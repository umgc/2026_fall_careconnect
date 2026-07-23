import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LanguagePicker {
  static const double _maxRowWidth = 640;
  static const double _minHorizontalInset = 16;

  static Future<void> show(BuildContext context) async {
    final locales = AppLocalizations.supportedLocales;
    final current = context.read<LocaleProvider>().locale;
    final t = AppLocalizations.of(context)!;
    final media = MediaQuery.of(context);
    final horizontalInset = _horizontalInsetFor(media.size.width);
    // Short landscape screens need a scroll-controlled sheet so shrink-wrapped
    // content can grow and remain fully scrollable instead of capping ~56%.
    final isShortLandscape =
        media.size.height < 500 && media.size.width > media.size.height;

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: isShortLandscape,
      builder: (ctx) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(
              horizontalInset,
              12,
              horizontalInset,
              12,
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
                title: Text(labelFor(locale, t)),
                subtitle: Text(locale.toLanguageTag()),
                trailing: selected ? const Icon(Icons.check) : null,
                onTap: () {
                  context.read<LocaleProvider>().setLocale(locale);
                  Navigator.pop(ctx);
                },
              );
            },
          ),
        );
      },
    );
  }

  /// Centers content up to [_maxRowWidth]; otherwise keeps a 16px inset.
  static double _horizontalInsetFor(double width) {
    final centered = (width - _maxRowWidth) / 2;
    return centered > _minHorizontalInset ? centered : _minHorizontalInset;
  }

  // Minimal labels. Expand as you add locales, or derive from your ARB metadata.
  static String labelFor(Locale l, AppLocalizations t) {
    if (l.languageCode == 'en') return t.languagepicker_English;
    if (l.languageCode == 'es') return t.languagepicker_Spanish;
    if (l.languageCode == 'ur') return t.languagepicker_Urdu;
    if (l.languageCode == 'ar') return t.languagepicker_Arabic;
    if (l.languageCode == 'fr') return t.languagepicker_French;
    if (l.languageCode == 'am') return t.languagepicker_Amharic;
    if (l.languageCode == 'ne') return t.languagepicker_Nepali;
    if (l.languageCode == 'hi') return t.languagepicker_Hindi;
    if (l.languageCode == 'fa') return t.languagepicker_Farsi;
    if (l.languageCode == 'zh') return t.languagepicker_MandarinChinese;
    if (l.languageCode == 'pt') return t.languagepicker_Portuguese;
    if (l.languageCode == 'bn') return t.languagepicker_Bengali;
    if (l.languageCode == 'ru') return t.languagepicker_Russian;
    if (l.languageCode == 'ja') return t.languagepicker_Japanese;

    return l.toLanguageTag();
  }
}
