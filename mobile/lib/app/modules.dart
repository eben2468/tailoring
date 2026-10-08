import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Business modules and which delivery group brings their backend + screens.
/// Until a module ships, its entry points open [ModuleNotReadyView] (no fake data is ever shown).
enum AppModule {
  dashboard('Dashboard', Symbols.grid_view, 'Live overview of jobs, hours, deadlines, stock alerts and AI insights.', 11),
  customers('Customers', Symbols.contacts, 'Customer profiles, measurements and measurement history.', 2),
  jobs('Jobs', Symbols.content_cut, 'Jobs, production stages, task templates and progress.', 3),
  timer('Work Timer', Symbols.timer, 'Start/stop work timing and work logs.', 4),
  calendar('Calendar', Symbols.calendar_month, 'Day, week and month schedule with fittings and deadlines.', 5),
  inventory('Inventory', Symbols.inventory_2, 'Materials, stock movements and low-stock alerts.', 6),
  tools('Tools & Equipment', Symbols.precision_manufacturing, 'Equipment records and maintenance schedule.', 7),
  reports('Reports', Symbols.monitoring, 'Production, hours, customer, inventory and maintenance reports.', 8),
  notifications('Notifications', Symbols.notifications, 'Reminders for deadlines, fittings, stock and maintenance.', 9),
  ai('AI Assistant', Symbols.auto_awesome, 'Production insights, estimates and schedule suggestions.', 10);

  const AppModule(this.title, this.icon, this.description, this.group);

  final String title;
  final IconData icon;
  final String description;
  final int group;

  static AppModule? byKey(String key) => AppModule.values.where((m) => m.name == key).firstOrNull;
}
