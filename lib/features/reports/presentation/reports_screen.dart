import 'package:flutter/material.dart';

import '../../../shared/widgets/section_placeholder.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionPlaceholder(
      title: 'Reports',
      icon: Icons.bar_chart_outlined,
      message: 'Sales, inventory valuation, P&L, balance sheet and tax.',
    );
  }
}
