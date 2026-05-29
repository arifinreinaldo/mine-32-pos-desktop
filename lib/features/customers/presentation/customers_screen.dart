import 'package:flutter/material.dart';

import '../../../shared/widgets/section_placeholder.dart';

class CustomersScreen extends StatelessWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionPlaceholder(
      title: 'Customers',
      icon: Icons.people_outline,
      message: 'Customer accounts, vehicles, credit and history.',
    );
  }
}
