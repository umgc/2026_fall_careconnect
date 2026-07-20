import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LanguagePicker {
  static Future<void> show(BuildContext context) async {
    final locales = AppLocalizations.supportedLocales;
    final current = context.read<LocaleProvider>().locale;
    final t = AppLocalizations.of(context)!;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      // Allow the sheet to grow past the default ~56% height cap so the
      // language list stays usable on short mobile-landscape screens, and
      // honor safe-area insets (notches / rounded corners), which matter
      // most in landscape.
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        // Cap height so the sheet doesn't cover the whole screen while still
        // giving the list room in landscape.
        final maxSheetHeight = MediaQuery.sizeOf(ctx).height * 0.85;

        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxSheetHeight),
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Tablet bottom sheets can be narrower than the full viewport,
              // so base centering padding on the sheet's real width.
              const maxRowWidth = 640.0;
              final sheetWidth = constraints.maxWidth;
              final horizontalPadding = sheetWidth > maxRowWidth
                  ? (sheetWidth - maxRowWidth) / 2
                  : 16.0;

              return ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: horizontalPadding,
                ),
                itemCount: locales.length + 1,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, index) {
                  if (index == 0) {
                    final selected = current == null;
                    return ListTile(
                      leading: const Icon(Icons.phone_iphone),
                      title: Text(t.systemDefault),
                      trailing: selected ? const Icon(Icons.check) : null,
                      onTap: () {
                        context.read<LocaleProvider>().setLocale(null);
                        Navigator.pop(ctx);
                      },
                    );
                  }
                  final locale = locales[index - 1];
                  final selected = current == locale;
                  return ListTile(
                    leading: const Icon(Icons.translate),
                    title: Text(labelFor(locale)),
                    subtitle: Text(locale.toLanguageTag()),
                    trailing: selected ? const Icon(Icons.check) : null,
                    onTap: () {
                      context.read<LocaleProvider>().setLocale(locale);
                      Navigator.pop(ctx);
                    },
                  );
                },
              );
            },
          ),
        );
      },
    );
  }

  // Minimal labels. Expand as you add locales, or derive from your ARB metadata.
  static String labelFor(Locale l) {
    if (l.languageCode == 'en') return 'English';
    if (l.languageCode == 'es') return 'Español (Spanish)';
    if (l.languageCode == 'ur') return 'اردو (Urdu)'; // Urdu
    if (l.languageCode == 'ar') return 'العربية (Arabic)'; // Arabic
    if (l.languageCode == 'fr') return 'Français (French)';
    if (l.languageCode == 'am') return 'አማርኛ (Amharic)'; // Amharic
    if (l.languageCode == 'ne') return 'नेपाली (Nepali)'; // Nepali
    if (l.languageCode == 'hi') return 'हिन्दी (Hindi)'; // Hindi
    if (l.languageCode == 'fa') return 'فارسی (Farsi)';
    if (l.languageCode == 'zh') {
      return '中文 (Mandarin Chinese)'; // Mandarin Chinese
    }
    if (l.languageCode == 'pt') return 'Português (Portuguese)'; // Portuguese
    if (l.languageCode == 'bn') return 'বাংলা (Bengali)'; // Bengali
    if (l.languageCode == 'ru') return 'Русский (Russian)'; // Russian
    if (l.languageCode == 'ja') return '日本語 (Japanese)';

    return l.toLanguageTag();
  }
}
