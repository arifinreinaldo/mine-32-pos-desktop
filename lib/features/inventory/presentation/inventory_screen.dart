import 'package:flutter/material.dart';

import '../../../shared/widgets/section_placeholder.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionPlaceholder(
      title: 'Stock',
      icon: Icons.warehouse_outlined,
      message: 'Stock levels by location, adjustments, transfers and counts.',
    );
  }
}
