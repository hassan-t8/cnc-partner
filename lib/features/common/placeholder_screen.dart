import 'package:flutter/material.dart';

import '../../widgets/app_states.dart';

/// Temporary screen for modules not yet implemented.
class PlaceholderScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  const PlaceholderScreen(
      {super.key, required this.title, this.icon = Icons.construction});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: EmptyState(
        icon: icon,
        title: '$title — coming soon',
        subtitle: 'This screen is being built.',
      ),
    );
  }
}
