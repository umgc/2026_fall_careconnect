import 'package:flutter/material.dart';

class MoreFeaturesBottomDrawer extends StatelessWidget {
  final List<FeatureItem> features;
  final String title;

  const MoreFeaturesBottomDrawer({
    super.key,
    required this.features,
    this.title = 'Additional Features',
  });

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final maxHeight = screenHeight * 0.5;

    return SizedBox(
      height: maxHeight,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: features.length,
                itemBuilder: (context, index) {
                  final feature = features[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8.0),
                    child: Card(
                      child: InkWell(
                        onTap: feature.onTap,
                        child: ListTile(
                          leading: Icon(feature.icon, color: feature.iconColor),
                          title: Text(feature.title),
                          subtitle: Text(feature.subtitle),
                          trailing: const Icon(
                            Icons.arrow_forward_ios,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              child: const Text('Close'),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

class FeatureItem {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const FeatureItem({
    required this.icon,
    this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}
