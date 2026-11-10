import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../core/activity.dart';

/// SQLite owns durable local state; no cloud connection is required to use it.
class LocalStore extends GeneratedDatabase {
  LocalStore(super.executor);
  factory LocalStore.file(File file) =>
      LocalStore(NativeDatabase.createInBackground(file));
  factory LocalStore.memory() => LocalStore(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (_) async {
      await customStatement(
        'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      await customStatement('''CREATE TABLE intervals (
      id TEXT PRIMARY KEY, device_id TEXT NOT NULL, source TEXT NOT NULL,
      start_ms INTEGER NOT NULL, end_ms INTEGER NOT NULL,
      dirty INTEGER NOT NULL DEFAULT 1, CHECK (end_ms > start_ms))''');
      await customStatement(
        'CREATE INDEX intervals_time ON intervals(end_ms, start_ms)',
      );
      await customStatement(
        'CREATE TABLE sessions (id TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
      await customStatement('PRAGMA journal_mode=WAL');
    },
  );

  Future<String?> setting(String key) async {
    final row = await customSelect(
      'SELECT value FROM settings WHERE key = ?',
      variables: [Variable(key)],
    ).getSingleOrNull();
    return row?.read<String>('value');
  }

  Future<void> saveSetting(String key, String value) => customStatement(
    'INSERT INTO settings(key,value) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value',
    [key, value],
  );

  Future<void> putUsage(UsageInterval interval, {bool pending = true}) =>
      customStatement(
        '''
    INSERT INTO intervals(id,device_id,source,start_ms,end_ms,dirty) VALUES (?,?,?,?,?,?)
    ON CONFLICT(id) DO UPDATE SET
      end_ms=MAX(intervals.end_ms,excluded.end_ms),
      dirty=CASE WHEN excluded.end_ms > intervals.end_ms
        THEN MAX(intervals.dirty,excluded.dirty) ELSE intervals.dirty END
    ''',
        [
          interval.id,
          interval.deviceId,
          interval.source,
          interval.start.millisecondsSinceEpoch,
          interval.end.millisecondsSinceEpoch,
          pending ? 1 : 0,
        ],
      );

  Future<List<UsageInterval>> usage({
    DateTime? from,
    bool pendingOnly = false,
  }) async {
    final rows = await customSelect(
      'SELECT * FROM intervals WHERE end_ms > ? ${pendingOnly ? 'AND dirty=1' : ''} ORDER BY start_ms',
      variables: [Variable(from?.millisecondsSinceEpoch ?? 0)],
    ).get();
    return rows
        .map(
          (row) => UsageInterval(
            id: row.read<String>('id'),
            deviceId: row.read<String>('device_id'),
            source: row.read<String>('source'),
            start: DateTime.fromMillisecondsSinceEpoch(
              row.read<int>('start_ms'),
              isUtc: true,
            ),
            end: DateTime.fromMillisecondsSinceEpoch(
              row.read<int>('end_ms'),
              isUtc: true,
            ),
          ),
        )
        .toList();
  }

  // A later observation may have extended this interval while an upload ran.
  Future<void> markUploaded(UsageInterval interval) => customStatement(
    'UPDATE intervals SET dirty=0 WHERE id=? AND end_ms=?',
    [interval.id, interval.end.millisecondsSinceEpoch],
  );

  Future<List<ActivityRule>> rules() async {
    final value = await setting('rules');
    if (value == null) return [];
    return (jsonDecode(value) as List)
        .map((r) => ActivityRule.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<void> saveRules(Iterable<ActivityRule> rules) =>
      saveSetting('rules', jsonEncode(rules.map((r) => r.toJson()).toList()));
}
