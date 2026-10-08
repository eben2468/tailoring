import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/routes.dart';
import '../../../app/section_scaffold.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/menu_row.dart';
import '../../../core/widgets/segmented_tabs.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_pill.dart';
import '../../measurements/application/measurement_providers.dart';
import '../../measurements/domain/measurement.dart';
import '../../measurements/presentation/measurement_widgets.dart';
import '../../jobs/application/job_providers.dart';
import '../../jobs/presentation/job_widgets.dart';
import '../application/customer_providers.dart';
import '../domain/customer.dart';

/// Customer profile & measurement dossier (Stitch: customer_profile_measurement_dossier).
class CustomerProfileScreen extends ConsumerStatefulWidget {
  const CustomerProfileScreen({super.key, required this.customerId});

  final String customerId;

  @override
  ConsumerState<CustomerProfileScreen> createState() => _CustomerProfileScreenState();
}

class _CustomerProfileScreenState extends ConsumerState<CustomerProfileScreen> {
  int _tab = 0;
  MeasurementUnit? _unitOverride;

  Future<void> _refresh() async {
    ref
      ..invalidate(customerProvider(widget.customerId))
      ..invalidate(currentMeasurementsProvider(widget.customerId))
      ..invalidate(measurementHistoryProvider(widget.customerId));
    await ref.read(customerProvider(widget.customerId).future);
  }

  @override
  Widget build(BuildContext context) {
    final customer = ref.watch(customerProvider(widget.customerId));

    return DetailScaffold(
      title: 'Customer',
      actions: [
        if (customer.value != null)
          IconButton(
            tooltip: 'Edit customer',
            icon: const Icon(Symbols.edit, size: 22, color: AppColors.onSurfaceVariant),
            onPressed: () => context.push(Routes.customerEdit(widget.customerId)),
          ),
      ],
      body: switch (customer) {
        AsyncData(:final value) => RefreshIndicator(
            edgeOffset: MediaQuery.paddingOf(context).top + 64,
            onRefresh: _refresh,
            child: ListView(
              padding: belowHeader(context, bottom: 32),
              children: [
                _HeaderCard(customer: value),
                Gap.lg,
                SegmentedTabs(labels: const ['Measurements', 'Commissions', 'Preferences'], selected: _tab, onChanged: (i) => setState(() => _tab = i)),
                Gap.lg,
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: KeyedSubtree(
                    key: ValueKey(_tab),
                    child: switch (_tab) {
                      0 => _MeasurementsTab(
                          customer: value,
                          unit: _unitOverride ?? displayUnitFor(value, ref.watch(defaultMeasurementUnitProvider)),
                          onToggleUnit: () => setState(() {
                            final now = _unitOverride ?? displayUnitFor(value, ref.read(defaultMeasurementUnitProvider));
                            _unitOverride = now == MeasurementUnit.inch ? MeasurementUnit.cm : MeasurementUnit.inch;
                          }),
                        ),
                      1 => _CommissionsTab(customer: value),
                      _ => _PreferencesTab(customer: value),
                    },
                  ),
                ),
              ],
            ),
          ),
        AsyncError(:final error) => ErrorView(error: error, onRetry: () => ref.invalidate(customerProvider(widget.customerId))),
        _ => const LoadingView(),
      },
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.customer});

  final Customer customer;

  Future<void> _open(BuildContext context, Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
      showAppSnack(context, 'No app on this phone can open that.', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = customer.summary;
    final phone = customer.phone;

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          InitialsAvatar(name: customer.fullName, size: 64, dark: true),
          Gap.md,
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(customer.fullName, style: AppText.headlineLg, maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(
                [if (phone != null) Fmt.phone(phone), if (customer.address != null) customer.address!].join(' • '),
                style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (customer.isArchived) ...[Gap.xs, const StatusPill(label: 'Archived', tone: StatusTone.neutral)],
            ]),
          ),
        ]),
        Gap.lg,
        Row(children: [
          Expanded(
            child: _ContactTile(
              icon: Symbols.call,
              label: 'Direct Call',
              color: AppColors.onSurface,
              onTap: phone == null ? null : () => _open(context, Uri(scheme: 'tel', path: phone)),
            ),
          ),
          Gap.sm,
          Expanded(
            child: _ContactTile(
              icon: Symbols.chat,
              label: 'WhatsApp',
              color: AppColors.onTertiaryContainer,
              onTap: phone == null ? null : () => _open(context, Uri.parse('https://wa.me/${Fmt.phoneDigits(phone)}')),
            ),
          ),
          Gap.sm,
          Expanded(
            child: _ContactTile(
              icon: Symbols.mail,
              label: 'Email',
              color: AppColors.secondary,
              onTap: customer.email == null ? null : () => _open(context, Uri(scheme: 'mailto', path: customer.email)),
            ),
          ),
        ]),
        Gap.md,
        InsetTile(
          padding: const EdgeInsets.symmetric(vertical: AppSpace.md, horizontal: AppSpace.xs),
          child: Row(children: [
            Expanded(child: _Stat(caption: 'ORDERS', value: '${summary?.completedJobs ?? 0} Done', footnote: '${summary?.activeJobs ?? 0} Ongoing')),
            Expanded(
              child: _Stat(
                caption: 'MEASURED',
                value: summary?.lastMeasuredAt == null ? '—' : Fmt.shortDate(summary!.lastMeasuredAt!),
                footnote: '${summary?.measurementSets ?? 0} record${summary?.measurementSets == 1 ? '' : 's'}',
                footnoteColor: summary?.lastMeasuredAt == null ? AppColors.warning : AppColors.onTertiaryContainer,
              ),
            ),
            Expanded(child: _Stat(caption: 'CUSTOMER SINCE', value: '${customer.createdAt.year}', footnote: Fmt.since(customer.createdAt))),
          ]),
        ),
      ]),
    );
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.icon, required this.label, required this.color, required this.onTap});

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: AppColors.surfaceContainerLow,
        borderRadius: AppRadius.control,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.control,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.sm + 2),
            child: Column(children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 4),
              Text(label, style: AppText.labelMd.copyWith(color: AppColors.onSurface)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.caption, required this.value, required this.footnote, this.footnoteColor});

  final String caption;
  final String value;
  final String footnote;
  final Color? footnoteColor;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Text(caption, style: AppText.overline.copyWith(fontSize: 10), textAlign: TextAlign.center, maxLines: 1),
      const SizedBox(height: 2),
      FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: AppText.metricNum)),
      Text(footnote, style: AppText.bodySm.copyWith(color: footnoteColor ?? AppColors.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
    ]);
  }
}

class _MeasurementsTab extends ConsumerWidget {
  const _MeasurementsTab({required this.customer, required this.unit, required this.onToggleUnit});

  final Customer customer;
  final MeasurementUnit unit;
  final VoidCallback onToggleUnit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(measurementFieldsProvider);
    final current = ref.watch(currentMeasurementsProvider(customer.id));
    final history = ref.watch(measurementHistoryProvider(customer.id));

    final actions = Row(children: [
      Expanded(
        child: AppButton(
          label: current.value?.isEmpty ?? true ? 'Record measures' : 'Edit Measures',
          icon: Symbols.tune,
          variant: AppButtonVariant.outline,
          onPressed: () => context.push(Routes.recordMeasurements(customer.id)),
        ),
      ),
      Gap.sm,
      Expanded(
        child: AppButton(
          label: 'History',
          icon: Symbols.history,
          variant: AppButtonVariant.outline,
          onPressed: (customer.summary?.measurementSets ?? 0) == 0 ? null : () => context.push(Routes.measurementHistory(customer.id)),
        ),
      ),
    ]);

    return switch ((groups, current)) {
      (AsyncData(value: final g), AsyncData(value: final c)) when c.isEmpty => Column(children: [
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
            child: MessageView(
              icon: Symbols.straighten,
              title: 'No measurements yet',
              message: 'Record ${customer.fullName.split(' ').first}\'s measurements to keep a full history for every fitting.',
              actionLabel: 'Record measurements',
              onAction: () => context.push(Routes.recordMeasurements(customer.id)),
            ),
          ),
          if (g.isEmpty) const SizedBox.shrink(),
        ]),
      (AsyncData(value: final g), AsyncData(value: final c)) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MeasurementDossier(
            groups: g,
            current: c,
            unit: unit,
            onToggleUnit: onToggleUnit,
            notes: history.value?.where((s) => s.notes != null && s.notes!.trim().isNotEmpty).firstOrNull?.notes,
            recordedBy: history.value?.firstOrNull?.recordedBy,
          ),
          Gap.md,
          actions,
        ]),
      (AsyncError(:final error), _) || (_, AsyncError(:final error)) => ErrorView(
          error: error,
          onRetry: () => ref
            ..invalidate(measurementFieldsProvider)
            ..invalidate(currentMeasurementsProvider(customer.id)),
        ),
      _ => const Padding(padding: EdgeInsets.all(AppSpace.xl), child: LoadingView()),
    };
  }
}

/// The customer's jobs ("Commissions"), newest first, plus "+ New Commission".
class _CommissionsTab extends ConsumerWidget {
  const _CommissionsTab({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = JobQuery(filter: 'any', customerId: customer.id);
    final jobs = ref.watch(jobListProvider(query));
    final newJob = AppButton(
      label: 'New Commission',
      icon: Symbols.add,
      expand: true,
      onPressed: customer.isArchived ? null : () => context.push(Routes.jobNew(customerId: customer.id)),
    );

    return switch (jobs) {
      AsyncData(:final value) when value.items.isEmpty => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.xl),
            child: MessageView(icon: Symbols.content_cut, title: 'No jobs yet', message: 'Jobs for ${customer.fullName.split(' ').first} will be listed here.'),
          ),
          Gap.md,
          newJob,
        ]),
      AsyncData(:final value) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          newJob,
          Gap.md,
          for (final job in value.items) ...[
            JobCard(job: job, compact: true, showCustomer: false, onTap: () => context.push(Routes.job(job.id))),
            Gap.sm,
          ],
          if (value.hasMore)
            Center(
              child: AppButton(
                label: 'Load more',
                variant: AppButtonVariant.tonal,
                size: AppButtonSize.medium,
                loading: value.loadingMore,
                onPressed: () => ref.read(jobListProvider(query).notifier).loadMore(),
              ),
            ),
        ]),
      AsyncError(:final error) => ErrorView(error: error, onRetry: () => ref.invalidate(jobListProvider(query))),
      _ => const Padding(padding: EdgeInsets.all(AppSpace.xl), child: LoadingView()),
    };
  }
}

class _PreferencesTab extends ConsumerWidget {
  const _PreferencesTab({required this.customer});

  final Customer customer;

  Future<void> _toggleArchive(BuildContext context, WidgetRef ref) async {
    final archiving = !customer.isArchived;
    if (archiving &&
        !await confirmAction(
          context,
          title: 'Archive ${customer.fullName}?',
          message: 'They will be hidden from the customer list. Measurements and history are kept and the customer can be restored at any time.',
          confirmLabel: 'Archive',
        )) {
      return;
    }
    try {
      await ref.read(customersApiProvider).setArchived(customer.id, archived: archiving);
      ref
        ..invalidate(customerProvider(customer.id))
        ..invalidate(customerListProvider);
      if (context.mounted) showAppSnack(context, archiving ? 'Customer archived.' : 'Customer restored.');
    } on ApiException catch (e) {
      if (context.mounted) showAppSnack(context, e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget block(String title, String? text, IconData icon) => AppCard(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 20, color: AppColors.onSurfaceVariant),
            Gap.md,
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: AppText.titleSm),
                Gap.xs,
                Text(
                  text == null || text.trim().isEmpty ? 'Nothing recorded yet.' : text,
                  style: AppText.bodyMd.copyWith(color: text == null || text.trim().isEmpty ? AppColors.outline : AppColors.onSurfaceVariant),
                ),
              ]),
            ),
          ]),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      block('Style preferences', customer.stylePreferences, Symbols.styler),
      Gap.md,
      block('Notes', customer.notes, Symbols.sticky_note_2),
      Gap.md,
      block(
        'Contact',
        [
          if (customer.phone != null) Fmt.phone(customer.phone!),
          if (customer.phoneAlt != null) '${Fmt.phone(customer.phoneAlt!)} (alt)',
          if (customer.email != null) customer.email!,
          if (customer.address != null) customer.address!,
        ].join('\n'),
        Symbols.contact_page,
      ),
      Gap.md,
      MenuGroup(children: [
        MenuRow(icon: Symbols.edit, title: 'Edit customer', onTap: () => context.push(Routes.customerEdit(customer.id))),
        MenuRow(
          icon: customer.isArchived ? Symbols.unarchive : Symbols.archive,
          title: customer.isArchived ? 'Restore customer' : 'Archive customer',
          subtitle: customer.isArchived ? 'Show them in the customer list again' : 'Hide from the list; history is kept',
          onTap: () => _toggleArchive(context, ref),
        ),
      ]),
    ]);
  }
}
