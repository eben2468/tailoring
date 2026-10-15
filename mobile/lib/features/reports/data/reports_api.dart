import 'dart:convert';

import '../../../core/local/local_store.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../domain/reports.dart';

/// Reports are calculated on the server (GET /reports/{key}, docs/API_REFERENCE.md §14). The last result
/// of each report and range is kept on the phone, so a report opens without a connection (marked stale).
class ReportsApi {
  const ReportsApi(this._client, this._store);

  final ApiClient _client;
  final LocalStore _store;

  String _cacheKey(ReportKind kind, ReportRange range) => 'report:${kind.key}:${range.fromYmd}:${range.toYmd}';

  Future<ReportResult> fetch(ReportKind kind, ReportRange range) async {
    try {
      final data = await _client.get('/reports/${kind.key}', query: {'from': range.fromYmd, 'to': range.toYmd}) as Map<String, dynamic>;
      final now = DateTime.now();
      _store.setMeta(_cacheKey(kind, range), jsonEncode({'fetched_at': now.toUtc().toIso8601String(), 'data': data}));
      return ReportResult(kind: kind, data: data, fetchedAt: now, stale: false);
    } on ApiException catch (e) {
      if (e is! NetworkException && e is! TimeoutApiException) rethrow;
      final cached = cachedResult(kind, range);
      if (cached == null) rethrow;
      return cached;
    }
  }

  /// The last downloaded result, or null.
  ReportResult? cachedResult(ReportKind kind, ReportRange range) {
    final raw = _store.meta(_cacheKey(kind, range));
    if (raw == null) return null;
    final json = (jsonDecode(raw) as Map).cast<String, dynamic>();
    return ReportResult(
      kind: kind,
      data: (json['data'] as Map).cast<String, dynamic>(),
      fetchedAt: DateTime.parse(json['fetched_at'] as String).toLocal(),
      stale: true,
    );
  }
}
