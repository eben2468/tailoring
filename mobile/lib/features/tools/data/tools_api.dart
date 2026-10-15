import 'package:uuid/uuid.dart';

import '../../../core/local/local_store.dart';
import '../../../core/network/api_exception.dart';
import '../../settings/domain/config_category.dart';
import '../../sync/data/sync_engine.dart';
import '../../sync/domain/config_bundle.dart';
import '../domain/tools.dart';

/// Tool fields from the form. Only changed fields are sent on edit.
class ToolDraft {
  const ToolDraft({
    required this.categoryId,
    required this.name,
    this.brandModel,
    this.serialNumber,
    this.purchaseDate,
    this.condition = ToolCondition.good,
    this.status = ToolStatus.operational,
    this.storageLocation,
    this.intervalDays,
    this.notes,
  });

  final int categoryId;
  final String name;
  final String? brandModel;
  final String? serialNumber;
  final DateTime? purchaseDate;
  final ToolCondition condition;
  final ToolStatus status;
  final String? storageLocation;
  final int? intervalDays;
  final String? notes;

  static String? _text(String? v) => v == null || v.trim().isEmpty ? null : v.trim();

  Map<String, dynamic> toJson() => {
        'category_id': categoryId,
        'tool_name': name.trim(),
        'brand_model': _text(brandModel),
        'serial_number': _text(serialNumber),
        'purchase_date': purchaseDate == null ? null : MaintenanceRules.ymd(purchaseDate!),
        'tool_condition': condition.name,
        'operational_status': status.api,
        'storage_location': _text(storageLocation),
        'maintenance_interval_days': intervalDays,
        'notes': _text(notes),
      };

  Map<String, dynamic> changesFrom(Tool t) {
    final before = ToolDraft(
      categoryId: t.categoryId,
      name: t.name,
      brandModel: t.brandModel,
      serialNumber: t.serialNumber,
      purchaseDate: t.purchaseDate,
      condition: t.condition,
      status: t.status,
      storageLocation: t.storageLocation,
      intervalDays: t.intervalDays,
      notes: t.notes,
    ).toJson();
    return {
      for (final e in toJson().entries)
        if (e.value != before[e.key]) e.key: e.value,
    };
  }
}

/// Tool writes (docs/API_REFERENCE.md §13). Work offline; reads come from the local copy.
class ToolsApi implements CategorySettings {
  const ToolsApi(this._sync);

  final SyncEngine _sync;

  Tool _read(String id) {
    final presenter = _sync.presenter();
    final row = _sync.store.get(Tables.tools, id);
    if (presenter == null || row == null || row['deleted_at'] != null) throw const NotFoundException('This tool was not found.');
    return Tool.fromJson(presenter.tool(row));
  }

  Future<Tool> create(ToolDraft draft) async {
    final id = const Uuid().v7();
    await _sync.perform(label: 'Add ${draft.name.trim()}', method: 'POST', path: '/tools', body: {'id': id, ...draft.toJson()});
    return _read(id);
  }

  Future<Tool> update(Tool tool, ToolDraft draft) async {
    final changes = draft.changesFrom(tool);
    if (changes.isEmpty) return tool;
    await _sync.perform(label: 'Edit ${draft.name.trim()}', method: 'PATCH', path: '/tools/${tool.id}', body: {'version': tool.version, ...changes});
    return _read(tool.id);
  }

  /// Sets (or clears, with null) a manual next-maintenance date.
  Future<Tool> setNextDate(Tool tool, DateTime? date) async {
    await _sync.perform(
      label: '${tool.name}: next service date',
      method: 'PATCH',
      path: '/tools/${tool.id}',
      body: {'version': tool.version, 'next_maintenance_override': date == null ? null : MaintenanceRules.ymd(date)},
    );
    return _read(tool.id);
  }

  Future<Tool> setStatus(Tool tool, ToolStatus status) async {
    await _sync.perform(label: '${tool.name}: ${status.choiceLabel.toLowerCase()}', method: 'PATCH', path: '/tools/${tool.id}', body: {'version': tool.version, 'operational_status': status.api});
    return _read(tool.id);
  }

  Future<Tool> setArchived(Tool tool, {required bool archived}) async {
    await _sync.perform(label: '${archived ? 'Archive' : 'Restore'} ${tool.name}', method: 'POST', path: '/tools/${tool.id}/${archived ? 'archive' : 'unarchive'}');
    return _read(tool.id);
  }

  Future<void> logMaintenance(
    Tool tool, {
    required MaintenanceType type,
    required DateTime performedOn,
    String? description,
    String? performedBy,
    ToolCondition? conditionAfter,
    ToolStatus? status,
  }) =>
      _sync.perform(
        label: '${type.label}: ${tool.name}',
        method: 'POST',
        path: '/tools/${tool.id}/maintenance',
        body: {
          'id': const Uuid().v7(),
          'maintenance_type': type.name,
          'performed_on': MaintenanceRules.ymd(performedOn),
          if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
          if (performedBy != null && performedBy.trim().isNotEmpty) 'performed_by': performedBy.trim(),
          'condition_after': ?conditionAfter?.name,
          'operational_status': ?status?.api,
        },
      );

  Future<void> deleteLog(MaintenanceLog log, String toolName) =>
      _sync.perform(label: 'Remove ${log.type.label.toLowerCase()}: $toolName', method: 'DELETE', path: '/tool-maintenance/${log.id}');

  // Categories are configuration: changed online only, then the configuration is downloaded again.

  @override
  Future<List<ConfigCategory>> categories() async {
    final data = await _sync.client.get('/tool-categories') as List<dynamic>;
    return [for (final c in data.cast<Map<String, dynamic>>()) ConfigCategory.fromJson(c)];
  }

  @override
  Future<void> createCategory(String name) async {
    await _sync.client.post('/tool-categories', body: {'category_name': name.trim()});
    await _sync.refreshConfig();
  }

  @override
  Future<void> updateCategory(int id, {String? name, bool? isActive}) async {
    await _sync.client.patch('/tool-categories/$id', body: {'category_name': ?name?.trim(), 'is_active': ?isActive});
    await _sync.refreshConfig();
  }
}
