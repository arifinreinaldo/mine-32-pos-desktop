import 'package:flutter/material.dart';

/// Standard "coming soon" body for sections not yet implemented. Replaced by the
/// real screen as each milestone lands.
class SectionPlaceholder extends StatelessWidget {
  final String title;
  final IconData icon;
  final String message;

  const SectionPlaceholder({
    super.key,
    required this.title,
    required this.icon,
    this.message = 'This section is under construction.',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(title, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
