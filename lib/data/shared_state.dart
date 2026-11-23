import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import '../core/activity.dart';
import '../core/focus_session.dart';
import 'local_store.dart';

class SharedChange {
  const SharedChange({
    required this.kind,
    required this.id,
    required this.mutationId,
    required this.baseRevision,
    required this.value,
    this.bootstrap = false,
  });
  final String kind;
  final String id;
  final String mutationId;
  final int baseRevision;
  final Map<String, dynamic>? value;
  final bool bootstrap;
  Map<String, Object?> toJson() => {
    'kind': kind,
    'id': id,
    'mutation_id': mutationId,
    'base_revision': baseRevision,
    'value': value,
  };
  factory SharedChange.fromRow(QueryRow row) => SharedChange(
    kind: row.read<String>('kind'),
    id: row.read<String>('id'),
    mutationId: row.read<String>('mutation_id'),
    baseRevision: row.read<int>('base_revision'),
    value: _decode(row.readNullable<String>('value')),
    bootstrap: row.read<int>('bootstrap') != 0,
  );
}

class SharedConflict {
  const SharedConflict({
    required this.change,
    required this.confirmedValue,
    required this.confirmedRevision,
  });
  final SharedChange change;
  final Map<String, dynamic>? confirmedValue;
  final int confirmedRevision;
}

Map<String, dynamic>? _decode(String? value) =>
    value == null ? null : jsonDecode(value) as Map<String, dynamic>;
String? _encode(Map<String, dynamic>? value) =>
    value == null ? null : jsonEncode(value);

/// Durable compare-and-set state, separate from append/extend-only usage sync.
/// Confirmed policy wins conflicts; losing edits remain available for review.
class SharedState {
  SharedState(this.store, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final LocalStore store;
  final DateTime Function() _clock;
  final _uuid = const Uuid();
  DateTime get _now => _clock().toUtc();

  Future<int> revision(String kind, String id) async {
    final row = await store
        .customSelect(
          'SELECT revision FROM sync_entities WHERE kind=? AND id=?',
          variables: [Variable(kind), Variable(id)],
        )
        .getSingleOrNull();
    return row?.read<int>('revision') ?? 0;
  }

  Future<void> queue(
    String kind,
    String id,
    Map<String, dynamic>? value, {
    bool bootstrap = false,
    int? baseRevision,
  }) => store.transaction(() async {
    await store.customStatement(
      '''INSERT INTO sync_outbox(kind,id,mutation_id,base_revision,value,bootstrap) VALUES(?,?,?,?,?,?)
      ON CONFLICT(kind,id) DO UPDATE SET mutation_id=excluded.mutation_id,base_revision=excluded.base_revision,value=excluded.value,bootstrap=excluded.bootstrap''',
      [
        kind,
        id,
        _uuid.v4(),
        baseRevision ?? await revision(kind, id),
        _encode(value),
        bootstrap ? 1 : 0,
      ],
    );
  });

  Future<List<SharedChange>> pending({
    bool focusOnly = false,
    bool excludeFocus = false,
  }) async {
    final rows = await store
        .customSelect(
          'SELECT * FROM sync_outbox ${focusOnly
              ? "WHERE kind='focus'"
              : excludeFocus
              ? "WHERE kind<>'focus'"
              : ''} ORDER BY kind,id',
        )
        .get();
    return rows.map(SharedChange.fromRow).toList();
  }

  Future<List<SharedConflict>> conflicts() async {
    final rows = await store.customSelect(
      '''SELECT c.kind,c.id,c.mutation_id,c.remote_revision AS base_revision,c.value,0 AS bootstrap,
      e.value AS confirmed_value,coalesce(e.revision,c.remote_revision) AS confirmed_revision
      FROM sync_conflicts c LEFT JOIN sync_entities e ON e.kind=c.kind AND e.id=c.id ORDER BY c.kind,c.id''',
    ).get();
    return rows
        .map(
          (row) => SharedConflict(
            change: SharedChange.fromRow(row),
            confirmedValue: _decode(
              row.readNullable<String>('confirmed_value'),
            ),
            confirmedRevision: row.read<int>('confirmed_revision'),
          ),
        )
        .toList();
  }

  Future<void> rememberFocusFlag(ActivityRule rule) async {
    final flags =
        _decode(await store.setting('focus_flags')) ?? <String, dynamic>{};
    flags[rule.id] = rule.focusBlock;
    await store.saveSetting('focus_flags', jsonEncode(flags));
  }

  static Map<String, dynamic> sharedRule(ActivityRule rule) =>
      Map<String, dynamic>.from(rule.toJson())..remove('focus_block');

  Future<void> seed() => store.transaction(() async {
    if (await store.setting('shared_seeded') == 'true') return;
    Future<void> seedOne(
      String kind,
      String id,
      Map<String, dynamic> value, {
      bool bootstrap = true,
    }) async {
      final queued = await store
          .customSelect(
            'SELECT 1 FROM sync_outbox WHERE kind=? AND id=?',
            variables: [Variable(kind), Variable(id)],
          )
          .getSingleOrNull();
      if (queued == null && await revision(kind, id) == 0) {
        await queue(kind, id, value, bootstrap: bootstrap);
      }
    }

    for (final rule in await store.rules()) {
      await rememberFocusFlag(rule);
      await seedOne('rule', rule.id, sharedRule(rule), bootstrap: false);
    }
    await seedOne('setting', 'timezone', {
      'timezone': await store.setting('timezone') ?? 'UTC',
    });
    final strict = await store.setting('strict_mode');
    if (strict != null) {
      await seedOne('setting', 'strict_mode', {'enabled': strict == 'true'});
    }
    final focusHours = await store.setting('focus_hours');
    if (focusHours != null) {
      final saved = await store.setting('focus_hours_saved');
      final schedules = jsonDecode(focusHours) as List;
      await seedOne('setting', 'focus_hours', {
        'schedules': schedules,
        if (schedules.isEmpty && saved != null && saved != '[]')
          'saved': jsonDecode(saved),
      });
    }
    final active = _decode(await store.setting('active_session'));
    if (active != null) {
      await seedOne('focus', 'active', active, bootstrap: false);
    }
    for (final row
        in await store.customSelect('SELECT value FROM sessions').get()) {
      final session = _decode(row.read<String>('value'))!;
      await seedOne('session', session['id'] as String, session);
    }
    await store.saveSetting('shared_seeded', 'true');
  });

  Future<void> accept(
    SharedChange change, {
    required bool applied,
    required Map<String, dynamic> record,
  }) => store.transaction(() async {
    if (record['kind'] != change.kind || record['id'] != change.id) {
      throw const FormatException(
        'A sync acknowledgement changed entity identity.',
      );
    }
    final pending = await store
        .customSelect(
          'SELECT mutation_id FROM sync_outbox WHERE kind=? AND id=?',
          variables: [Variable(change.kind), Variable(change.id)],
        )
        .getSingleOrNull();
    final same = pending?.read<String>('mutation_id') == change.mutationId;
    if (same) {
      if (!applied &&
          !change.bootstrap &&
          {'rule', 'setting'}.contains(change.kind)) {
        await store.customStatement(
          'INSERT OR REPLACE INTO sync_conflicts(mutation_id,kind,id,value,remote_revision) VALUES(?,?,?,?,?)',
          [
            change.mutationId,
            change.kind,
            change.id,
            _encode(change.value),
            record['revision'],
          ],
        );
      }
      if (!applied && change.kind == 'focus') {
        await store.saveSetting(
          'shared_notice',
          'Focus changed on another device. The confirmed shared session is now shown; elapsed local focus is kept in history.',
        );
      }
      await store.customStatement(
        'DELETE FROM sync_outbox WHERE mutation_id=?',
        [change.mutationId],
      );
    } else if (applied) {
      // Rebase a newer local snapshot only over our own acknowledged predecessor.
      await store.customStatement(
        'UPDATE sync_outbox SET base_revision=? WHERE kind=? AND id=? AND base_revision=?',
        [record['revision'], change.kind, change.id, change.baseRevision],
      );
    }
    await _receive(record);
  });

  Future<void> receive(Map<String, dynamic> record) =>
      store.transaction(() => _receive(record));

  Future<void> _receive(Map<String, dynamic> record) async {
    final kind = record['kind'] as String;
    final id = record['id'] as String;
    final remoteRevision = record['revision'] as int;
    if (!{'rule', 'setting', 'focus', 'session'}.contains(kind) ||
        remoteRevision <= 0) {
      throw const FormatException('Invalid shared state revision.');
    }
    var value = record['value'] == null
        ? null
        : Map<String, dynamic>.from(record['value'] as Map);
    final existing = await store
        .customSelect(
          'SELECT revision,value FROM sync_entities WHERE kind=? AND id=?',
          variables: [Variable(kind), Variable(id)],
        )
        .getSingleOrNull();
    if (existing != null && existing.read<int>('revision') > remoteRevision) {
      value = _decode(existing.readNullable<String>('value'));
    } else {
      await store.customStatement(
        'INSERT INTO sync_entities(kind,id,revision,value) VALUES(?,?,?,?) ON CONFLICT(kind,id) DO UPDATE SET revision=excluded.revision,value=excluded.value',
        [kind, id, remoteRevision, _encode(value)],
      );
    }
    final pending = await store
        .customSelect(
          'SELECT 1 FROM sync_outbox WHERE kind=? AND id=?',
          variables: [Variable(kind), Variable(id)],
        )
        .getSingleOrNull();
    if (pending == null) await _apply(kind, id, value);
  }

  Future<FocusSession> _history(FocusSession session) async {
    final row = await store
        .customSelect(
          'SELECT value FROM sessions WHERE id=?',
          variables: [Variable(session.id)],
        )
        .getSingleOrNull();
    final previous = row == null
        ? null
        : FocusSession.fromJson(_decode(row.read<String>('value'))!);
    if (previous != null &&
        (previous.start != session.start || previous.phase != session.phase)) {
      throw const FormatException('Session identity is immutable.');
    }
    final effective = previous != null && previous.end.isBefore(session.end)
        ? previous
        : session;
    await store.customStatement(
      'INSERT INTO sessions(id,value) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET value=excluded.value',
      [effective.id, jsonEncode(effective.toJson())],
    );
    return effective;
  }

  Future<void> _apply(
    String kind,
    String id,
    Map<String, dynamic>? value,
  ) async {
    switch (kind) {
      case 'rule':
        final rules = await store.rules();
        final previous = rules.where((r) => r.id == id).firstOrNull;
        final flags = _decode(await store.setting('focus_flags'));
        final next = rules.where((r) => r.id != id).toList();
        if (value != null) {
          if (value['id'] != id) {
            throw const FormatException('A rule changed identity.');
          }
          next.add(
            ActivityRule.fromJson({
              ...value,
              'focus_block': previous?.focusBlock ?? flags?[id] == true,
            }),
          );
        }
        await store.saveRules(next);
      case 'setting' when id == 'strict_mode':
        if (value == null || value['enabled'] is! bool) {
          throw const FormatException('Invalid strict mode.');
        }
        await store.saveSetting('strict_mode', '${value['enabled']}');
      case 'setting' when id == 'focus_hours':
        if (value == null || value['schedules'] is! List) {
          throw const FormatException('Invalid Focus hours.');
        }
        final encoded = jsonEncode(value['schedules']);
        decodeFocusHours(encoded); // Rejects invalid windows before saving.
        // Older versions send no "saved" times; keep this device's then.
        final saved = (value['schedules'] as List).isNotEmpty
            ? encoded
            : value['saved'] is List
            ? jsonEncode(value['saved'])
            : null;
        if (saved != null) decodeFocusHours(saved);
        await store.saveSetting('focus_hours', encoded);
        if (saved != null) await store.saveSetting('focus_hours_saved', saved);
      case 'setting':
        if (id != 'timezone' || value == null || value['timezone'] is! String) {
          throw const FormatException('Invalid shared setting.');
        }
        final timezone = value['timezone'] as String;
        tz.getLocation(timezone);
        await store.saveSetting('timezone', timezone);
      case 'focus':
        if (id != 'active') {
          throw const FormatException('Invalid shared session slot.');
        }
        final oldValue = _decode(await store.setting('active_session'));
        final old = oldValue == null ? null : FocusSession.fromJson(oldValue);
        final next = value == null ? null : FocusSession.fromJson(value);
        if (old != null && old.id != next?.id && old.end.isAfter(_now)) {
          if (_now.isAfter(old.start)) {
            final stopped = old.finish(_now);
            await _history(stopped);
            await queue('session', old.id, stopped.toJson());
          } else {
            // A zero-elapsed losing start is not fabricated into a positive interval.
            await store.customStatement('DELETE FROM sessions WHERE id=?', [
              old.id,
            ]);
            if (await revision('session', old.id) == 0) {
              await store.customStatement(
                "DELETE FROM sync_outbox WHERE kind='session' AND id=?",
                [old.id],
              );
            } else {
              await queue('session', old.id, null);
            }
          }
        }
        if (next == null) {
          await store.customStatement(
            "DELETE FROM settings WHERE key='active_session'",
          );
        } else {
          final effective = await _history(next);
          await store.saveSetting(
            'active_session',
            jsonEncode(effective.toJson()),
          );
        }
      case 'session':
        if (value == null) {
          await store.customStatement('DELETE FROM sessions WHERE id=?', [id]);
        } else {
          final next = FocusSession.fromJson(value);
          if (next.id != id) {
            throw const FormatException('Session history changed identity.');
          }
          await _history(next);
          final active = _decode(await store.setting('active_session'));
          if (active?['id'] == id &&
              next.end.isBefore(FocusSession.fromJson(active!).end)) {
            await store.saveSetting(
              'active_session',
              jsonEncode(next.toJson()),
            );
          }
        }
    }
  }

  Future<void> resolveConflict(
    String mutationId, {
    required bool retry,
    int? baseRevision,
  }) => store.transaction(() async {
    final rows = await conflicts();
    final conflict = rows
        .where((r) => r.change.mutationId == mutationId)
        .firstOrNull;
    if (conflict == null) return;
    if (retry) {
      final change = conflict.change;
      await queue(
        change.kind,
        change.id,
        change.value,
        baseRevision: baseRevision ?? conflict.confirmedRevision,
      );
      await _apply(change.kind, change.id, change.value);
    }
    await store.customStatement(
      'DELETE FROM sync_conflicts WHERE mutation_id=?',
      [mutationId],
    );
  });
}
