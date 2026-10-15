import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
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
import '../../../core/widgets/bottom_action_bar.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/menu_row.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_pill.dart';
import '../../sync/application/sync_providers.dart';
import '../application/calendar_providers.dart';
import '../domain/calendar.dart';
import 'calendar_widgets.dart';

/// One appointment: when, who, which job, where; confirm / done / no-show / cancel; call or WhatsApp.
class AppointmentScreen extends ConsumerStatefulWidget {
  const AppointmentScreen({super.key, required this.appointmentId});

  final String appointmentId;

  @override
  ConsumerState<AppointmentScreen> createState() => _AppointmentScreenState();
}

class _AppointmentScreenState extends ConsumerState<AppointmentScreen> {
  bool _busy = false;

  Future<void> _status(Appointment a, AppointmentStatus status, String done) async {
    if (status == AppointmentStatus.cancelled &&
        !await confirmAction(context, title: 'Cancel this appointment?', message: '${a.title} on ${DateFormat('EEE d MMM, HH:mm').format(a.startsAt)}.', confirmLabel: 'Cancel appointment', destructive: true)) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(appointmentsApiProvider).setStatus(a, status);
      if (mounted) showAppSnack(context, done);
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Appointment a) async {
    if (!await confirmAction(context, title: 'Delete this appointment?', message: 'Use this for an appointment booked by mistake. To keep a record, cancel it instead.', confirmLabel: 'Delete', destructive: true)) {
      return;
    }
    try {
      await ref.read(appointmentsApiProvider).delete(a);
      if (mounted) {
        showAppSnack(context, 'Appointment deleted.');
        context.pop();
      }
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message, isError: true);
    }
  }

  Future<void> _open(Uri uri) async {
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted) showAppSnack(context, 'No app on this phone can open that.', isError: true);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(appointmentProvider(widget.appointmentId));
    final a = async.value;

    return DetailScaffold(
      title: 'Appointment',
      actions: [
        if (a != null && a.status.isOpen)
          IconButton(tooltip: 'Edit appointment', icon: const Icon(Symbols.edit, size: 22, color: AppColors.onSurfaceVariant), onPressed: () => context.push(Routes.appointmentEdit(a.id))),
      ],
      bottomBar: a == null || !a.status.isOpen
          ? null
          : BottomActionBar(
              child: Row(children: [
                if (a.status == AppointmentStatus.scheduled) ...[
                  Expanded(
                    child: AppButton(
                      label: 'Confirm',
                      icon: Symbols.check,
                      variant: AppButtonVariant.tonal,
                      onPressed: _busy ? null : () => _status(a, AppointmentStatus.confirmed, 'Appointment confirmed.'),
                    ),
                  ),
                  Gap.sm,
                ],
                Expanded(
                  child: AppButton(
                    label: 'Mark done',
                    icon: Symbols.task_alt,
                    loading: _busy,
                    onPressed: () => _status(a, AppointmentStatus.completed, 'Appointment marked done.'),
                  ),
                ),
              ]),
            ),
      body: switch (async) {
        AsyncData(value: final a) => ListView(
            padding: belowHeader(context, bottom: 24),
            children: [
              AppCard(
                padding: const EdgeInsets.all(AppSpace.lg),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Wrap(spacing: AppSpace.sm, children: [
                    StatusPill(label: a.type.label, tone: StatusTone.info, showDot: false),
                    StatusPill(label: a.status.label, tone: appointmentTone(a.status)),
                  ]),
                  Gap.md,
                  Text(a.title, style: AppText.headlineMd),
                  Gap.sm,
                  Row(children: [
                    const Icon(Symbols.schedule, size: 18, color: AppColors.secondary),
                    Gap.sm,
                    Expanded(
                      child: Text(
                        '${DateFormat('EEEE d MMMM').format(a.startsAt)} · ${hm(a.startsAt)}–${hm(a.endsAt)}',
                        style: AppText.bodyLg.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                    ),
                  ]),
                  if (a.location != null) ...[
                    Gap.xs,
                    Row(children: [
                      const Icon(Symbols.location_on, size: 18, color: AppColors.secondary),
                      Gap.sm,
                      Text(a.location!, style: AppText.bodyLg),
                    ]),
                  ],
                  if (a.reminderMinutesBefore != null) ...[
                    Gap.xs,
                    Row(children: [
                      const Icon(Symbols.notifications, size: 18, color: AppColors.onSurfaceVariant),
                      Gap.sm,
                      Text(
                        'Reminder ${a.reminderMinutesBefore! >= 1440 ? '${a.reminderMinutesBefore! ~/ 1440} day' : a.reminderMinutesBefore! >= 60 ? '${a.reminderMinutesBefore! ~/ 60} h' : '${a.reminderMinutesBefore} min'} before',
                        style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                      ),
                    ]),
                  ],
                  if (a.notes != null) ...[Gap.md, InsetTile(padding: const EdgeInsets.all(AppSpace.md), child: Text(a.notes!, style: AppText.bodyMd))],
                ]),
              ),
              if (a.customerName != null || a.jobId != null) ...[
                Gap.lg,
                MenuGroup(children: [
                  if (a.customerName != null)
                    MenuRow(
                      icon: Symbols.person,
                      title: a.customerName!,
                      subtitle: a.customerPhone == null ? 'Customer profile' : Fmt.phone(a.customerPhone!),
                      onTap: () => context.push(Routes.customer(a.customerId!)),
                    ),
                  if (a.jobId != null)
                    MenuRow(
                      icon: Symbols.content_cut,
                      title: a.jobNumber == null ? (a.jobTitle ?? 'Job') : 'Job #${a.jobNumber}',
                      subtitle: a.jobTitle,
                      onTap: () => context.push(Routes.job(a.jobId!)),
                    ),
                ]),
              ],
              if (a.customerPhone != null) ...[
                Gap.md,
                Row(children: [
                  Expanded(
                    child: AppButton(label: 'Call', icon: Symbols.call, variant: AppButtonVariant.outline, onPressed: () => _open(Uri(scheme: 'tel', path: a.customerPhone))),
                  ),
                  Gap.sm,
                  Expanded(
                    child: AppButton(
                      label: 'WhatsApp',
                      icon: Symbols.chat,
                      variant: AppButtonVariant.outline,
                      onPressed: () => _open(Uri.parse(
                        'https://wa.me/${Fmt.phoneDigits(a.customerPhone!)}?text=${Uri.encodeComponent('Hello ${a.customerName?.split(' ').first ?? ''}, a reminder of your ${a.type.label.toLowerCase()} on ${DateFormat('EEEE d MMMM').format(a.startsAt)} at ${hm(a.startsAt)}.')}',
                      )),
                    ),
                  ),
                ]),
              ],
              if (a.status.isOpen) ...[
                Gap.xl,
                MenuGroup(children: [
                  MenuRow(icon: Symbols.person_off, title: 'Customer did not come', subtitle: 'Mark as no-show', onTap: () => _status(a, AppointmentStatus.noShow, 'Marked as no-show.')),
                  MenuRow(icon: Symbols.event_busy, title: 'Cancel appointment', destructive: true, onTap: () => _status(a, AppointmentStatus.cancelled, 'Appointment cancelled.')),
                  MenuRow(icon: Symbols.delete, title: 'Delete (booked by mistake)', destructive: true, onTap: () => _delete(a)),
                ]),
              ],
            ],
          ),
        AsyncError(:final error) => ErrorView(error: error, onRetry: () => ref.invalidate(bootstrapProvider)),
        _ => const LoadingView(),
      },
    );
  }
}
