import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/customers_api.dart';
import '../domain/customer.dart';

final customersApiProvider = Provider<CustomersApi>((ref) => CustomersApi(ref.watch(apiClientProvider)));

/// One customer (profile header, form prefill). Invalidate after edits.
final customerProvider = FutureProvider.autoDispose.family<Customer, String>((ref, id) => ref.watch(customersApiProvider).get(id));

/// Search + filter for the customers tab.
class CustomerQuery {
  const CustomerQuery({this.text = '', this.status = 'active'});

  final String text;

  /// active | archived
  final String status;

  @override
  bool operator ==(Object other) => other is CustomerQuery && other.text == text && other.status == status;

  @override
  int get hashCode => Object.hash(text, status);
}

class CustomerListState {
  const CustomerListState({required this.items, required this.total, required this.page, required this.hasMore, this.loadingMore = false});

  final List<Customer> items;
  final int total;
  final int page;
  final bool hasMore;
  final bool loadingMore;

  CustomerListState copyWith({List<Customer>? items, int? page, bool? hasMore, bool? loadingMore}) => CustomerListState(
        items: items ?? this.items,
        total: total,
        page: page ?? this.page,
        hasMore: hasMore ?? this.hasMore,
        loadingMore: loadingMore ?? this.loadingMore,
      );
}

/// Paged customer list for a query ("load more" at the end of the list).
final customerListProvider = AsyncNotifierProvider.autoDispose.family<CustomerListController, CustomerListState, CustomerQuery>(CustomerListController.new);

class CustomerListController extends AsyncNotifier<CustomerListState> {
  CustomerListController(this.query);

  final CustomerQuery query;

  @override
  Future<CustomerListState> build() async {
    final first = await ref.read(customersApiProvider).list(query: query.text, status: query.status);
    return CustomerListState(items: first.items, total: first.total, page: first.page, hasMore: first.hasMore);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final next = await ref.read(customersApiProvider).list(query: query.text, status: query.status, page: current.page + 1);
      state = AsyncData(current.copyWith(items: [...current.items, ...next.items], page: next.page, hasMore: next.hasMore, loadingMore: false));
    } catch (_) {
      state = AsyncData(current.copyWith(loadingMore: false));
      rethrow;
    }
  }
}
