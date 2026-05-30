import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/app_database.dart';
import '../../../core/di/providers.dart';
import '../../../core/money/money.dart';
import '../domain/accounting_models.dart';
import 'accounting_controller.dart';

/// One editable journal leg.
class _LineEdit {
  String? accountId;
  final TextEditingController debit = TextEditingController();
  final TextEditingController credit = TextEditingController();
  void dispose() {
    debit.dispose();
    credit.dispose();
  }
}

/// A Xero-style manual journal entry: pick a date, add account legs with debit
/// or credit amounts, and post once debits equal credits. Returns `true` when
/// a journal was posted.
class ManualJournalDialog extends ConsumerStatefulWidget {
  const ManualJournalDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => const ManualJournalDialog(),
    );
  }

  @override
  ConsumerState<ManualJournalDialog> createState() =>
      _ManualJournalDialogState();
}

class _ManualJournalDialogState extends ConsumerState<ManualJournalDialog> {
  final _memo = TextEditingController();
  final List<_LineEdit> _lines = [_LineEdit(), _LineEdit()];
  late DateTime _date;
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _memo.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  int _minor(String raw, int scale) {
    final t = raw.trim();
    if (t.isEmpty) return 0;
    try {
      return Money.fromMajor(t, scale: scale).minorUnits;
    } on FormatException {
      return 0;
    }
  }

  void _addLine() => setState(() => _lines.add(_LineEdit()));

  void _removeLine(int i) {
    setState(() {
      _lines.removeAt(i).dispose();
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _post() async {
    final scale = ref.read(currencyScaleProvider);
    final inputs = <JournalLineInput>[];
    for (final l in _lines) {
      if (l.accountId == null) continue;
      final d = _minor(l.debit.text, scale);
      final c = _minor(l.credit.text, scale);
      if (d == 0 && c == 0) continue;
      inputs.add(
        JournalLineInput(
          accountId: l.accountId!,
          debitMinor: d,
          creditMinor: c,
        ),
      );
    }
    setState(() => _posting = true);
    try {
      await ref
          .read(accountingRepositoryProvider)
          .postManualJournal(
            date: _date.millisecondsSinceEpoch,
            memo: _memo.text.trim().isEmpty ? null : _memo.text.trim(),
            lines: inputs,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _posting = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not post: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = ref.watch(currencyScaleProvider);
    final money = ref.watch(moneyFormatProvider);
    final accountsAsync = ref.watch(accountsListProvider);

    var totalDebit = 0, totalCredit = 0, validLines = 0;
    for (final l in _lines) {
      final d = _minor(l.debit.text, scale);
      final c = _minor(l.credit.text, scale);
      if (l.accountId != null && (d > 0 || c > 0)) {
        validLines++;
        totalDebit += d;
        totalCredit += c;
      }
    }
    final balanced =
        totalDebit > 0 && totalDebit == totalCredit && validLines >= 2;
    final dateLabel =
        '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

    return AlertDialog(
      title: const Text('New journal'),
      content: SizedBox(
        width: 600,
        child: accountsAsync.when(
          loading: () => const SizedBox(
            height: 80,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text('Failed to load accounts: $e'),
          data: (accounts) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(dateLabel),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _memo,
                      decoration: const InputDecoration(
                        labelText: 'Memo (optional)',
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (var i = 0; i < _lines.length; i++)
                        _lineRow(i, accounts, theme),
                    ],
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addLine,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add line'),
                ),
              ),
              const Divider(),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      balanced
                          ? 'Balanced'
                          : 'Out of balance by ${money.format(Money((totalDebit - totalCredit).abs()))}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: balanced
                            ? Colors.green
                            : theme.colorScheme.error,
                      ),
                    ),
                  ),
                  Text(
                    'Dr ${money.format(Money(totalDebit))}   Cr ${money.format(Money(totalCredit))}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _posting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (balanced && !_posting) ? _post : null,
          child: Text(_posting ? 'Posting…' : 'Post'),
        ),
      ],
    );
  }

  Widget _lineRow(int i, List<Account> accounts, ThemeData theme) {
    final line = _lines[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: line.accountId,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Account',
              ),
              items: [
                for (final a in accounts)
                  DropdownMenuItem(
                    value: a.id,
                    child: Text(
                      '${a.code}  ${a.name}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => line.accountId = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: line.debit,
              textAlign: TextAlign.right,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Debit',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: line.credit,
              textAlign: TextAlign.right,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Credit',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          IconButton(
            tooltip: 'Remove line',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
            onPressed: _lines.length > 2 ? () => _removeLine(i) : null,
          ),
        ],
      ),
    );
  }
}
