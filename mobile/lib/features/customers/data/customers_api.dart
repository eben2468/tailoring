import 'package:uuid/uuid.dart';

import '../../../core/network/api_client.dart';
import '../domain/customer.dart';

/// /customers endpoints (docs/API_REFERENCE.md §Customers).
class CustomersApi {
  const CustomersApi(this._client);

  final ApiClient _client;

  /// [status]: active | archived | all · [sort]: name | recent
  Future<Paged<Customer>> list({String? query, String status = 'active', String sort = 'name', int page = 1}) =>
      _client.getPaged('/customers', Customer.fromJson, query: {'q': query, 'status': status, 'sort': sort, 'page': page, 'per_page': 30});

  Future<Customer> get(String id) async => Customer.fromJson(await _client.get('/customers/$id') as Map<String, dynamic>);

  /// The id is generated here, so a retried request can never create the customer twice.
  Future<Customer> create(CustomerDraft draft, {bool allowDuplicatePhone = false}) async => Customer.fromJson(
        await _client.post('/customers', body: {
          'id': const Uuid().v7(),
          ...draft.toJson(),
          if (allowDuplicatePhone) 'allow_duplicate_phone': true,
        }) as Map<String, dynamic>,
      );

  Future<Customer> update(String id, int version, CustomerDraft draft, {bool allowDuplicatePhone = false}) async => Customer.fromJson(
        await _client.patch('/customers/$id', body: {
          'version': version,
          ...draft.toJson(),
          if (allowDuplicatePhone) 'allow_duplicate_phone': true,
        }) as Map<String, dynamic>,
      );

  Future<Customer> setArchived(String id, {required bool archived}) async =>
      Customer.fromJson(await _client.post('/customers/$id/${archived ? 'archive' : 'unarchive'}') as Map<String, dynamic>);

  Future<List<PhoneMatch>> phoneCheck(String phone, {String? exceptId}) async =>
      (await _client.get('/customers/phone-check', query: {'phone': phone, 'except': exceptId}) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(PhoneMatch.fromJson)
          .toList();
}
