import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../data/admin_api.dart';

final adminApiProvider = Provider<AdminApi>((ref) => AdminApi(ref.watch(apiClientProvider)));

/// Account list (small: one owner and the admin, so one page of 50 is plenty).
final adminUsersProvider = FutureProvider.autoDispose<Paged<AdminUser>>((ref) => ref.watch(adminApiProvider).users());

final adminUserProvider = FutureProvider.autoDispose.family<AdminUser, int>((ref, id) => ref.watch(adminApiProvider).user(id));

/// Audit log with "load more" paging.
final auditLogProvider = AsyncNotifierProvider.autoDispose<AuditLogController, AuditLogState>(AuditLogController.new);

class AuditLogState {
  const AuditLogState({required this.entries, required this.page, required this.hasMore, this.loadingMore = false});

  final List<AuditEntry> entries;
  final int page;
  final bool hasMore;
  final bool loadingMore;
}

class AuditLogController extends AsyncNotifier<AuditLogState> {
  @override
  Future<AuditLogState> build() async {
    final first = await ref.read(adminApiProvider).auditLog();
    return AuditLogState(entries: first.items, page: first.page, hasMore: first.hasMore);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(AuditLogState(entries: current.entries, page: current.page, hasMore: true, loadingMore: true));
    try {
      final next = await ref.read(adminApiProvider).auditLog(page: current.page + 1);
      state = AsyncData(AuditLogState(entries: [...current.entries, ...next.items], page: next.page, hasMore: next.hasMore));
    } catch (_) {
      state = AsyncData(AuditLogState(entries: current.entries, page: current.page, hasMore: true));
      rethrow;
    }
  }
}
