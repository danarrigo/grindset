# App updates

Settings > **App updates > Check for updates** is available from v1.2.0. Older installations need one manual update to gain the button.

Checks load the installed version using `package_info_plus`, then anonymously fetch the public HTTPS feed. They do not send account credentials, usage or device identifiers. There is no automatic startup check or forced update. Numeric stable-version comparison ignores the installed build suffix and never offers equal/older versions. A failed check remains an error, not an up-to-date result.

An available release shows its notes. **Download update** uses the external browser to download the Windows x64 installer or Android ARM64 APK from the fixed public distribution repository. The feed supplies only the version/notes, not arbitrary launch URLs. The OS/user must run or approve installation. This is not an in-process package downloader or silent installer and requests no Android package-install permission.

Install over the existing release to retain data. The Android package and signing key and the Windows app/storage identities remain stable. Android's package installer enforces its signing identity; differently signed debug previews cannot be replaced by the release APK. Export before changing installation/signing identity. Windows installers remain unsigned. Never bypass security protections to install an update.

## Publication

- Private app source: `danarrigo/grindset`.
- Public website, feed and binaries: `danarrigo/grindset-releases`.
- Website source: `site/` in the private repository, copied as the public repository's root. Never copy the app repository, ignored config, credentials or signing material there.
- Feed: `https://danarrigo.github.io/grindset-releases/latest.json`, schema `1`, stable `version`, plain-text `notes`.
- Publish and verify all public release assets before updating `latest.json`. Retain previous releases so clients with a cached feed can still download their advertised version. Source remains private; public distribution does not imply store review or continuous enforcement certification.

The existing manual Verify workflow builds and verifies the retained-key Android APK and the unsigned Windows installer. Release publication is an explicit owner-approved operation, not a new automated control plane. GitHub credentials remain in the publishing environment, never in clients or the feed.
