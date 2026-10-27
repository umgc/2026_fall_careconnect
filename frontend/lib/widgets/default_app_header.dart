import 'package:care_connect_app/widgets/page_title.dart';
import 'package:care_connect_app/pages/settings_page.dart';
import 'package:flutter/material.dart';

class DefaultAppHeader extends StatelessWidget implements PreferredSizeWidget {
  final bool showBackButton;

  const DefaultAppHeader({this.showBackButton = false, super.key});

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      elevation: 0,
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          if (showBackButton)
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back),
            )
          else
            const SizedBox(width: 48),
          Expanded(
            child: Center(
              child: Image.asset(
                'assets/images/CareConnectLogo.png',
                semanticLabel: 'CareConnect',
                height: 32,
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              Navigator.push(
                context,
                TitledMaterialPageRoute(
                  title: 'Settings',
                  builder: (context) => const SettingsPage()),
              );
            },
            icon: Icon(
              Icons.settings_outlined,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
