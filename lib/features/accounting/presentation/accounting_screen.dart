import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/di/providers.dart';
import '../../../core/money/money.dart';
import '../../../shared/widgets/section_placeholder.dart';
import '../domain/accounting_models.dart';
import 'accounting_controller.dart';
import 'manual_journal_dialog.dart';

class AccountingScreen extends ConsumerWidget {
  const AccountingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return DefaultTabController(
      length: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Accounting', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            const TabBar(
              tabs: [
                Tab(text: 'Chart of accounts'),
                Tab(text: 'Journals'),
              ],
            ),
            const Expanded(
              child: TabBarView(
                children: [_ChartOfAccountsTab(), _JournalsTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChartOfAccountsTab extends ConsumerWidget {
  const _ChartOfAccountsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tb = ref.watch(trialBalanceProvider);
    final money = ref.watch(moneyFormatProvider);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
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
          final totalDebit = rows.fold(0, (s, r) => s + r.debit.minorUnits);
          final totalCredit = rows.fold(0, (s, r) => s + r.credit.minorUnits);
          final labelStyle = theme.textTheme.labelMedium;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                child: Row(
                  children: [
                    SizedBox(width: 80, child: Text('Code', style: labelStyle)),
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
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                child: Row(
                  children: [
                    const SizedBox(width: 80),
                    Expanded(
                      child: Text('Totals', style: theme.textTheme.titleSmall),
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
    );
  }
}

class _JournalsTab extends ConsumerWidget {
  const _JournalsTab();

  static String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journals = ref.watch(journalsProvider);

    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => ManualJournalDialog.show(context),
              icon: const Icon(Icons.post_add_outlined),
              label: const Text('New journal'),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: journals.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Failed to load: $e')),
              data: (rows) {
                if (rows.isEmpty) {
                  return const SectionPlaceholder(
                    title: 'No journals yet',
                    icon: Icons.menu_book_outlined,
                    message:
                        'Sales, purchases and manual entries will appear here.',
                  );
                }
                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) =>
                      _JournalTile(journal: rows[i], dateLabel: _date),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _JournalTile extends ConsumerWidget {
  final JournalSummary journal;
  final String Function(int) dateLabel;
  const _JournalTile({required this.journal, required this.dateLabel});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final money = ref.watch(moneyFormatProvider);
    final subtitle = [
      journal.source,
      if (journal.memo != null && journal.memo!.isNotEmpty) journal.memo!,
    ].join(' · ');

    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Row(
        children: [
          SizedBox(width: 110, child: Text(dateLabel(journal.dateMs))),
          Expanded(child: Text(subtitle, overflow: TextOverflow.ellipsis)),
          Text(money.format(journal.total), style: theme.textTheme.titleSmall),
        ],
      ),
      childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      children: [
        FutureBuilder<List<JournalLineView>>(
          future: ref
              .read(accountingRepositoryProvider)
              .journalLines(journal.id),
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(8),
                child: LinearProgressIndicator(),
              );
            }
            return Column(
              children: [
                for (final l in snap.data!)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 70,
                          child: Text(
                            l.accountCode,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                        Expanded(child: Text(l.accountName)),
                        SizedBox(
                          width: 120,
                          child: Text(
                            l.debit.minorUnits == 0
                                ? ''
                                : money.format(l.debit),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        SizedBox(
                          width: 120,
                          child: Text(
                            l.credit.minorUnits == 0
                                ? ''
                                : money.format(l.credit),
                            textAlign: TextAlign.right,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
