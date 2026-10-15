import 'package:uuid/uuid.dart';

import '../../../core/local/local_store.dart';
import '../../../core/network/api_exception.dart';
import '../../sync/data/sync_engine.dart';
import '../../sync/domain/local_ops.dart';
import '../domain/customer.dart';

/// Customer writes (docs/API_REFERENCE.md §5). Reads come from the local copy (customer_providers.dart).
/// Every write works offline: it is applied locally and sent when the connection returns.
class CustomersApi {
  const CustomersApi(this._sync);

  final SyncEngine _sync;

  Customer _read(String id) {
    final presenter = _sync.presenter();
    final row = _sync.store.get(Tables.customers, id);
    if (presenter == null || row == null) throw const NotFoundException('This customer is not on this phone yet. Pull to refresh.');
    return Customer.fromJson(presenter.customer(row));
  }

  /// The id is generated here, so a retried request can never create the customer twice.
  Future<Customer> create(CustomerDraft draft, {bool allowDuplicatePhone = false}) async {
    final id = const Uuid().v7();
    await _sync.perform(
      label: 'Add customer ${draft.fullName}',
      method: 'POST',
      path: '/customers',
      body: {'id': id, ...draft.toJson(), if (allowDuplicatePhone) 'allow_duplicate_phone': true},
    );
    return _read(id);
  }

  /// Sends only the fields that changed, so resolving a conflict ("keep my version") never overwrites
  /// what another device changed in other fields.
  Future<Customer> update(String id, int version, CustomerDraft draft, {bool allowDuplicatePhone = false}) async {
    final current = _sync.store.get(Tables.customers, id) ?? const <String, dynamic>{};
    final changed = Map.of(draft.toJson())
      ..removeWhere((key, value) {
        final before = current[key];
        if (key == 'phone' || key == 'phone_alt') return normalizePhone(value as String?) == before;
        return value == before;
      });
    if (changed.isEmpty) return _read(id);
    await _sync.perform(
      label: 'Edit ${draft.fullName}',
      method: 'PATCH',
      path: '/customers/$id',
      body: {'version': version, ...changed, if (allowDuplicatePhone) 'allow_duplicate_phone': true},
    );
    return _read(id);
  }

  Future<Customer> setArchived(String id, {required bool archived}) async {
    final name = _sync.store.get(Tables.customers, id)?['full_name'] ?? 'customer';
    await _sync.perform(label: '${archived ? 'Archive' : 'Restore'} $name', method: 'POST', path: '/customers/$id/${archived ? 'archive' : 'unarchive'}');
    return _read(id);
  }

  /// Customers already using a phone number (main or alternative), from the local copy.
  List<PhoneMatch> phoneCheck(String phone, {String? exceptId}) {
    final normalized = normalizePhone(phone);
    if (normalized == null) return const [];
    return _sync.store
        .all(Tables.customers)
        .where((c) => c['deleted_at'] == null && c['id'] != exceptId && (c['phone'] == normalized || c['phone_alt'] == normalized))
        .map((c) => PhoneMatch(id: c['id'] as String, fullName: c['full_name'] as String, phone: c['phone'] as String?, isArchived: c['archived_at'] != null))
        .toList();
  }
}
