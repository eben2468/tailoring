import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/local/local_store.dart';
import '../../../core/network/api_exception.dart';
import '../../settings/domain/config_category.dart';
import '../../sync/application/sync_providers.dart';
import '../data/tools_api.dart';
import '../domain/tools.dart';

final toolsApiProvider = Provider<ToolsApi>((ref) => ToolsApi(ref.watch(syncEngineProvider)));

final toolSummaryProvider = Provider<AsyncValue<ToolSummary>>((ref) => fromStore(ref, (p) => ToolSummary.fromJson(p.toolSummary())));

/// Active tools by name (or the archived ones).
final toolsProvider = Provider.family<AsyncValue<List<Tool>>, bool>((ref, archived) => fromStore(ref, (p) => [for (final t in p.tools(archived: archived)) Tool.fromJson(t)]));

final toolProvider = Provider.family<AsyncValue<Tool>, String>((ref, id) => fromStore(ref, (p) {
      final row = p.store.get(Tables.tools, id);
      if (row == null || row['deleted_at'] != null) throw const NotFoundException('This tool was not found. It may have been removed on another device.');
      return Tool.fromJson(p.tool(row));
    }));

/// Maintenance history of a tool, newest first.
final toolLogsProvider = Provider.family<AsyncValue<List<MaintenanceLog>>, String>((ref, id) => fromStore(ref, (p) => [for (final l in p.toolLogs(id)) MaintenanceLog.fromJson(l)]));

/// Tool categories from the downloaded configuration (inactive ones included).
final toolCategoriesProvider = Provider<AsyncValue<List<ConfigCategory>>>((ref) => fromStore(ref, (p) => [for (final c in p.config.toolCategories) ConfigCategory.fromJson(c)]));
