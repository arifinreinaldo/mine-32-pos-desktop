import 'package:flutter/material.dart';

import '../../../shared/widgets/section_placeholder.dart';

class PurchasingScreen extends StatelessWidget {
  const PurchasingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionPlaceholder(
      title: 'Purchasing',
      icon: Icons.local_shipping_outlined,
      message: 'Suppliers, purchase orders and goods receipt.',
    );
  }
}
