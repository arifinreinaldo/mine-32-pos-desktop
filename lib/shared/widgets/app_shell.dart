import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/navigation.dart';

/// Persistent desktop chrome: a scrollable side navigation rail plus the routed
/// body. Used as the `ShellRoute` builder.
class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final selected = navIndexForLocation(location);
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SideNav(
            selectedIndex: selected,
            onSelected: (i) => context.go(navItems[i].route),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _SideNav extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  const _SideNav({required this.selectedIndex, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 208,
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        child: Column(
          children: [
            const _Brand(),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: navItems.length,
                itemBuilder: (context, i) {
                  final item = navItems[i];
                  final isSelected = i == selectedIndex;
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    child: ListTile(
                      dense: true,
                      selected: isSelected,
                      selectedTileColor: theme.colorScheme.secondaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      leading: Icon(item.icon, size: 22),
                      title: Text(item.label, overflow: TextOverflow.ellipsis),
                      onTap: () => onSelected(i),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      child: Row(
        children: [
          Icon(Icons.settings_suggest, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Mine32 POS',
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
