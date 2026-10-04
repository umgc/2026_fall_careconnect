# Help localization and translated content

Code paths and commands in this guide are relative to `frontend/`.

## Current behavior

Help screen labels use `AppLocalizations`. Article/category titles,
descriptions, sections, keywords, and custom headings are bundled English Dart
data. `HelpRepository.bundled()` always returns that English catalog, regardless
of the selected app locale. No translated-content selector is shipped yet.

The current Help labels are defined in `lib/l10n/app_en.arb`. Missing translations
in the other existing ARB files fall back to generated English values, and
`missing_translations.txt` records the omissions. This is an explicit fallback,
not a claim that Help is fully translated into all supported app languages.

## Translate screen labels now

1. Add the corresponding key/value to the target `lib/l10n/app_<locale>.arb`.
   Keep the English template key unchanged.
2. Preserve placeholder names and types. `helpSearchResultsCount` accepts the
   integer `count`; translate its ICU plural message using the target language's
   plural rules. Test zero, one, and several results.
3. Run `flutter gen-l10n` from `frontend/`. Review
   `missing_translations.txt`. Do not edit generated
   `app_localizations*.dart` files by hand.
4. Test the chosen locale, English fallback, long translated labels, and RTL
   layout where applicable. An English fallback should remain readable while
   translations are incomplete.

All Help UI labels, including empty-result actions and accessibility
announcements, must continue to come from `AppLocalizations`.

## Introduce the first translated article catalog

This is the concrete extension design for future translated content. Adding a
translated data file alone does not change today's runtime locale behavior.

1. Add a catalog under `data/locales/`, for example `help_content_es.dart`.
   Export translated categories and articles using the existing models and
   permanent constants from `help_content_ids.dart`.
2. Translate titles, summaries, category descriptions, paragraph text, numbered
   steps, troubleshooting text, custom headings, and search keywords. Preserve
   category IDs, article IDs, related IDs, role metadata, and featured order.
   Keep button names consistent with the target app locale.
3. Add a single shared locale resolver in the data layer, for example
   `HelpRepository.forLocale(languageCode: ..., scriptCode: ..., countryCode: ...)`.
   A locale registry should select an exact locale when registered, then a
   supported language catalog, then English. Pass strings to keep the repository
   independent of Flutter.
4. Resolve the active locale using `Localizations.localeOf(context)` when each
   Help screen builds, and pass it to that shared resolver whenever an injected
   test/preview repository is absent. Keep the injected repository override.
   This one-time wiring changes neither route patterns nor per-article screen
   layouts, and ensures a language change updates all Help screens consistently.
5. Validate each registered catalog through `HelpRepository`. Require the same
   article/category ID set as English for a complete translation. Until a locale
   is complete, leave it unregistered so the whole English catalog is the
   fallback; avoid mixed-language fragments or broken related links.
6. Add tests for exact locale selection, language fallback, unsupported-locale
   English fallback, switching locale on an open screen, identical ID/link sets,
   translated keyword search, and localized titles on related links. Keep these
   tests independent of backend connectivity.

After this resolver is wired, future translators add content files and register
catalogs in configuration without changing the router or article screen.
Route URLs and bookmarks remain identical across languages. Do not replace IDs
with translated titles or list positions.
