import 'package:flutter/widgets.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../settings/domain/config_category.dart';
import '../../sync/domain/config_bundle.dart';

/// Stock state from the server's rules (InventoryStock / StockRules).
enum StockStatus {
  ok('In Stock'),
  low('Low Stock'),
  out('Depleted'),
  negative('Recount');

  const StockStatus(this.label);

  final String label;

  bool get needsAttention => this != ok;

  static StockStatus parse(String? value) => values.firstWhere((s) => s.name == value, orElse: () => ok);
}

/// Ledger entry kinds (inventory_transactions.transaction_type).
enum TransactionType {
  opening('Opening balance', 'Opening', Symbols.flag),
  purchase('Received', 'Receive stock', Symbols.local_shipping),
  usage('Used', 'Use material', Symbols.content_cut),
  returned('Returned', 'Return to stock', Symbols.undo),
  writeOff('Written off', 'Write off', Symbols.delete_sweep),
  adjustment('Stock count', 'Count stock', Symbols.fact_check);

  const TransactionType(this.label, this.action, this.icon);

  /// Past tense for the ledger ("Used").
  final String label;

  /// The action that records it ("Use material").
  final String action;
  final IconData icon;

  String get api => switch (this) {
        returned => 'return',
        writeOff => 'write_off',
        _ => name,
      };

  bool get takesJob => this == usage || this == returned;

  static TransactionType parse(String? value) => values.firstWhere((t) => t.api == value, orElse: () => adjustment);
}

/// Units a material can be counted in (inventory_items.unit).
abstract final class StockUnits {
  static const all = ['m', 'yd', 'cm', 'pcs', 'spool', 'cone', 'roll', 'set', 'box', 'pack', 'kg', 'g'];

  static const labels = {
    'm': 'Metres (m)',
    'yd': 'Yards (yd)',
    'cm': 'Centimetres (cm)',
    'pcs': 'Pieces (pcs)',
    'spool': 'Spools',
    'cone': 'Cones',
    'roll': 'Rolls',
    'set': 'Sets',
    'box': 'Boxes',
    'pack': 'Packs',
    'kg': 'Kilograms (kg)',
    'g': 'Grams (g)',
  };

  /// Lengths and weights sit next to the number ("18.5m"); counts get a space ("3 spools").
  static String format(num value, String unit) {
    final n = StockRules.number(value);
    return StockRules.isCounted(unit) ? '$n ${StockRules.unitName(unit, value)}' : '$n$unit';
  }
}

class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.unit,
    required this.minStockLevel,
    required this.quantityOnHand,
    required this.status,
    required this.jobsUsedThisMonth,
    required this.version,
    this.categoryName,
    this.sku,
    this.description,
    this.reorderQuantity,
    this.unitCost,
    this.supplierName,
    this.supplierContact,
    this.storageLocation,
    this.notes,
    this.lastTransactionAt,
    this.archivedAt,
  });

  factory InventoryItem.fromJson(Map<String, dynamic> json) => InventoryItem(
        id: json['id'] as String,
        categoryId: (json['category_id'] as num).toInt(),
        categoryName: json['category_name'] as String?,
        name: json['item_name'] as String,
        sku: json['sku'] as String?,
        description: json['description'] as String?,
        unit: json['unit'] as String,
        minStockLevel: (json['min_stock_level'] as num? ?? 0).toDouble(),
        reorderQuantity: (json['reorder_quantity'] as num?)?.toDouble(),
        unitCost: (json['unit_cost'] as num?)?.toDouble(),
        supplierName: json['supplier_name'] as String?,
        supplierContact: json['supplier_contact'] as String?,
        storageLocation: json['storage_location'] as String?,
        notes: json['notes'] as String?,
        quantityOnHand: (json['quantity_on_hand'] as num).toDouble(),
        status: StockStatus.parse(json['stock_status'] as String?),
        lastTransactionAt: DateTime.tryParse(json['last_transaction_at'] as String? ?? '')?.toLocal(),
        jobsUsedThisMonth: (json['jobs_used_this_month'] as num? ?? 0).toInt(),
        archivedAt: DateTime.tryParse(json['archived_at'] as String? ?? '')?.toLocal(),
        version: (json['version'] as num).toInt(),
      );

  final String id;
  final int categoryId;
  final String? categoryName;
  final String name;
  final String? sku;
  final String? description;
  final String unit;
  final double minStockLevel;
  final double? reorderQuantity;
  final double? unitCost;
  final String? supplierName;
  final String? supplierContact;
  final String? storageLocation;
  final String? notes;
  final double quantityOnHand;
  final StockStatus status;
  final DateTime? lastTransactionAt;
  final int jobsUsedThisMonth;
  final DateTime? archivedAt;
  final int version;

  bool get isArchived => archivedAt != null;

  bool get isCounted => StockRules.isCounted(unit);

  /// "18.5m" / "3 spools".
  String format(num value) => StockUnits.format(value, unit);

  String get onHandLabel => format(quantityOnHand);

  /// The level after a restock arrives (minimum + reorder quantity), used to scale the stock bar.
  double get fullLevel {
    final full = minStockLevel + (reorderQuantity ?? minStockLevel);
    return full > 0 ? full : (quantityOnHand > 0 ? quantityOnHand : 1);
  }

  /// 0–1: how full the shelf is against [fullLevel].
  double get fillRatio => (quantityOnHand / fullLevel).clamp(0, 1).toDouble();
}

class InventoryTransaction {
  const InventoryTransaction({
    required this.id,
    required this.itemId,
    required this.type,
    required this.quantityChange,
    required this.occurredAt,
    required this.isVoided,
    required this.version,
    this.itemName,
    this.unit,
    this.jobId,
    this.jobNumber,
    this.unitCost,
    this.reference,
    this.note,
    this.voidReason,
    this.recordedBy,
  });

  factory InventoryTransaction.fromJson(Map<String, dynamic> json) => InventoryTransaction(
        id: json['id'] as String,
        itemId: json['item_id'] as String,
        itemName: json['item_name'] as String?,
        unit: json['unit'] as String?,
        type: TransactionType.parse(json['transaction_type'] as String?),
        quantityChange: (json['quantity_change'] as num).toDouble(),
        jobId: json['job_id'] as String?,
        jobNumber: json['job_number'] as String?,
        unitCost: (json['unit_cost'] as num?)?.toDouble(),
        reference: json['reference'] as String?,
        note: json['note'] as String?,
        occurredAt: DateTime.parse(json['occurred_at'] as String).toLocal(),
        isVoided: json['is_voided'] == true,
        voidReason: json['void_reason'] as String?,
        recordedBy: json['recorded_by'] as String?,
        version: (json['version'] as num).toInt(),
      );

  final String id;
  final String itemId;
  final String? itemName;
  final String? unit;
  final TransactionType type;
  final double quantityChange;
  final String? jobId;
  final String? jobNumber;
  final double? unitCost;
  final String? reference;
  final String? note;
  final DateTime occurredAt;
  final bool isVoided;
  final String? voidReason;
  final String? recordedBy;
  final int version;

  /// "+25m" / "−3 spools".
  String signedLabel(String unit) => '${quantityChange > 0 ? '+' : '−'}${StockUnits.format(quantityChange.abs(), unit)}';
}

/// GET /inventory/summary.
class InventorySummary {
  const InventorySummary({
    required this.totalItems,
    required this.categoryCount,
    required this.lowStock,
    required this.outOfStock,
    required this.negative,
    required this.stockValue,
    required this.valuedItems,
    required this.itemsByCategory,
    required this.alerts,
  });

  factory InventorySummary.fromJson(Map<String, dynamic> json) => InventorySummary(
        totalItems: (json['total_items'] as num).toInt(),
        categoryCount: (json['category_count'] as num).toInt(),
        lowStock: (json['low_stock'] as num).toInt(),
        outOfStock: (json['out_of_stock'] as num).toInt(),
        negative: (json['negative'] as num).toInt(),
        stockValue: (json['stock_value'] as num? ?? 0).toDouble(),
        valuedItems: (json['valued_items'] as num? ?? 0).toInt(),
        itemsByCategory: {
          for (final c in (json['by_category'] as List? ?? const []).cast<Map<String, dynamic>>()) (c['category_id'] as num).toInt(): (c['items'] as num).toInt(),
        },
        alerts: [for (final a in (json['alerts'] as List).cast<Map<String, dynamic>>()) InventoryItem.fromJson(a)],
      );

  final int totalItems;
  final int categoryCount;
  final int lowStock;

  /// Depleted (0) — negative balances are counted separately.
  final int outOfStock;
  final int negative;
  final double stockValue;
  final int valuedItems;
  final Map<int, int> itemsByCategory;

  /// Materials needing attention: negative, then depleted, then low.
  final List<InventoryItem> alerts;
}

/// A material category from the configuration.
typedef InventoryCategory = ConfigCategory;
