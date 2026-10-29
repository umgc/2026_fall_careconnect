import 'package:care_connect_app/l10n/app_localizations.dart';
import 'package:care_connect_app/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LanguagePicker {
  static const List<Locale> _availableLocales = <Locale>[
    Locale('en'),
    Locale('es'),
  ];

  static Future<void> show(BuildContext context) async {
    final current = context.read<LocaleProvider>().locale;
    final t = AppLocalizations.of(context)!;

    await showDialog<void>(
      context: context,
      useSafeArea: true,
      barrierDismissible: true,
      builder: (ctx) {
        final maxDialogHeight = MediaQuery.sizeOf(ctx).height * 0.75;

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          clipBehavior: Clip.antiAlias,
          child: Semantics(
            label: t.language,
            namesRoute: true,
            explicitChildNodes: true,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 440,
                maxHeight: maxDialogHeight,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.language),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            t.language,
                            style: Theme.of(ctx).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: MaterialLocalizations.of(
                            ctx,
                          ).closeButtonTooltip,
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: _availableLocales.length + 1,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        if (index == 0) {
                          final selected = current == null;

                          return ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.smartphone),
                            ),
                            title: Text(t.systemDefault),
                            trailing: selected ? const Icon(Icons.check) : null,
                            onTap: () {
                              ctx.read<LocaleProvider>().setLocale(null);
                              Navigator.pop(ctx);
                            },
                          );
                        }

                        final locale = _availableLocales[index - 1];
                        final selected =
                            current?.languageCode == locale.languageCode;

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(
                              ctx,
                            ).colorScheme.primaryContainer,
                            foregroundColor: Theme.of(
                              ctx,
                            ).colorScheme.onPrimaryContainer,
                            child: ExcludeSemantics(
                              child: Text(
                                locale.languageCode.toUpperCase(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                          title: Text(labelFor(locale, t)),
                          trailing: selected ? const Icon(Icons.check) : null,
                          onTap: () {
                            ctx.read<LocaleProvider>().setLocale(locale);
                            Navigator.pop(ctx);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static String labelFor(Locale locale, AppLocalizations t) {
    if (locale.languageCode == 'es') {
      return t.languagepicker_Spanish;
    }

    return t.languagepicker_English;
  }
}
