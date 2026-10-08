import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/section_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/state_views.dart';
import '../application/admin_providers.dart';
import '../data/admin_api.dart';

/// Admin: audit trail, newest first, with "load more".
class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(auditLogProvider);

    return DetailScaffold(
      title: 'Audit log',
      body: switch (log) {
        AsyncData(:final value) when value.entries.isEmpty =>
          const MessageView(icon: Symbols.history, title: 'No activity yet', message: 'Sign-ins and sensitive changes will appear here.'),
        AsyncData(:final value) => RefreshIndicator(
            onRefresh: () => ref.refresh(auditLogProvider.future),
            edgeOffset: MediaQuery.paddingOf(context).top + 64,
            child: ListView.separated(
              padding: belowHeader(context),
              itemCount: value.entries.length + (value.hasMore ? 1 : 0),
              separatorBuilder: (_, _) => Gap.sm,
              itemBuilder: (context, i) {
                if (i == value.entries.length) {
                  return Center(
                    child: AppButton(
                      label: 'Load more',
                      variant: AppButtonVariant.tonal,
                      size: AppButtonSize.medium,
                      loading: value.loadingMore,
                      onPressed: () => ref.read(auditLogProvider.notifier).loadMore().catchError((Object e) {
                        if (context.mounted) showAppSnack(context, errorMessage(e), isError: true);
                      }),
                    ),
                  );
                }
                return _AuditTile(entry: value.entries[i]);
              },
            ),
          ),
        AsyncError(:final error) => ErrorView(error: error, onRetry: () => ref.invalidate(auditLogProvider)),
        _ => const LoadingView(),
      },
    );
  }
}

class _AuditTile extends StatelessWidget {
  const _AuditTile({required this.entry});

  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _style(entry.action);
    return AppCard(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: AppRadius.control),
          child: Icon(icon, size: 18, color: color),
        ),
        Gap.md,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(Fmt.auditAction(entry.action), style: AppText.titleSm, overflow: TextOverflow.ellipsis)),
              Text(Fmt.relative(entry.createdAt), style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant)),
            ]),
            Text(
              [
                entry.userName ?? 'System',
                if (entry.entityType != null) '${entry.entityType} #${entry.entityId ?? '—'}',
                if (entry.ipAddress != null) entry.ipAddress!,
              ].join(' · '),
              style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant),
            ),
          ]),
        ),
      ]),
    );
  }

  static (IconData, Color) _style(String action) => switch (action) {
        _ when action.contains('failed') || action.contains('locked') || action.contains('reuse') => (Symbols.gpp_maybe, AppColors.error),
        _ when action.startsWith('admin.') => (Symbols.admin_panel_settings, AppColors.secondary),
        _ when action.contains('logout') => (Symbols.logout, AppColors.onSurfaceVariant),
        _ => (Symbols.login, AppColors.onTertiaryContainer),
      };
}
