import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/local/local_store.dart';
import '../../../core/network/api_exception.dart';
import '../../sync/application/sync_providers.dart';
import '../data/inventory_api.dart';
import '../domain/inventory.dart';

final inventoryApiProvider = Provider<InventoryApi>((ref) => InventoryApi(ref.watch(syncEngineProvider)));

final inventorySummaryProvider = Provider<AsyncValue<InventorySummary>>((ref) => fromStore(ref, (p) => InventorySummary.fromJson(p.inventorySummary())));

/// Active materials by name (or the archived ones).
final inventoryItemsProvider = Provider.family<AsyncValue<List<InventoryItem>>, bool>(
  (ref, archived) => fromStore(ref, (p) => [for (final i in p.inventoryItems(archived: archived)) InventoryItem.fromJson(i)]),
);

final inventoryItemProvider = Provider.family<AsyncValue<InventoryItem>, String>((ref, id) => fromStore(ref, (p) {
      final row = p.store.get(Tables.inventoryItems, id);
      if (row == null || row['deleted_at'] != null) throw const NotFoundException('This material was not found. It may have been removed on another device.');
      return InventoryItem.fromJson(p.inventoryItem(row));
    }));

/// The stock ledger of a material, newest first (voided lines included).
final inventoryLedgerProvider = Provider.family<AsyncValue<List<InventoryTransaction>>, String>(
  (ref, id) => fromStore(ref, (p) => [for (final t in p.inventoryLedger(id)) InventoryTransaction.fromJson(t)]),
);

/// Materials used for (and returned from) a job.
final jobMaterialsProvider = Provider.family<AsyncValue<List<InventoryTransaction>>, String>(
  (ref, jobId) => fromStore(ref, (p) => [for (final t in p.jobMaterials(jobId)) InventoryTransaction.fromJson(t)]),
);

/// Categories from the downloaded configuration (inactive ones included).
final inventoryCategoriesProvider = Provider<AsyncValue<List<InventoryCategory>>>(
  (ref) => fromStore(ref, (p) => [for (final c in p.config.inventoryCategories) InventoryCategory.fromJson(c)]),
);
