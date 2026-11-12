import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/platform/desktop_lifecycle.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const windowChannel = MethodChannel('window_manager');
  const trayChannel = MethodChannel('tray_manager');
  const screenChannel = MethodChannel(
    'dev.leanflutter.plugins/screen_retriever',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const display = {
    'id': '0',
    'size': {'width': 1920.0, 'height': 1080.0},
    'visiblePosition': {'dx': 0.0, 'dy': 0.0},
    'visibleSize': {'width': 1920.0, 'height': 1040.0},
    'scaleFactor': 1,
  };

  for (final background in [true, false]) {
    test(
      '${background ? 'background' : 'normal'} startup awaits its OS visibility operation',
      () async {
        final visibilityStarted = Completer<void>();
        final visibilityFinished = Completer<void>();
        final calls = <String>[];
        final visibilityMethod = background ? 'hide' : 'show';
        messenger.setMockMethodCallHandler(windowChannel, (call) async {
          calls.add(call.method);
          if (call.method == visibilityMethod) {
            visibilityStarted.complete();
            await visibilityFinished.future;
            return null;
          }
          return switch (call.method) {
            'isFullScreen' || 'isMaximized' || 'isMinimized' => false,
            'getBounds' => {
              'x': 0.0,
              'y': 0.0,
              'width': 400.0,
              'height': 600.0,
            },
            _ => null,
          };
        });
        messenger.setMockMethodCallHandler(trayChannel, (_) async => null);
        messenger.setMockMethodCallHandler(
          screenChannel,
          (call) async => switch (call.method) {
            'getPrimaryDisplay' => display,
            'getAllDisplays' => {
              'displays': [display],
            },
            'getCursorScreenPoint' => {'dx': 100.0, 'dy': 100.0},
            _ => null,
          },
        );
        final lifecycle = DesktopLifecycle(quit: () async {});
        var completed = false;
        final initialization = lifecycle
            .initialize(background: background)
            .then((_) {
              completed = true;
            });
        addTearDown(() async {
          if (!visibilityFinished.isCompleted) visibilityFinished.complete();
          await initialization;
          await lifecycle.dispose();
          for (final channel in [windowChannel, trayChannel, screenChannel]) {
            messenger.setMockMethodCallHandler(channel, null);
          }
        });

        await visibilityStarted.future.timeout(const Duration(seconds: 5));
        await Future<void>.delayed(Duration.zero);
        expect(
          completed,
          isFalse,
          reason: 'Startup must not finish while show/hide can still fail.',
        );
        visibilityFinished.complete();
        await initialization;
        expect(completed, isTrue);
        if (background) {
          expect(calls, isNot(contains('show')));
        } else {
          expect(calls, containsAllInOrder(['show', 'restore', 'focus']));
        }
      },
    );
  }
}
