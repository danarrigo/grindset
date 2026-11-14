# Install and update packages

Grindset releases are personal-use distribution, not a Play Store submission or a Windows trust certificate. Packaging does not establish native enforcement or cloud validation.

## Windows

Build with Windows Flutter and the Visual Studio C++ workload:

```powershell
flutter pub get
flutter build windows --release
./tool/package_windows.ps1
```

The packaging script requires Inno Setup 6.4 or newer and the Visual C++ redistributable files installed with Visual Studio. It bundles the CRT app-locally, then creates `build/installers/grindset-<version>-windows-x64-setup.exe`.

- Per-user installation under `%LOCALAPPDATA%\Programs\Grindset`, without elevation.
- Stable installer identity `app.lockin.lockin`, Start-menu shortcut, optional desktop shortcut, and the notification AppUserModelID.
- Sign-in startup is not enabled by the installer; the app's tracking opt-in controls it.
- Updates close the installed app and replace its executable/assets. The normal application-support journal and auth storage remain outside the install directory and are preserved. Existing installations retain their previous install directory; fresh installations use Grindset.
- The legacy Android package ID, Windows installer/AppUserModelID, startup registry key, executable name (`lockin.exe`), Dart package, Windows resource identity and storage/export schema identifiers are intentionally retained. Windows resource identity determines the application-support/auth location; changing it just for branding would strand existing data. Visible app, tray, notification, shortcut, extension and installer labels use Grindset. Historical acceptance evidence and local SDK/signing paths retain their original names.
- Uninstall preserves app data. Use Settings > Reset this device first to clear local data and sign out. Uninstall removes the startup entry only when it points at this installation.
- The installer is **unsigned**. SmartScreen/trust warnings remain possible. No publisher certificate has been purchased or configured.

The Verify workflow builds the installer and runs a silent install, the existing native startup/close-to-tray checks against the installed executable, and uninstall on an ephemeral Windows runner. It uploads `grindset-windows-installer-unsigned` alongside the portable `grindset-windows-unsigned` bundle. A runner smoke check is not a clean physical-machine certification.

Existing `--data-dir` previews use explicitly selected journals. They do not register themselves for Windows sign-in startup or remove the normal installation's startup entry on reset; their tracking disclosure makes that distinction explicit. Installing the app does not silently import those folders or change the account identity. Preserve/export the old preview's data before deciding how to move it.

### Defender acceptance blocker (2026-11-13)

During native testing of the `4791d85` portable artifact, opting into tracking registered its temporary executable as `HKCU` sign-in startup. Microsoft Defender classified that behavior as `Behavior:Win32/Persistence.A!ml` (threat ID `2147737394`), terminated PID `27544` and quarantined the executable. Its detection timestamp was `08:31:01 UTC`; the owned journal's final tracking heartbeat was `08:32:11.464199 UTC`. This is not a confirmed false-positive determination or successful native tracking acceptance.

The source now prevents `--data-dir` previews from enabling or disabling sign-in startup. Regression tests cover both operations, normal-installation behavior and the tracking disclosure. The rebuilt `14b597f` artifact from CI run `43403540374` subsequently ran real foreground tracking and Chrome website/idle/video checks with Defender real-time protection enabled, no sign-in startup entry and no new detection for that preview. This validates preview startup isolation, not the installer or ordinary sign-in registration against Defender. Defender was not disabled, excluded, or bypassed, and the quarantined executable was not restored.

## Android stable signing

Release builds no longer fall back to the debug key. Without complete owner signing configuration they fail before packaging. Ordinary debug builds still work.

For a local release, copy `android/key.properties.example` to ignored `android/key.properties`, or supply:

- `LOCKIN_KEYSTORE_PATH`
- `LOCKIN_KEYSTORE_PASSWORD`
- `LOCKIN_KEY_ALIAS`
- `LOCKIN_KEY_PASSWORD`

Keep the keystore outside git, retain an offline backup, and use the same key/package ID for every update. Increase the build number for subsequent releases. Losing the signing key can prevent updating an existing installation.

A manual run of **Verify and build** calls the reusable **Build signed Android APK** workflow, including on the feature branch without merging `main`. Push/PR builds do not access the signing secrets. The signed job expects these repository secrets:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded owner-controlled keystore |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Existing signing alias |
| `ANDROID_KEY_PASSWORD` | Alias password |

The workflow builds an ARM64 release with the same key, uses the increasing **Verify and build** run number as the base build number, verifies the APK with Android's `apksigner`, and removes runner key material afterward. All signed builds use this single entry point to avoid competing version counters. Use a higher build number for local builds that must update a workflow-built APK. Manual signing runs are not cancelled by later pushes.

Owner-approved signing material is provisioned outside git at `~/.local/share/lockin/signing/`: `lockin-release.p12`, owner-only `credentials.json`, and public `certificate.der`. The four encrypted repository secrets above are configured. An encrypted Google Drive backup was owner-confirmed and recovery-verified at `2026-11-13T09:36:41Z`: the downloaded archive decrypted successfully and all three recovered files exactly matched the originals. The owner retains the backup passphrase separately on paper; it was not sent to the agent or stored in the repository. The verification receipt is local at `~/.local/share/lockin/signing-backup-verification.txt`. GitHub secrets cannot be downloaded as a recovery copy. Do not replace or regenerate this key for later updates.

Public signing-certificate SHA-256: `e5cd43267649b0cda8082dac47eab1332c1d826f9308d3ddbe503df57cf9ac38`. Signed artifacts include `signing-certificate.txt` so the certificate can be compared without exposing private key material. The first owner-key build, run `43337652818`, passed APK signature verification and all jobs. That build preceded public Supabase configuration and is local-mode; use a later configured build for cloud access.

**Debug previews are a different signing identity.** Older CI debug keys may be unrecoverable and cannot be made upgrade-compatible by this configuration. Do not uninstall a personal installation to work around a signature mismatch without preserving its data. JSON export is an archive, not an automatic in-app restore/migration feature.

## Optional cloud configuration

Native CI builds use repository **variables** `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`. Both empty means local mode. Both set means the public configuration is compiled into the app. Legacy `anon` keys are supported; privileged/service-role keys are rejected. Never supply admin credentials to a client build.

The build itself does not create a Supabase project or apply migrations. The owner's project and public variables are now configured; see [deployment state](supabase-deployment.md). Live Auth/email and two-device acceptance remain separate from successful signed packaging.
