import 'package:flutter/material.dart';

import '../../../shared/widgets/section_placeholder.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionPlaceholder(
      title: 'Settings',
      icon: Icons.settings_outlined,
      message: 'Company details, currency, tax defaults and receipts.',
    );
  }
}
