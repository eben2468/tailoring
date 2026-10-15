import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';

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
import '../../customers/application/customer_providers.dart';
import '../../customers/presentation/customer_picker.dart';
import '../../jobs/application/job_providers.dart';
import '../../sync/application/sync_providers.dart';
import '../application/calendar_providers.dart';
import '../data/appointments_api.dart';
import '../domain/calendar.dart';

/// Book or change an appointment: type, customer, job (optional), date, time, duration, room, reminder.
/// A fitting booked for a job is linked to the job's next fitting stage automatically.
class AppointmentFormScreen extends ConsumerWidget {
  const AppointmentFormScreen({super.key, this.appointmentId, this.date, this.customerId, this.jobId, this.type});

  final String? appointmentId;
  final DateTime? date;
  final String? customerId;
  final String? jobId;
  final String? type;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (appointmentId == null) return _AppointmentForm(date: date, customerId: customerId, jobId: jobId, type: AppointmentType.parse(type ?? 'fitting'));
    return switch (ref.watch(appointmentProvider(appointmentId!))) {
      AsyncData(:final value) => _AppointmentForm(existing: value, type: value.type),
      AsyncError(:final error) => DetailScaffold(title: 'Edit appointment', body: ErrorView(error: error, onRetry: () => ref.invalidate(bootstrapProvider))),
      _ => const DetailScaffold(title: 'Edit appointment', body: LoadingView()),
    };
  }
}

class _AppointmentForm extends ConsumerStatefulWidget {
  const _AppointmentForm({required this.type, this.existing, this.date, this.customerId, this.jobId});

  final Appointment? existing;
  final AppointmentType type;
  final DateTime? date;
  final String? customerId;
  final String? jobId;

  @override
  ConsumerState<_AppointmentForm> createState() => _AppointmentFormState();
}

class _AppointmentFormState extends ConsumerState<_AppointmentForm> {
  static const _durations = [15, 30, 45, 60, 90, 120];
  static const _reminders = <(int?, String)>[(null, 'None'), (30, '30 min'), (60, '1 hour'), (120, '2 hours'), (1440, '1 day')];

  late AppointmentType _type = widget.type;
  late String? _customerId = widget.existing?.customerId ?? widget.customerId;
  late String? _jobId = widget.existing?.jobId ?? widget.jobId;
  late DateTime _day = dayOf(widget.existing?.startsAt ?? widget.date ?? DateTime.now());
  late TimeOfDay _time = widget.existing == null ? _nextSlot() : TimeOfDay.fromDateTime(widget.existing!.startsAt);
  late int _minutes = widget.existing?.duration.inMinutes ?? (widget.type == AppointmentType.collection ? 30 : 60);
  late int? _reminder = widget.existing?.reminderMinutesBefore ?? 60;
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _location = TextEditingController(text: widget.existing?.location);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late bool _titleEdited = widget.existing != null;
  Map<String, String> _errors = const {};
  bool _saving = false;

  bool get _editing => widget.existing != null;

  static TimeOfDay _nextSlot() {
    final now = DateTime.now().add(const Duration(hours: 1));
    return TimeOfDay(hour: now.hour.clamp(8, 17), minute: 0);
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  /// "Fitting — 3-Piece Suit" until the owner types a title of their own.
  String _suggestedTitle() {
    final job = _jobId == null ? null : ref.read(jobProvider(_jobId!)).value;
    final customer = _customerId == null ? null : ref.read(customerProvider(_customerId!)).value;
    final what = job?.title ?? customer?.fullName;
    return what == null ? _type.label : '${_type.label} — $what';
  }

  Future<void> _save({bool allowOverlap = false}) async {
    final starts = DateTime(_day.year, _day.month, _day.day, _time.hour, _time.minute);
    final title = _title.text.trim().isEmpty ? _suggestedTitle() : _title.text.trim();
    String? fittingTask;
    if (_type == AppointmentType.fitting && _jobId != null) {
      final job = ref.read(jobProvider(_jobId!)).value;
      fittingTask = job?.tasks.where((t) => t.taskType.isFitting && !t.status.isClosed).firstOrNull?.id ?? (_editing ? widget.existing!.jobTaskId : null);
    }
    final draft = AppointmentDraft(
      type: _type,
      title: title,
      startsAt: starts,
      endsAt: starts.add(Duration(minutes: _minutes)),
      customerId: _customerId,
      jobId: _jobId,
      jobTaskId: fittingTask,
      location: _location.text,
      reminderMinutesBefore: _reminder,
      notes: _notes.text,
    );
    setState(() {
      _saving = true;
      _errors = const {};
    });
    try {
      final api = ref.read(appointmentsApiProvider);
      final saved = _editing ? await api.update(widget.existing!, draft, allowOverlap: allowOverlap) : await api.create(draft, allowOverlap: allowOverlap);
      if (!mounted) return;
      showAppSnack(context, _editing ? 'Appointment updated.' : '${saved.type.label} booked for ${DateFormat('EEE d MMM, HH:mm').format(saved.startsAt)}.');
      context.pop();
    } on ConflictException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (e.code == 'SCHEDULE_CONFLICT' &&
          await confirmAction(context, title: 'Time already booked', message: '${e.message} Book it anyway?', confirmLabel: 'Book anyway')) {
        await _save(allowOverlap: true);
      } else if (e.code != 'SCHEDULE_CONFLICT' && mounted) {
        showAppSnack(context, e.message, isError: true);
      }
    } on ValidationException catch (e) {
      if (mounted) setState(() => _errors = {for (final entry in e.fieldErrors.entries) entry.key: entry.value.first});
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customer = _customerId == null ? null : ref.watch(customerProvider(_customerId!)).value;
    final jobs = _customerId == null ? null : ref.watch(jobListProvider(JobQuery(customerId: _customerId))).value?.items;
    if (!_titleEdited && _title.text != _suggestedTitle()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_titleEdited) _title.text = _suggestedTitle();
      });
    }

    Widget tile(String caption, String value, IconData icon, VoidCallback onTap, {String? error}) => Expanded(
          child: Material(
            color: AppColors.surfaceContainerLow,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.control, side: error == null ? BorderSide.none : const BorderSide(color: AppColors.error)),
            child: InkWell(
              borderRadius: AppRadius.control,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(AppSpace.md),
                child: Row(children: [
                  Icon(icon, size: 20, color: AppColors.onSurfaceVariant),
                  Gap.sm,
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(caption, style: AppText.labelSm.copyWith(color: AppColors.secondary)),
                      Text(value, style: AppText.titleSm),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        );

    return DetailScaffold(
      title: _editing ? 'Edit appointment' : 'New appointment',
      bottomBar: BottomActionBar(
        child: AppButton(label: _editing ? 'Save changes' : 'Book ${_type.label}', icon: Symbols.event_available, expand: true, loading: _saving, onPressed: () => _save()),
      ),
      body: ListView(
        padding: belowHeader(context, bottom: 24),
        children: [
          Text(_editing ? 'Change appointment' : 'Schedule', style: AppText.headlineLg),
          Gap.lg,
          AppCard(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Kicker('Type'),
              Gap.sm,
              FilterPills(
                labels: [for (final t in AppointmentType.values) t.label],
                selected: AppointmentType.values.indexOf(_type),
                onChanged: (i) => setState(() => _type = AppointmentType.values[i]),
              ),
              Gap.lg,
              Kicker('Customer', trailing: _customerId == null || _editing ? null : AppButton(label: 'Clear', variant: AppButtonVariant.text, size: AppButtonSize.small, onPressed: () => setState(() {
                    _customerId = null;
                    _jobId = null;
                  }))),
              Gap.sm,
              if (customer == null)
                AppButton(
                  label: 'Choose customer',
                  icon: Symbols.person_search,
                  variant: AppButtonVariant.outline,
                  expand: true,
                  onPressed: () async {
                    final picked = await pickCustomer(context);
                    if (picked != null) setState(() => _customerId = picked.id);
                  },
                )
              else
                InsetTile(
                  padding: const EdgeInsets.all(AppSpace.md),
                  child: Row(children: [
                    InitialsAvatar(name: customer.fullName),
                    Gap.md,
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(customer.fullName, style: AppText.titleSm),
                        if (customer.phone != null) Text(Fmt.phone(customer.phone!), style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                      ]),
                    ),
                    if (!_editing)
                      AppButton(
                        label: 'Change',
                        variant: AppButtonVariant.text,
                        size: AppButtonSize.small,
                        onPressed: () async {
                          final picked = await pickCustomer(context);
                          if (picked != null) {
                            setState(() {
                              _customerId = picked.id;
                              _jobId = null;
                            });
                          }
                        },
                      ),
                  ]),
                ),
              if (jobs != null && jobs.isNotEmpty) ...[
                Gap.md,
                Text('For job', style: AppText.labelMd.copyWith(color: AppColors.onSurfaceVariant)),
                Gap.xs,
                FilterPills(
                  labels: ['No job', for (final j in jobs) '${j.displayNumber} ${j.jobTypeName}'],
                  selected: _jobId == null ? 0 : jobs.indexWhere((j) => j.id == _jobId) + 1,
                  onChanged: (i) => setState(() => _jobId = i == 0 ? null : jobs[i - 1].id),
                ),
              ],
              if (_errors['customer_id'] ?? _errors['job_id'] case final error?) ...[Gap.xs, Text(error, style: AppText.bodySm.copyWith(color: AppColors.error))],
            ]),
          ),
          Gap.lg,
          AppCard(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Kicker('When'),
              Gap.sm,
              Row(children: [
                tile('DAY', DateFormat('EEE d MMM').format(_day), Symbols.calendar_month, () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _day,
                    firstDate: DateTime.now().subtract(const Duration(days: 365)),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (picked != null) setState(() => _day = picked);
                }, error: _errors['starts_at']),
                Gap.sm,
                tile('TIME', _time.format(context), Symbols.schedule, () async {
                  final picked = await showTimePicker(context: context, initialTime: _time);
                  if (picked != null) setState(() => _time = picked);
                }),
              ]),
              Gap.md,
              Text('Duration', style: AppText.labelMd.copyWith(color: AppColors.onSurfaceVariant)),
              Gap.xs,
              FilterPills(
                labels: [for (final m in _durations) m < 60 ? '$m min' : (m % 60 == 0 ? '${m ~/ 60} h' : '${m / 60} h')],
                selected: _durations.contains(_minutes) ? _durations.indexOf(_minutes) : -1,
                onChanged: (i) => setState(() => _minutes = _durations[i]),
              ),
              if (_errors['ends_at'] case final error?) ...[Gap.xs, Text(error, style: AppText.bodySm.copyWith(color: AppColors.error))],
              Gap.md,
              Text('Reminder', style: AppText.labelMd.copyWith(color: AppColors.onSurfaceVariant)),
              Gap.xs,
              FilterPills(
                labels: [for (final r in _reminders) r.$2],
                selected: _reminders.indexWhere((r) => r.$1 == _reminder),
                onChanged: (i) => setState(() => _reminder = _reminders[i].$1),
              ),
            ]),
          ),
          Gap.lg,
          AppCard(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppTextField(
                label: 'Title',
                controller: _title,
                errorText: _errors['title'],
                maxLength: 150,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => _titleEdited = true,
              ),
              Gap.md,
              AppTextField(label: 'Room', hint: 'e.g. Fitting Room 1', controller: _location, prefixIcon: Symbols.location_on, maxLength: 120, textCapitalization: TextCapitalization.words),
              Gap.md,
              AppTextField(label: 'Notes', controller: _notes, maxLines: 4, minLines: 2, textCapitalization: TextCapitalization.sentences),
            ]),
          ),
          if (!_editing && _type == AppointmentType.fitting && _jobId != null) ...[
            Gap.md,
            Text('This fitting is linked to the job\'s next fitting stage.', style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}
