# Commit notes: Help Center entry and temporary Windows preview

## Suggested commit title

Add Help entry under General settings and a separate Help Center screen

## Suggested commit body

Add Help as the first entry under Settings > General, before Offline
Persistence. Selecting Help pushes the /help route and opens a separate Help
Center screen. Standard back navigation returns to Settings. Include a help
icon, descriptive subtitle, and a placeholder for the articles planned in later
steps. Record the Settings Help tap using the existing telemetry pattern.

Add English localization keys and regenerate the missing-translation report.
Other locales currently fall back to English for the new Help text.

Validation: all 90 existing Settings widget tests passed. Analysis of the
changed screen, Settings page, and router found no errors; it reported one
existing unused-import warning and six existing async-context lint notices.
The running Windows preview was updated through a hot restart.

The temporary Windows preview changes listed below are local development work
and should be excluded from the Help feature commit if they will be removed
before pushing.

## Help feature files to keep

| File | Exact change |
| --- | --- |
| `frontend/lib/pages/settings_page.dart` | Inserted a Help settings card immediately after the General heading and before Offline Persistence. Uses `Icons.help_outline`, localized title/subtitle, existing button-tap telemetry, and `context.push('/help')`. |
| `frontend/lib/config/router/app_router.dart` | Added the `HelpCenterPage` import and a `/help` GoRoute. |
| `frontend/lib/features/help/presentation/pages/help_center_page.dart` | New standalone screen with a Help Center AppBar, automatic back navigation when pushed from Settings, and localized placeholder text. No FAQ/category/search implementation yet. |
| `frontend/lib/l10n/app_en.arb` | Added `settingsHelp`, `settingsHelpDesc`, `helpCenterTitle`, and `helpCenterPlaceholder`. |
| `frontend/missing_translations.txt` | Regenerated the report to include the four new Help keys in non-English locales. This file was already marked modified before this work; do not blindly restore the entire file to HEAD. |
| `docs/commit-notes/help-center-step-1.md` | This change inventory and restoration record. Keep with the feature if desired. |

Flutter also regenerated these ignored files under `frontend/lib/l10n/`:
`app_localizations.dart`, `app_localizations_am.dart`,
`app_localizations_ar.dart`, `app_localizations_bn.dart`,
`app_localizations_en.dart`, `app_localizations_es.dart`,
`app_localizations_fa.dart`, `app_localizations_fr.dart`,
`app_localizations_hi.dart`, `app_localizations_ja.dart`,
`app_localizations_ne.dart`, `app_localizations_pt.dart`,
`app_localizations_ru.dart`, `app_localizations_ur.dart`, and
`app_localizations_zh.dart`. They can be regenerated with `flutter gen-l10n`;
they are not source files to stage under the current ignore rules.

## Temporary Windows preview files to exclude or remove before pushing

The full frontend dependencies were **not removed from the original app**.
The launcher creates a separate working copy at `tmp/windows-online/` and
changes only that copy to avoid OpenSSL, NuGet/CppWinRT, and optional ATL headers.
No additional add-ons were installed during this work.

| Repository file | Temporary change | Restoration action |
| --- | --- | --- |
| `.gitignore` | Added exactly one line: `/tmp/windows-online/`. | Remove only that line after the generated preview is removed or otherwise excluded from staging. Preserve all other ignore rules. |
| `scripts/run-windows-preview.ps1` | New launcher that copies the frontend, applies the preview-only edits listed below, resolves cached packages with `pub get --offline`, and builds/runs Windows in debug mode. Defaults to `http://localhost:8080`; supports `-BackendUrl`, `-FlutterPath`, and `-BuildOnly`. | Exclude/remove this new file when retiring the temporary preview. |
| `scripts/windows-string-conversions.h` | New Win32 ANSI/wide string conversion helpers replacing ATL helpers in the copied secure-storage plugin. | Exclude/remove this new file with the preview launcher. |
| `scripts/WINDOWS_PREVIEW.md` | New documentation for the preview, disabled features, and launch commands. | Exclude/remove this new file when retiring the temporary preview. |

## Exact changes inside the generated preview

All paths in this table start at `tmp/windows-online/`. These are ignored local
files, not edits to the original `frontend/` files or the global Pub cache.

| Preview path | Exact modification and purpose |
| --- | --- |
| `pubspec.yaml` | Removed the direct `sqlite3` and `sqlcipher_flutter_libs` entries from the copied manifest. Added path overrides for the six copied packages below. This removes the SQLCipher Windows OpenSSL build requirement from the preview. |
| `pubspec.lock` | Copied the original local lockfile, then resolved it for the preview manifest and local overrides. Generated package configuration and plugin registration files likewise reflect the preview dependencies. |
| `lib/services/local_db/app_database.dart` | Replaced the copied native database implementation with the existing web stub, but changed its enqueue operation to throw `UnsupportedError` rather than claim an offline write was saved. No persistent offline queue in this preview. |
| `lib/providers/user_provider.dart` | Changed `offlineModeEnabled` to return `false`, preventing the normal API flow from queuing offline writes. |
| `preview_plugins/flutter_tts/pubspec.yaml` | Removed the copied package's `flutter` plugin metadata so its NuGet-dependent native implementation is not built. Text-to-speech is unavailable. |
| `preview_plugins/geolocator/pubspec.yaml` | Removed copied plugin metadata, including the default native implementation reference. |
| `preview_plugins/geolocator_windows/pubspec.yaml` | Removed copied plugin metadata so the NuGet/CppWinRT GPS implementation is not built. GPS features are unavailable. |
| `preview_plugins/permission_handler/pubspec.yaml` | Removed copied plugin metadata, including the default native implementation reference. |
| `preview_plugins/permission_handler_windows/pubspec.yaml` | Removed copied plugin metadata so the NuGet/CppWinRT permission implementation is not built. Native permission integration is unavailable. |
| `preview_plugins/flutter_secure_storage_windows/windows/flutter_secure_storage_windows_plugin.cpp` | Replaced `#include <atlstr.h>` with the local conversion header. Replaced `CA2W` declarations with `WidenWindowsString`, `.m_psz` with `.data()`, and `CW2A` with `NarrowWindowsString`. Credential storage and encryption logic remain enabled. |
| `preview_plugins/flutter_secure_storage_windows/windows/windows-string-conversions.h` | Copied the new helper header from `scripts/windows-string-conversions.h`. The copied secure-storage package retains its plugin metadata and is selected through a path override. |
| `windows/CMakeLists.txt` | Made the existing `CMAKE_INSTALL_PREFIX` assignment to the executable's bundle directory unconditional in the preview. Prevents a failed earlier configuration from leaving a cached `Program Files` destination. |
| `assets` | Directory junction to the original `frontend/assets`; the large model assets were not duplicated or deleted. Any cleanup must remove the junction without deleting its target. |
| `conversion-test/CMakeLists.txt`, `conversion-test/main.cpp`, `conversion-test/windows-string-conversions.h`, and `conversion-test/build/` | Disposable local test project for the replacement string helpers. Empty strings, credential keys, and accented-text conversion checks passed. |
| `build/`, `.dart_tool/`, `.flutter-plugins-dependencies`, and `windows/flutter/` generated plugin/ephemeral files | Normal generated artifacts for the preview build. Never stage these as Help feature source. |

The Help source files and generated localization Dart files were also copied
into this preview so the running app could display the new Help entry. Keep
developing the original `frontend/` files; the launcher recreates the preview
from them.

## Original files that do not need dependency restoration

The following original files were not modified to strip features:

- `frontend/pubspec.yaml`: still includes SQLite, SQLCipher, text-to-speech,
  geolocation, permission handling, and the original dependency configuration.
- `frontend/lib/services/local_db/app_database.dart`: retains the native
  SQLCipher implementation.
- `frontend/lib/providers/user_provider.dart`: retains the original offline
  persistence behavior.
- `frontend/windows/CMakeLists.txt`: retains its original CMake logic.
- The hosted Pub cache packages: no original package manifests, native source,
  or CMake files were patched there.

There were no backend source edits, database credential changes, new account
creation, or password resets. The existing caregiver demo login was verified
against the running local backend. Existing encrypted database files and
original assets were not deleted.

## Restoration checklist before pushing

1. Keep the Help feature files listed above. Do not restore the whole Settings
   page, router, English ARB, or missing-translation report to undo the preview.
2. Stop using the preview launcher and close the preview app before removing
   its local working directory. Avoid deleting the asset junction's target.
3. Exclude/remove the three new preview files under `scripts/` listed above.
4. Remove the generated `tmp/windows-online/` copy if desired, then remove only
   the `/tmp/windows-online/` line added to `.gitignore`. If keeping the local
   copy, keep it excluded through a local ignore rule before removing that line.
5. There are no dependencies to add back to `frontend/pubspec.yaml`: they are
   already present. Build from the original `frontend/` when validating the
   full app. Its original Windows requirements still apply: OpenSSL for
   SQLCipher, NuGet/CppWinRT for the identified plugins, and ATL headers for
   the unmodified secure-storage plugin.
6. Review the staged file list. Confirm no preview files, copied package
   overrides, generated build artifacts, or temporary test project are staged.
7. Run the appropriate full-app checks in an environment with those original
   requirements available. The successful preview build does not verify the
   native integrations disabled in the preview.

No restoration, file deletion, commit, or push was performed while writing
these notes.
