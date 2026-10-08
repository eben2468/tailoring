import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/routes.dart';
import '../../../app/section_scaffold.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/bottom_action_bar.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/filter_pills.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_pill.dart';
import '../../customers/application/customer_providers.dart';
import '../../customers/domain/customer.dart';
import '../../measurements/application/measurement_providers.dart';
import '../application/job_providers.dart';
import '../domain/job.dart';

/// Create a job (Stitch "New Commission") or edit one ([jobId] set: routing is edited on the job sheet).
class JobFormScreen extends ConsumerWidget {
  const JobFormScreen({super.key, this.jobId, this.customerId});

  final String? jobId;

  /// Pre-selected customer (from the customer profile).
  final String? customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (jobId == null) return _JobForm(existing: null, initialCustomerId: customerId);
    final job = ref.watch(jobProvider(jobId!));
    return switch (job) {
      AsyncData(:final value) => _JobForm(existing: value),
      AsyncError(:final error) => DetailScaffold(
        title: 'Edit Job',
        body: ErrorView(error: error, onRetry: () => ref.invalidate(jobProvider(jobId!))),
      ),
      _ => const DetailScaffold(title: 'Edit Job', body: LoadingView()),
    };
  }
}

class _JobForm extends ConsumerStatefulWidget {
  const _JobForm({required this.existing, this.initialCustomerId});

  final Job? existing;
  final String? initialCustomerId;

  @override
  ConsumerState<_JobForm> createState() => _JobFormState();
}

class _JobFormState extends ConsumerState<_JobForm> {
  late String? _customerId = widget.existing?.customerId ?? widget.initialCustomerId;
  JobType? _jobType;
  List<PlannedTask> _tasks = const [];
  List<TextEditingController> _hourFields = const [];
  late JobPriority _priority = widget.existing?.priority ?? JobPriority.normal;
  late DateTime? _due = widget.existing?.dueDate;
  late DateTime? _collection = widget.existing?.collectionDate;
  late int _quantity = widget.existing?.quantity ?? 1;
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _fabric = TextEditingController(text: widget.existing?.fabricNote);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  Map<String, String> _errors = const {};
  bool _saving = false;

  bool get _editing => widget.existing != null;

  @override
  void dispose() {
    for (final c in [_title, _fabric, _notes, ..._hourFields]) {
      c.dispose();
    }
    super.dispose();
  }

  void _chooseType(JobType type) {
    for (final c in _hourFields) {
      c.dispose();
    }
    setState(() {
      _jobType = type;
      _quantity = type.defaultQuantity;
      _tasks = [for (final t in type.tasks) PlannedTask(taskType: t.taskType, name: t.name, estimatedSeconds: t.estimatedSeconds)];
      _hourFields = [for (final t in _tasks) TextEditingController(text: t.taskType.isMilestone ? '' : Fmt.hours(t.estimatedSeconds))];
    });
  }

  int get _totalSeconds => _tasks.indexed.fold(0, (sum, e) => sum + (e.$2.taskType.isMilestone ? 0 : (Fmt.parseHours(_hourFields[e.$1].text) ?? 0)));

  Future<void> _pickDate({required bool due}) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final initial = (due ? _due : _collection) ?? _due ?? today.add(const Duration(days: 14));
    final first = widget.existing?.orderDate ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : initial,
      firstDate: first,
      lastDate: today.add(const Duration(days: 730)),
      helpText: due ? 'Target delivery date' : 'Collection date',
    );
    if (picked != null) setState(() => due ? _due = picked : _collection = picked);
  }

  Future<void> _pickCustomer() async {
    final picked = await showModalBottomSheet<Customer>(
      context: context,
      useRootNavigator: true, // above the bottom navigation and timer bar
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _CustomerPicker(),
    );
    if (picked != null) setState(() => _customerId = picked.id);
  }

  Future<void> _save({required bool draft}) async {
    final errors = <String, String>{};
    if (_customerId == null) errors['customer_id'] = 'Choose the customer.';
    if (!_editing && _jobType == null) errors['job_type_id'] = 'Choose the garment.';
    final tasks = <PlannedTask>[];
    for (final (i, task) in _tasks.indexed) {
      final seconds = task.taskType.isMilestone ? 0 : Fmt.parseHours(_hourFields[i].text);
      if (seconds == null) errors['tasks.$i'] = 'Hours?';
      tasks.add(task.copyWith(estimatedSeconds: seconds ?? 0));
    }
    setState(() => _errors = errors);
    if (errors.isNotEmpty) {
      showAppSnack(context, errors['customer_id'] ?? errors['job_type_id'] ?? 'Check the hours of each stage.', isError: true);
      return;
    }

    final latestSet = ref.read(measurementHistoryProvider(_customerId!)).value?.firstOrNull?.id;
    final fields = JobDraft(
      title: _title.text,
      quantity: _quantity,
      priority: _priority,
      dueDate: _due,
      collectionDate: _collection,
      fabricNote: _fabric.text,
      notes: _notes.text,
      description: widget.existing?.description,
      measurementSetId: _editing ? widget.existing!.measurementSetId : latestSet,
    );

    setState(() => _saving = true);
    try {
      if (_editing) {
        final job = widget.existing!;
        await ref.read(jobProvider(job.id).notifier).run((api) => api.update(job.id, job.version, fields));
        if (!mounted) return;
        showAppSnack(context, 'Job updated.');
        context.pop();
      } else {
        final job = await ref.read(jobsApiProvider).create(customerId: _customerId!, jobTypeId: _jobType!.id, draft: draft, fields: fields, tasks: tasks);
        invalidateJobListsFromWidget(ref, customerId: job.customerId);
        if (!mounted) return;
        showAppSnack(context, draft ? 'Draft ${job.displayNumber} saved.' : 'Job ${job.displayNumber} queued for production.');
        context.pushReplacement(Routes.job(job.id));
      }
    } on ValidationException catch (e) {
      if (!mounted) return;
      setState(() => _errors = {for (final entry in e.fieldErrors.entries) entry.key: entry.value.first});
      showAppSnack(context, e.fieldErrors.values.firstOrNull?.firstOrNull ?? e.message, isError: true);
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final types = _editing ? null : ref.watch(jobTypesProvider);
    final available = types?.value;
    if (_jobType == null && available != null && available.isNotEmpty) {
      // Preselect the first garment so the routing and hours show straight away.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _jobType == null) _chooseType(available.first);
      });
    }
    final steps = [_customerId != null, _editing || _jobType != null, _due != null];

    return DetailScaffold(
      title: _editing ? 'Edit Job' : 'New Job',
      bottomBar: BottomActionBar(
        child: _editing
            ? AppButton(label: 'Save Changes', icon: Symbols.check, expand: true, loading: _saving, onPressed: () => _save(draft: false))
            : Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: AppButton(label: 'Save Draft', variant: AppButtonVariant.tonal, onPressed: _saving ? null : () => _save(draft: true)),
                  ),
                  Gap.sm,
                  Expanded(
                    flex: 3,
                    child: AppButton(label: 'Queue Production', icon: Symbols.verified, loading: _saving, onPressed: () => _save(draft: false)),
                  ),
                ],
              ),
      ),
      body: ListView(
        padding: belowHeader(context, bottom: 24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_editing ? 'JOB ${widget.existing!.displayNumber}' : 'INTAKE · ${steps.where((s) => s).length} OF 3', style: AppText.overline),
                    Text(_editing ? widget.existing!.title : 'New Commission', style: AppText.headlineLg, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (!_editing) const StatusPill(label: 'Draft', tone: StatusTone.info),
            ],
          ),
          Gap.sm,
          Row(
            children: [
              for (final (i, done) in steps.indexed) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: AnimatedContainer(
                    duration: AppMotion.medium,
                    height: 4,
                    decoration: BoxDecoration(color: done ? AppColors.secondary : AppColors.surfaceContainerHigh, borderRadius: AppRadius.full),
                  ),
                ),
              ],
            ],
          ),
          Gap.lg,
          _CustomerCard(customerId: _customerId, locked: _editing, error: _errors['customer_id'], onChange: _pickCustomer),
          Gap.lg,
          if (!_editing) ...[_routingCard(types!), Gap.lg, _WorkloadCard(seconds: _totalSeconds, stages: _tasks.where((t) => !t.taskType.isMilestone).length, due: _due), Gap.lg],
          _detailsCard(),
        ],
      ),
    );
  }

  Widget _routingCard(AsyncValue<List<JobType>> types) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Kicker(
            'Garment',
            trailing: Text('Standard routing', style: AppText.labelMd.copyWith(color: AppColors.onSurfaceVariant)),
          ),
          Gap.sm,
          switch (types) {
            AsyncData(:final value) when value.isEmpty => Text('No garment types are set up. Add one in More → Garment templates.', style: AppText.bodySm.copyWith(color: AppColors.error)),
            AsyncData(:final value) => FilterPills(
              labels: [for (final t in value) t.name],
              selected: _jobType == null ? -1 : value.indexWhere((t) => t.id == _jobType!.id),
              onChanged: (i) => _chooseType(value[i]),
            ),
            AsyncError(:final error) => ErrorView(error: error, onRetry: () => ref.invalidate(jobTypesProvider)),
            _ => const SizedBox(height: 36, child: LoadingView()),
          },
          if (_jobType != null) ...[
            Gap.lg,
            Row(
              children: [
                Expanded(
                  child: Text('Production Routing', style: AppText.labelMd.copyWith(color: AppColors.onSurfaceVariant)),
                ),
                Text('Tap to adjust hours', style: AppText.labelMd.copyWith(color: AppColors.onSurfaceVariant)),
              ],
            ),
            Gap.sm,
            for (final (i, task) in _tasks.indexed) ...[
              _RoutingRow(number: i + 1, task: task, controller: _hourFields[i], hasError: _errors.containsKey('tasks.$i'), onChanged: () => setState(() {})),
              const SizedBox(height: 6),
            ],
            if (_jobType!.estimatedSeconds == 0)
              Padding(
                padding: const EdgeInsets.only(top: AppSpace.xs),
                child: Text('This garment has no standard hours yet. Enter them here, or set them once in More → Garment templates.', style: AppText.bodySm.copyWith(color: AppColors.warning)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _detailsCard() {
    Widget priorityButton(JobPriority p, Color dot) {
      final active = _priority == p;
      return Expanded(
        child: Material(
          color: active ? AppColors.secondaryFixed : AppColors.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.control,
            side: BorderSide(color: active ? AppColors.secondary : Colors.transparent, width: 1.5),
          ),
          child: InkWell(
            borderRadius: AppRadius.control,
            onTap: () => setState(() => _priority = p),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
              child: Column(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                  ),
                  const SizedBox(height: 6),
                  Text(p.label, style: AppText.labelMd.copyWith(color: active ? AppColors.onSecondaryFixed : AppColors.onSurface), maxLines: 1),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Kicker('Fabric'),
          Gap.sm,
          AppTextField(
            label: 'Fabric',
            hint: 'e.g. Navy Super 150s wool',
            controller: _fabric,
            prefixIcon: Symbols.texture,
            errorText: _errors['fabric_note'],
            textCapitalization: TextCapitalization.sentences,
          ),
          Gap.lg,
          const Kicker('Production priority'),
          Gap.sm,
          Row(
            children: [
              priorityButton(JobPriority.normal, AppColors.outline),
              Gap.sm,
              priorityButton(JobPriority.high, AppColors.secondary),
              Gap.sm,
              priorityButton(JobPriority.urgent, AppColors.error),
            ],
          ),
          Gap.lg,
          Kicker(
            'Schedule',
            trailing: _due == null
                ? null
                : Text('${DateUtils.dateOnly(_due!).difference(DateUtils.dateOnly(DateTime.now())).inDays} Days Window', style: AppText.labelMd.copyWith(color: AppColors.secondary)),
          ),
          Gap.sm,
          _DateTile(caption: 'Target Delivery Date', date: _due, error: _errors['due_date'], onTap: () => _pickDate(due: true), onClear: _due == null ? null : () => setState(() => _due = null)),
          Gap.sm,
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _SmallTile(
                    caption: 'COLLECTION',
                    icon: Symbols.shopping_bag,
                    value: _collection == null ? 'Not set' : Fmt.date(_collection!),
                    error: _errors['collection_date'],
                    onTap: () => _pickDate(due: false),
                  ),
                ),
                Gap.sm,
                Expanded(
                  child: _SmallTile(
                    caption: 'PIECES',
                    icon: Symbols.layers,
                    value: '$_quantity',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _StepButton(icon: Symbols.remove, onTap: _quantity > 1 ? () => setState(() => _quantity--) : null),
                        _StepButton(icon: Symbols.add, onTap: _quantity < 999 ? () => setState(() => _quantity++) : null),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Gap.lg,
          const Kicker('Details'),
          Gap.sm,
          AppTextField(
            label: 'Job title',
            hint: _jobType?.name ?? 'e.g. Wedding suit',
            controller: _title,
            errorText: _errors['title'],
            maxLength: 150,
            textCapitalization: TextCapitalization.sentences,
          ),
          Gap.md,
          AppTextField(label: 'Notes', hint: 'Styling and finish details', controller: _notes, maxLines: 5, minLines: 3, errorText: _errors['notes'], textCapitalization: TextCapitalization.sentences),
        ],
      ),
    );
  }
}

class _CustomerCard extends ConsumerWidget {
  const _CustomerCard({required this.customerId, required this.locked, required this.onChange, this.error});

  final String? customerId;
  final bool locked;
  final VoidCallback onChange;
  final String? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = customerId == null ? null : ref.watch(customerProvider(customerId!));
    final current = customerId == null ? null : ref.watch(currentMeasurementsProvider(customerId!)).value;
    if (customerId != null) ref.watch(measurementHistoryProvider(customerId!)); // latest set is linked to the job

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Kicker(
            'Customer',
            trailing: locked || customerId == null ? null : AppButton(label: 'Change', icon: Symbols.swap_horiz, variant: AppButtonVariant.text, size: AppButtonSize.small, onPressed: onChange),
          ),
          Gap.sm,
          switch (customer) {
            null => AppButton(label: 'Choose customer', icon: Symbols.person_search, variant: AppButtonVariant.outline, expand: true, onPressed: onChange),
            AsyncData(:final value) => InsetTile(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Row(
                children: [
                  InitialsAvatar(name: value.fullName, size: 48, dark: true),
                  Gap.md,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(value.fullName, style: AppText.titleSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (value.phone != null) Text(Fmt.phone(value.phone!), style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if ((current?.values.length ?? 0) > 0)
                        StatusPill(label: '${current!.values.length} specs', tone: StatusTone.success, showDot: false)
                      else
                        const StatusPill(label: 'Not measured', tone: StatusTone.warning),
                      if (value.summary?.lastMeasuredAt != null) ...[
                        const SizedBox(height: 4),
                        Text('Measured ${Fmt.relative(value.summary!.lastMeasuredAt!).toLowerCase()}', style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            AsyncError(:final error) => ErrorView(error: error, onRetry: () => ref.invalidate(customerProvider(customerId!))),
            _ => const SizedBox(height: 72, child: LoadingView()),
          },
          if (error != null) ...[Gap.xs, Text(error!, style: AppText.bodySm.copyWith(color: AppColors.error))],
        ],
      ),
    );
  }
}

class _RoutingRow extends StatelessWidget {
  const _RoutingRow({required this.number, required this.task, required this.controller, required this.hasError, required this.onChanged});

  final int number;
  final PlannedTask task;
  final TextEditingController controller;
  final bool hasError;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpace.md, vertical: 6),
      decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: AppRadius.control),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.surfaceContainerLowest, shape: BoxShape.circle),
            child: task.taskType.isMilestone
                ? const Icon(Symbols.flag, size: 14, color: AppColors.onSurfaceVariant)
                : Text('$number', style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant)),
          ),
          Gap.md,
          Expanded(
            child: Text(task.name, style: AppText.bodyMd, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          if (task.taskType.isMilestone)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text('Milestone', style: AppText.labelSm.copyWith(color: AppColors.outline)),
            )
          else ...[
            SizedBox(
              width: 64,
              child: TextField(
                controller: controller,
                onChanged: (_) => onChanged(),
                textAlign: TextAlign.right,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                style: AppText.titleSm.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.surfaceContainerLowest,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: AppRadius.small,
                    borderSide: hasError ? const BorderSide(color: AppColors.error) : BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppRadius.small,
                    borderSide: hasError ? const BorderSide(color: AppColors.error) : BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text('h', style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

/// Dark "CALCULATED WORKBENCH WORKLOAD" card.
class _WorkloadCard extends StatelessWidget {
  const _WorkloadCard({required this.seconds, required this.stages, required this.due});

  final int seconds;
  final int stages;
  final DateTime? due;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: AppRadius.card, boxShadow: AppShadows.raised),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CALCULATED WORKBENCH WORKLOAD', style: AppText.overline.copyWith(color: AppColors.onPrimaryContainer)),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: Fmt.hours(seconds),
                        style: AppText.displayLg.copyWith(color: AppColors.onPrimary, fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                      TextSpan(
                        text: ' HOURS',
                        style: AppText.headlineMd.copyWith(color: AppColors.onPrimary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: AppColors.secondary, borderRadius: AppRadius.small),
                child: Text('$stages stages', style: AppText.labelMd.copyWith(color: AppColors.onSecondary)),
              ),
              if (due != null) ...[const SizedBox(height: 6), Text('Due ${Fmt.shortDate(due!)}', style: AppText.bodySm.copyWith(color: AppColors.onPrimaryContainer))],
            ],
          ),
        ],
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  const _DateTile({required this.caption, required this.date, required this.onTap, this.onClear, this.error});

  final String caption;
  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.control,
        side: error == null ? BorderSide.none : const BorderSide(color: AppColors.error),
      ),
      child: InkWell(
        borderRadius: AppRadius.control,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, borderRadius: AppRadius.control),
                child: const Icon(Symbols.event_available, size: 22, color: AppColors.onSurface),
              ),
              Gap.md,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(caption, style: AppText.labelMd.copyWith(color: AppColors.onSurfaceVariant)),
                    Text(date == null ? 'Choose date' : Fmt.date(date!), style: AppText.headlineMd.copyWith(color: date == null ? AppColors.outline : AppColors.onSurface)),
                    if (error != null) Text(error!, style: AppText.bodySm.copyWith(color: AppColors.error)),
                  ],
                ),
              ),
              if (onClear != null)
                IconButton(
                  tooltip: 'Clear date',
                  onPressed: onClear,
                  icon: const Icon(Symbols.close, size: 20, color: AppColors.onSurfaceVariant),
                )
              else
                const Icon(Symbols.calendar_month, size: 22, color: AppColors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallTile extends StatelessWidget {
  const _SmallTile({required this.caption, required this.icon, required this.value, this.onTap, this.trailing, this.error});

  final String caption;
  final IconData icon;
  final String value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.control,
        side: error == null ? BorderSide.none : const BorderSide(color: AppColors.error),
      ),
      child: InkWell(
        borderRadius: AppRadius.control,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(caption, style: AppText.labelSm.copyWith(color: AppColors.secondary)),
                  ),
                  Icon(icon, size: 18, color: AppColors.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      style: AppText.titleSm.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ?trailing,
                ],
              ),
              if (error != null) Text(error!, style: AppText.bodySm.copyWith(color: AppColors.error)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(backgroundColor: AppColors.surfaceContainerLowest),
      icon: Icon(icon, size: 16, color: onTap == null ? AppColors.outlineVariant : AppColors.onSurface),
    );
  }
}

/// Searchable customer list for choosing who a job is for.
class _CustomerPicker extends ConsumerStatefulWidget {
  const _CustomerPicker();

  @override
  ConsumerState<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<_CustomerPicker> {
  CustomerQuery _query = const CustomerQuery();

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(customerListProvider(_query));
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Padding(
        padding: EdgeInsets.fromLTRB(AppSpace.margin, 0, AppSpace.margin, MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Choose customer', style: AppText.headlineMd),
            Gap.md,
            AppSearchField(
              hint: 'Search name or phone…',
              onChanged: (t) => setState(() => _query = CustomerQuery(text: t.trim())),
            ),
            Gap.md,
            Expanded(
              child: switch (list) {
                AsyncData(:final value) when value.items.isEmpty => MessageView(
                  icon: Symbols.person_add,
                  title: 'No customer found',
                  message: 'Add the customer first, then create the job from their profile.',
                  actionLabel: 'Add customer',
                  onAction: () {
                    Navigator.of(context).pop();
                    context.push(Routes.customerNew);
                  },
                ),
                AsyncData(:final value) => ListView.separated(
                  itemCount: value.items.length,
                  separatorBuilder: (_, _) => Gap.sm,
                  itemBuilder: (context, i) {
                    final c = value.items[i];
                    return AppCard(
                      onTap: () => Navigator.of(context).pop(c),
                      child: Row(
                        children: [
                          InitialsAvatar(name: c.fullName),
                          Gap.md,
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.fullName, style: AppText.titleSm),
                                if (c.phone != null) Text(Fmt.phone(c.phone!), style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                AsyncError(:final error) => ErrorView(error: error, onRetry: () => ref.invalidate(customerListProvider(_query))),
                _ => const LoadingView(),
              },
            ),
          ],
        ),
      ),
    );
  }
}
