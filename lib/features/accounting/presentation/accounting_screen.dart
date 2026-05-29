import 'package:flutter/material.dart';

import '../../../shared/widgets/section_placeholder.dart';

class AccountingScreen extends StatelessWidget {
  const AccountingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionPlaceholder(
      title: 'Accounts',
      icon: Icons.account_balance_outlined,
      message: 'Chart of accounts, journals and tax — double-entry ledger.',
    );
  }
}
