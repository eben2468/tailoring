import 'package:uuid/uuid.dart';

import '../../../core/local/local_store.dart';
import '../../../core/network/api_exception.dart';
import '../../settings/domain/config_category.dart';
import '../../sync/data/sync_engine.dart';
import '../domain/inventory.dart';

/// Material fields from the form. Only changed fields are sent on edit.
class InventoryItemDraft {
  const InventoryItemDraft({
    required this.categoryId,
    required this.name,
    required this.unit,
    this.sku,
    this.description,
    this.minStockLevel,
    this.reorderQuantity,
    this.unitCost,
    this.supplierName,
    this.supplierContact,
    this.storageLocation,
    this.notes,
  });

  final int categoryId;
  final String name;
  final String unit;
  final String? sku;
  final String? description;
  final double? minStockLevel;
  final double? reorderQuantity;
  final double? unitCost;
  final String? supplierName;
  final String? supplierContact;
  final String? storageLocation;
  final String? notes;

  static String? _text(String? v) => v == null || v.trim().isEmpty ? null : v.trim();

  Map<String, dynamic> toJson() => {
        'category_id': categoryId,
        'item_name': name.trim(),
        'unit': unit,
        'sku': _text(sku),
        'description': _text(description),
        'min_stock_level': minStockLevel ?? 0,
        'reorder_quantity': reorderQuantity,
        'unit_cost': unitCost,
        'supplier_name': _text(supplierName),
        'supplier_contact': _text(supplierContact),
        'storage_location': _text(storageLocation),
        'notes': _text(notes),
      };

  /// The fields that differ from [item] (so an edit never overwrites changes made elsewhere).
  Map<String, dynamic> changesFrom(InventoryItem item) {
    final before = {
      'category_id': item.categoryId,
      'item_name': item.name,
      'unit': item.unit,
      'sku': item.sku,
      'description': item.description,
      'min_stock_level': item.minStockLevel,
      'reorder_quantity': item.reorderQuantity,
      'unit_cost': item.unitCost,
      'supplier_name': item.supplierName,
      'supplier_contact': item.supplierContact,
      'storage_location': item.storageLocation,
      'notes': item.notes,
    };
    final after = toJson();
    return {
      for (final e in after.entries)
        if (!_same(e.value, before[e.key])) e.key: e.value,
    };
  }

  static bool _same(Object? a, Object? b) => (a is num && b is num) ? a.toDouble() == b.toDouble() : a == b;
}

/// Inventory writes (docs/API_REFERENCE.md §12). Work offline; reads come from the local copy.
/// Stock changes made without a connection are sent with `offline: true` and the device time, so the
/// server accepts usage that was really done even if its stock figure disagrees (it flags a negative stock).
class InventoryApi implements CategorySettings {
  const InventoryApi(this._sync);

  final SyncEngine _sync;

  String get _now => DateTime.now().toUtc().toIso8601String();

  InventoryItem _read(String id) {
    final presenter = _sync.presenter();
    final row = _sync.store.get(Tables.inventoryItems, id);
    if (presenter == null || row == null || row['deleted_at'] != null) throw const NotFoundException('This material was not found.');
    return InventoryItem.fromJson(presenter.inventoryItem(row));
  }

  Future<InventoryItem> create(InventoryItemDraft draft, {double openingQuantity = 0}) async {
    final id = const Uuid().v7();
    final body = {
      'id': id,
      ...draft.toJson(),
      if (openingQuantity > 0) ...{'opening_quantity': openingQuantity, 'opening_transaction_id': const Uuid().v7()},
    };
    await _sync.perform(label: 'Add ${draft.name.trim()}', method: 'POST', path: '/inventory/items', body: body, queuedBody: {...body, 'occurred_at': _now});
    return _read(id);
  }

  Future<InventoryItem> update(InventoryItem item, InventoryItemDraft draft) async {
    final changes = draft.changesFrom(item);
    if (changes.isEmpty) return item;
    await _sync.perform(label: 'Edit ${draft.name.trim()}', method: 'PATCH', path: '/inventory/items/${item.id}', body: {'version': item.version, ...changes});
    return _read(item.id);
  }

  Future<InventoryItem> setArchived(InventoryItem item, {required bool archived}) async {
    await _sync.perform(
      label: '${archived ? 'Archive' : 'Restore'} ${item.name}',
      method: 'POST',
      path: '/inventory/items/${item.id}/${archived ? 'archive' : 'unarchive'}',
    );
    return _read(item.id);
  }

  /// Records a stock change. [quantity] is the amount moved, or the counted stock for a stock count.
  Future<void> record(
    InventoryItem item,
    TransactionType type,
    double quantity, {
    String? jobId,
    double? unitCost,
    String? reference,
    String? note,
  }) {
    final body = <String, dynamic>{
      'id': const Uuid().v7(),
      'transaction_type': type.api,
      if (type == TransactionType.adjustment) 'counted_quantity': quantity else 'quantity': quantity,
      if (jobId != null && type.takesJob) 'job_id': jobId,
      if (unitCost != null && type == TransactionType.purchase) 'unit_cost': unitCost,
      if (reference != null && reference.trim().isNotEmpty) 'reference': reference.trim(),
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    };
    return _sync.perform(
      label: '${type.label}: ${item.name}',
      method: 'POST',
      path: '/inventory/items/${item.id}/transactions',
      body: body,
      queuedBody: {...body, 'occurred_at': _now, 'offline': true},
    );
  }

  Future<void> voidTransaction(InventoryTransaction tx, String itemName, String reason) {
    final body = {'reason': reason.trim()};
    return _sync.perform(
      label: 'Void ${tx.type.label.toLowerCase()}: $itemName',
      method: 'POST',
      path: '/inventory/transactions/${tx.id}/void',
      body: body,
      queuedBody: {...body, 'offline': true},
    );
  }

  // Categories are configuration: changed online only, then the configuration is downloaded again.

  @override
  Future<List<InventoryCategory>> categories() async {
    final data = await _sync.client.get('/inventory/categories') as List<dynamic>;
    return [for (final c in data.cast<Map<String, dynamic>>()) InventoryCategory.fromJson(c)];
  }

  @override
  Future<void> createCategory(String name) async {
    await _sync.client.post('/inventory/categories', body: {'category_name': name.trim()});
    await _sync.refreshConfig();
  }

  @override
  Future<void> updateCategory(int id, {String? name, bool? isActive}) async {
    await _sync.client.patch('/inventory/categories/$id', body: {'category_name': ?name?.trim(), 'is_active': ?isActive});
    await _sync.refreshConfig();
  }
}
