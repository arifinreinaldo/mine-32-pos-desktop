import 'package:flutter/material.dart';

import '../../../shared/widgets/section_placeholder.dart';

class SellScreen extends StatelessWidget {
  const SellScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionPlaceholder(
      title: 'Sell',
      icon: Icons.point_of_sale_outlined,
      message:
          'The checkout counter — scan parts, take payment, print receipts.',
    );
  }
}
