import 'package:flutter/material.dart';

/// One section of the app, shown in the side navigation and routed to.
class NavItem {
  final String route;
  final String label;
  final IconData icon;
  const NavItem(this.route, this.label, this.icon);
}

/// The fixed top-level sections (order = display order).
const navItems = <NavItem>[
  NavItem('/dashboard', 'Dashboard', Icons.dashboard_outlined),
  NavItem('/sell', 'Sell', Icons.point_of_sale_outlined),
  NavItem('/sales', 'Sales', Icons.receipt_long_outlined),
  NavItem('/catalog', 'Catalog', Icons.inventory_2_outlined),
  NavItem('/inventory', 'Stock', Icons.warehouse_outlined),
  NavItem('/purchasing', 'Purchasing', Icons.local_shipping_outlined),
  NavItem('/customers', 'Customers', Icons.people_outline),
  NavItem('/accounting', 'Accounts', Icons.account_balance_outlined),
  NavItem('/reports', 'Reports', Icons.bar_chart_outlined),
  NavItem('/sync', 'Sync', Icons.sync_outlined),
  NavItem('/settings', 'Settings', Icons.settings_outlined),
];

int navIndexForLocation(String location) {
  final i = navItems.indexWhere((n) => location.startsWith(n.route));
  return i < 0 ? 0 : i;
}
