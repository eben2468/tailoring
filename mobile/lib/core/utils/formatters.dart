import 'package:intl/intl.dart';

/// Display formatting shared by every screen (local time, English).
abstract final class Fmt {
  static final _dateTime = DateFormat('d MMM yyyy, HH:mm');
  static final _date = DateFormat('d MMM yyyy');
  static final _time = DateFormat('HH:mm');

  static String dateTime(DateTime value) => _dateTime.format(value);

  static String date(DateTime value) => _date.format(value);

  /// "4 Oct 2026" for date-only values (stored at midnight), else "4 Oct 2026, 14:30".
  static String dateOrDateTime(DateTime value) => value.hour == 0 && value.minute == 0 ? _date.format(value) : _dateTime.format(value);

  /// "Oct 4" this year, otherwise "Oct 2024".
  static String shortDate(DateTime value, {DateTime? now}) =>
      value.year == (now ?? DateTime.now()).year ? DateFormat('MMM d').format(value) : DateFormat('MMM yyyy').format(value);

  static String monthYear(DateTime value) => DateFormat('MMMM yyyy').format(value);

  static String monthShort(DateTime value) => DateFormat('MMM').format(value);

  /// Duration as a customer: "New this month", "8 months", "3 years".
  static String since(DateTime start, {DateTime? now}) {
    final ref = now ?? DateTime.now();
    final months = (ref.year - start.year) * 12 + ref.month - start.month;
    if (months < 1) return 'New this month';
    if (months < 24) return '$months month${months == 1 ? '' : 's'}';
    return '${months ~/ 12} years';
  }

  /// "Just now", "5 min ago", "Today 14:20", "Yesterday 09:05", or a full date.
  static String relative(DateTime value, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final diff = reference.difference(value);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    final today = DateTime(reference.year, reference.month, reference.day);
    final day = DateTime(value.year, value.month, value.day);
    if (day == today) return 'Today ${_time.format(value)}';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday ${_time.format(value)}';
    return _dateTime.format(value);
  }

  /// A past day, for date-only values: "today", "yesterday", "4 days ago", or "on 4 Oct 2026" after a month.
  static String daysAgo(DateTime value, {DateTime? now}) {
    final reference = now ?? DateTime.now();
    final days = DateTime(reference.year, reference.month, reference.day).difference(DateTime(value.year, value.month, value.day)).inDays;
    return switch (days) {
      <= 0 => 'today',
      1 => 'yesterday',
      < 30 => '$days days ago',
      _ => 'on ${_date.format(value)}',
    };
  }

  /// Seconds as decimal hours: 37800 → "10.5". Hours are always shown with one decimal (tabular).
  static String hours(int seconds) => (seconds / 3600).toStringAsFixed(1);

  /// Hours typed by the owner ("2.5", "2,5") → seconds, rounded to the minute. null if not a number ≥ 0.
  static int? parseHours(String text) {
    final value = double.tryParse(text.trim().replaceAll(',', '.'));
    if (value == null || value < 0 || value > 500) return null;
    return (value * 60).round() * 60;
  }

  /// Days until a due date → "today", "tomorrow", "in 3 days", "2 days late".
  static String dueIn(int days) => switch (days) {
        0 => 'today',
        1 => 'tomorrow',
        -1 => '1 day late',
        < 0 => '${-days} days late',
        _ => 'in $days days',
      };

  /// "+233241110001" → "+233 24 111 0001" (Ghana grouping; other numbers in groups of 3–4).
  static String phone(String e164) {
    final gh = RegExp(r'^\+233(\d{2})(\d{3})(\d{4})$').firstMatch(e164);
    if (gh != null) return '+233 ${gh[1]} ${gh[2]} ${gh[3]}';
    return e164;
  }

  /// Digits-only form for wa.me / tel: links.
  static String phoneDigits(String e164) => e164.replaceAll(RegExp(r'[^\d]'), '');

  /// "auth.login_failed" → "Login failed".
  static String auditAction(String action) {
    final words = action.split('.').last.replaceAll('_', ' ');
    return words.isEmpty ? action : words[0].toUpperCase() + words.substring(1);
  }
}
