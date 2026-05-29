import 'package:flutter/material.dart';

import '../../../shared/widgets/section_placeholder.dart';

class SyncScreen extends StatelessWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionPlaceholder(
      title: 'Sync',
      icon: Icons.sync_outlined,
      message: 'Serverless folder sync: status, configuration and history.',
    );
  }
}
