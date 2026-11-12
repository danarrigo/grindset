# Install and update packages

This milestone is personal/preview distribution, not a Play Store submission or a Windows trust certificate. Packaging does not establish native enforcement or cloud validation.

## Windows

Build with Windows Flutter and the Visual Studio C++ workload:

```powershell
flutter pub get
flutter build windows --release
./tool/package_windows.ps1
```

The packaging script requires Inno Setup 6.4 or newer and the Visual C++ redistributable files installed with Visual Studio. It bundles the CRT app-locally, then creates `build/installers/lockin-<version>-windows-x64-setup.exe`.

- Per-user installation under `%LOCALAPPDATA%\Programs\Lockin`, without elevation.
- Stable installer identity `app.lockin.lockin`, Start-menu shortcut, optional desktop shortcut, and the notification AppUserModelID.
- Sign-in startup is not enabled by the installer; the app's tracking opt-in controls it.
- Updates close the installed app and replace its executable/assets. The normal application-support journal and auth storage remain outside the install directory and are preserved.
- Uninstall preserves app data. Use Settings > Reset this device first to clear local data and sign out. Uninstall removes the startup entry only when it points at this installation.
- The installer is **unsigned**. SmartScreen/trust warnings remain possible. No publisher certificate has been purchased or configured.

The Verify workflow builds the installer and runs a silent install, the existing native startup/close-to-tray checks against the installed executable, and uninstall on an ephemeral Windows runner. It uploads `lockin-windows-installer-unsigned` alongside the portable `lockin-windows-unsigned` bundle. A runner smoke check is not a clean physical-machine certification.

Existing `--data-dir` previews use explicitly selected journals. Installing the app does not silently import those folders or change the account identity. Preserve/export the old preview's data before deciding how to move it.

## Android stable signing

Release builds no longer fall back to the debug key. Without complete owner signing configuration they fail before packaging. Ordinary debug builds still work.

For a local release, copy `android/key.properties.example` to ignored `android/key.properties`, or supply:

- `LOCKIN_KEYSTORE_PATH`
- `LOCKIN_KEYSTORE_PASSWORD`
- `LOCKIN_KEY_ALIAS`
- `LOCKIN_KEY_PASSWORD`

Keep the keystore outside git, retain an offline backup, and use the same key/package ID for every update. Increase the build number for subsequent releases. Losing the signing key can prevent updating an existing installation.

The manual **Build signed Android APK** workflow expects these repository secrets:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded owner-controlled keystore |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Existing signing alias |
| `ANDROID_KEY_PASSWORD` | Alias password |

The workflow builds an ARM64 release with the same key, uses its increasing workflow run number as the base build number, and removes runner key material afterward. Use a higher build number for local builds that must update a workflow-built APK. Owner key generation, backup and secret provisioning require approval; no release key has been generated or uploaded automatically. The workflow must exist on the default branch before GitHub exposes manual dispatch.

**Debug previews are a different signing identity.** Older CI debug keys may be unrecoverable and cannot be made upgrade-compatible by this configuration. Do not uninstall a personal installation to work around a signature mismatch without preserving its data. JSON export is an archive, not an automatic in-app restore/migration feature.

## Optional cloud configuration

Native CI builds use repository **variables** `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`. Both empty means local mode. Both set means the public configuration is compiled into the app. Legacy `anon` keys are supported; privileged/service-role keys are rejected. Never supply admin credentials to a client build.

This does not create a Supabase project or apply migrations. Live Auth and two-device validation still require the owner's project and the migrations in `supabase/migrations/`.
