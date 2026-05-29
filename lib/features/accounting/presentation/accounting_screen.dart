import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/money/money.dart';
import '../../../shared/widgets/section_placeholder.dart';
import 'accounting_controller.dart';

class AccountingScreen extends ConsumerWidget {
  const AccountingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tb = ref.watch(trialBalanceProvider);
    final money = ref.watch(moneyFormatProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Chart of accounts', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),
          Expanded(
            child: tb.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Failed to load: $e')),
              data: (rows) {
                if (rows.isEmpty) {
                  return const SectionPlaceholder(
                    title: 'No accounts',
                    icon: Icons.account_balance_outlined,
                    message: 'The chart of accounts will appear here.',
                  );
                }
                final totalDebit = rows.fold(
                  0,
                  (s, r) => s + r.debit.minorUnits,
                );
                final totalCredit = rows.fold(
                  0,
                  (s, r) => s + r.credit.minorUnits,
                );
                final labelStyle = theme.textTheme.labelMedium;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 8,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 80,
                            child: Text('Code', style: labelStyle),
                          ),
                          Expanded(child: Text('Account', style: labelStyle)),
                          SizedBox(
                            width: 130,
                            child: Text(
                              'Debit',
                              style: labelStyle,
                              textAlign: TextAlign.right,
                            ),
                          ),
                          SizedBox(
                            width: 130,
                            child: Text(
                              'Credit',
                              style: labelStyle,
                              textAlign: TextAlign.right,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final r = rows[i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 8,
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 80,
                                  child: Text(
                                    r.code,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                                Expanded(child: Text(r.name)),
                                SizedBox(
                                  width: 130,
                                  child: Text(
                                    r.debit.minorUnits == 0
                                        ? '—'
                                        : money.format(r.debit),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                                SizedBox(
                                  width: 130,
                                  child: Text(
                                    r.credit.minorUnits == 0
                                        ? '—'
                                        : money.format(r.credit),
                                    textAlign: TextAlign.right,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 8,
                      ),
                      child: Row(
                        children: [
                          const SizedBox(width: 80),
                          Expanded(
                            child: Text(
                              'Totals',
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          SizedBox(
                            width: 130,
                            child: Text(
                              money.format(Money(totalDebit)),
                              textAlign: TextAlign.right,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                          SizedBox(
                            width: 130,
                            child: Text(
                              money.format(Money(totalCredit)),
                              textAlign: TextAlign.right,
                              style: theme.textTheme.titleSmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
