import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lockin/platform/native_tracker.dart';
import 'package:lockin/platform/windows_apps.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Windows app metadata accepts spaces but rejects executable paths and malformed rows', () {
    final app = WindowsApp.fromMap({
      'source': 'windows:test app.exe',
      'name': 'Test App',
      'running': true,
    });
    expect(app.source, 'windows:test app.exe');
    expect(app.running, isTrue);
    for (final source in [
      'windows:C:\\test.exe',
      'windows:folder/test.exe',
      'web:test.exe',
      'windows:test\n.exe',
      'windows:test',
    ]) {
      expect(
        () => WindowsApp.fromMap({'source': source, 'name': 'Test'}),
        throwsFormatException,
      );
    }
    expect(
      () => WindowsApp.fromMap({'source': 'windows:test.exe', 'name': ''}),
      throwsFormatException,
    );
  });
  test(
    'app discovery asks the native metadata API without requesting tracking',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(NativeTracker.windowsChannel, (
        MethodCall call,
      ) async {
        expect(call.method, 'listWindowsApps');
        expect(call.arguments, isNull);
        return [
          {'source': 'windows:discord.exe', 'name': 'Discord', 'running': true},
        ];
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          NativeTracker.windowsChannel,
          null,
        ),
      );
      expect((await WindowsApps.list()).single.name, 'Discord');
    },
  );
}
