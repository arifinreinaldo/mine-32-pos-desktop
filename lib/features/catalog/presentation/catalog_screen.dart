import 'package:flutter/material.dart';

import '../../../shared/widgets/section_placeholder.dart';

class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionPlaceholder(
      title: 'Catalog',
      icon: Icons.inventory_2_outlined,
      message: 'Parts, variants, brands, fitment and cross-reference.',
    );
  }
}
