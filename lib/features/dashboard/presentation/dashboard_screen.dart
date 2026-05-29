import 'package:flutter/material.dart';

import '../../../shared/widgets/section_placeholder.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionPlaceholder(
      title: 'Dashboard',
      icon: Icons.dashboard_outlined,
      message: "Today's sales, low stock and cash position will appear here.",
    );
  }
}
