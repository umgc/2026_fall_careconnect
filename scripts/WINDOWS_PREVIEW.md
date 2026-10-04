# Run the Windows desktop preview without OpenSSL or NuGet

From the repository root in PowerShell:

```powershell
.\scripts\run-windows-preview.ps1
```

The launcher finds Flutter on PATH, or uses `$env:USERPROFILE\flutter\bin\flutter.bat`.
This machine already has the required Flutter SDK and Visual Studio C++ build tools.
Android tooling and Chrome are not required for the Windows app.

To connect to an existing backend:

```powershell
.\scripts\run-windows-preview.ps1 -BackendUrl 'https://your-backend.example'
```

The default is `http://localhost:8080`. The script does not start the backend.
Login and server-backed operations require that backend to be reachable.
You can use a hosted backend without installing a local database or Docker.

The launcher prepares an isolated copy under `tmp/windows-online` and resolves
dependencies from the existing pub cache with `flutter pub get --offline`.
It does not edit the production frontend or the global package cache.
Normal Flutter builds still use the full dependency set.

This preview disables:

- **Offline saving and replay:** `sqlcipher_flutter_libs` requires OpenSSL during
  Windows CMake configuration. Merely skipping initialization does not remove
  that build dependency. The preview removes SQLCipher and SQLite, disables
  offline queuing, and rejects attempts to queue writes instead of claiming
  they were saved. Existing encrypted database files are left untouched.
- **Text-to-speech:** `flutter_tts` requires `nuget.exe` and CppWinRT.
- **GPS and native permission integration:** `geolocator_windows` and
  `permission_handler_windows` use NuGet/CppWinRT. The preview omits their native
  plugins. Features calling those integrations are unavailable.

Other native libraries used by the app are still bundled. Some plugin build
steps may fetch bundled libraries; this is not a completely network-free build.
This mode is intended for desktop development and UI review, not a full-feature
production release.

The existing secure-storage plugin also needs optional ATL headers. The preview
copies that plugin and substitutes Win32 string conversions for its ATL helpers;
its credential storage and encryption code remain enabled.

To build without launching:

```powershell
.\scripts\run-windows-preview.ps1 -BuildOnly
```

The debug executable is created at
`tmp/windows-online/build/windows/x64/runner/Debug/care_connect_app.exe`.
Keep it with its DLLs and `data` directory when running it.
