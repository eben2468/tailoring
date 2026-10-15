import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/local/local_store.dart';
import '../../../core/network/api_exception.dart';
import '../../sync/application/sync_providers.dart';
import '../data/customers_api.dart';
import '../domain/customer.dart';

final customersApiProvider = Provider<CustomersApi>((ref) => CustomersApi(ref.watch(syncEngineProvider)));

/// One customer (profile header, form prefill), from the local copy.
final customerProvider = Provider.family<AsyncValue<Customer>, String>((ref, id) => fromStore(ref, (p) {
      final row = p.store.get(Tables.customers, id);
      if (row == null || row['deleted_at'] != null) throw const NotFoundException('This customer was not found. It may have been removed on another device.');
      return Customer.fromJson(p.customer(row));
    }));

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
  const CustomerListState({required this.items});

  final List<Customer> items;

  int get total => items.length;
}

/// Customers matching a search (name, email or phone digits), active or archived, by name.
final customerListProvider = Provider.family<AsyncValue<CustomerListState>, CustomerQuery>((ref, query) => fromStore(ref, (p) {
      final text = query.text.toLowerCase();
      var digits = query.text.replaceAll(RegExp(r'\D'), '');
      if (digits.startsWith('0')) digits = digits.substring(1);
      final rows = p.store.all(Tables.customers).where((c) {
        if (c['deleted_at'] != null) return false;
        if ((c['archived_at'] != null) != (query.status == 'archived')) return false;
        if (text.isEmpty) return true;
        final phones = '${c['phone'] ?? ''} ${c['phone_alt'] ?? ''}';
        return (c['full_name'] as String).toLowerCase().contains(text) ||
            ((c['email'] as String?) ?? '').contains(text) ||
            (digits.length >= 3 && phones.contains(digits));
      }).toList()
        ..sort((a, b) => (a['full_name'] as String).toLowerCase().compareTo((b['full_name'] as String).toLowerCase()));
      return CustomerListState(items: rows.map((r) => Customer.fromJson(p.customer(r))).toList());
    }));
