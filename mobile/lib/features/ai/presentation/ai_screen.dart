import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/section_scaffold.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/hero_panel.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/status_pill.dart';
import '../application/ai_providers.dart';
import '../domain/ai.dart';
import 'insight_actions.dart';

/// More → AI Assistant — Stitch "Sartor AI Business Assistant": status banner, proactive directives
/// (insight cards, also offline), estimate accuracy, capacity, quick queries and the grounded chat.
/// Money figures, photos and auto-scheduling in the design are out of scope (the AI only proposes).
class AiScreen extends ConsumerStatefulWidget {
  const AiScreen({super.key});

  @override
  ConsumerState<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends ConsumerState<AiScreen> {
  final _question = TextEditingController();
  final _scroll = ScrollController();

  static const _quickQueries = ['What should I work on today?', 'Which jobs may finish late?', 'Can I take another commission this week?', 'Which materials run out soon?', 'How accurate are my estimates?'];

  @override
  void dispose() {
    _question.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _ask(String text) async {
    _question.clear();
    FocusScope.of(context).unfocus();
    await ref.read(chatProvider.notifier).ask(text);
    if (mounted && _scroll.hasClients) unawaited(_scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut));
  }

  Future<void> _act(Insight i) => runInsightAction(context, ref, i);

  Future<void> _dismiss(Insight i) async {
    try {
      await ref.read(aiApiProvider).dismiss(i);
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final insights = ref.watch(insightsProvider).value ?? const <Insight>[];
    final overview = ref.watch(aiOverviewProvider);
    final chat = ref.watch(chatProvider);
    final o = overview.value;

    return DetailScaffold(
      title: 'AI Assistant',
      bottomBar: _AskBar(controller: _question, busy: chat.busy, onAsk: _ask),
      body: RefreshIndicator(
        edgeOffset: MediaQuery.paddingOf(context).top + 64,
        onRefresh: () => ref.refresh(aiOverviewProvider.future).then((_) {}, onError: (Object _) {}),
        child: ListView(controller: _scroll, padding: belowHeader(context), children: [
          _Banner(overview: o, offline: overview.hasError),
          Gap.lg,
          Row(children: [
            const Icon(Symbols.auto_awesome, size: 20, color: AppColors.secondary),
            Gap.sm,
            Expanded(child: Text('Proactive Directives', style: AppText.titleSm)),
            if (insights.isNotEmpty) StatusPill(label: '${insights.where((i) => i.isNew).length} fresh', tone: StatusTone.neutral, showDot: false),
          ]),
          Gap.sm,
          if (insights.isEmpty)
            AppCard(child: Text('Nothing needs your attention. Cards appear here when a job may finish late, the week fills up, or a material is about to run out.', style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant)))
          else
            for (final i in insights) ...[_InsightCard(insight: i, onAct: () => _act(i), onDismiss: () => _dismiss(i)), Gap.md],
          Gap.sm,
          if (o != null) ...[
            _PrecisionCard(accuracy: o.accuracy),
            Gap.md,
            _CapacityCard(workload: o.workload),
            Gap.lg,
          ] else if (overview.hasError) ...[
            AppCard(
              color: AppColors.surfaceContainerHigh,
              child: Row(children: [
                const Icon(Symbols.cloud_off, size: 20, color: AppColors.onSurfaceVariant),
                Gap.sm,
                Expanded(child: Text(_errorText(overview.error), style: AppText.bodyMd)),
              ]),
            ),
            Gap.lg,
          ],
          Text('ATELIER QUICK QUERIES', style: AppText.overline),
          Gap.sm,
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final q in _quickQueries)
              ActionChip(
                avatar: const Icon(Symbols.bolt, size: 16, color: AppColors.secondary),
                label: Text(q, style: AppText.labelMd),
                backgroundColor: AppColors.surfaceContainerLowest,
                side: const BorderSide(color: AppColors.outlineVariant),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.full),
                onPressed: chat.busy ? null : () => _ask(q),
              ),
          ]),
          if (chat.messages.isNotEmpty || chat.busy) ...[
            Gap.lg,
            Row(children: [
              const Icon(Symbols.forum, size: 20, color: AppColors.onSurface),
              Gap.sm,
              Expanded(child: Text('Atelier Query Stream', style: AppText.titleSm)),
              AppButton(label: 'Clear', variant: AppButtonVariant.text, size: AppButtonSize.small, onPressed: () => ref.read(chatProvider.notifier).clear()),
            ]),
            Gap.sm,
            for (final m in chat.messages) ...[_Bubble(message: m), Gap.sm],
            if (chat.busy) const Padding(padding: EdgeInsets.all(AppSpace.md), child: Center(child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)))),
          ],
          if (chat.error != null) ...[Gap.sm, Text(chat.error!, style: AppText.bodySm.copyWith(color: AppColors.error))],
        ]),
      ),
    );
  }

  static String _errorText(Object? e) => switch (e) {
        NetworkException() => 'Offline: the live figures and the chat need a connection. The cards above are from the last sync.',
        ApiException(:final message) => message,
        _ => 'The AI assistant is unavailable right now.',
      };
}

class _Banner extends StatelessWidget {
  const _Banner({required this.overview, required this.offline});

  final AiOverview? overview;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    final o = overview;
    final status = o == null ? (offline ? 'OFFLINE · CARDS FROM LAST SYNC' : 'CONNECTING…') : 'PRODUCTION COPILOT · ACTIVE';
    Widget chip(IconData icon, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: AppColors.primaryFixedDim),
          const SizedBox(width: 6),
          Flexible(child: Text(text, style: AppText.labelSm.copyWith(color: AppColors.primaryFixedDim, fontWeight: FontWeight.w500))),
        ]);
    return HeroPanel(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(color: AppColors.onPrimary.withValues(alpha: 0.1), borderRadius: AppRadius.full),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: o == null ? AppColors.outline : AppColors.tertiaryFixedDim, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Flexible(child: Text(status, style: AppText.labelSm.copyWith(color: AppColors.tertiaryFixedDim), maxLines: 1, overflow: TextOverflow.ellipsis)),
          ]),
        ),
        Gap.sm,
        Text('Nutɔfe AI Assistant', style: AppText.headlineLg.copyWith(color: AppColors.onPrimary)),
        const SizedBox(height: 2),
        Text(
          o == null ? 'Learns from your completed jobs, hours and stock.' : 'Learning from ${o.completedJobs} completed job${o.completedJobs == 1 ? '' : 's'}, your logged hours and stock use.',
          style: AppText.bodyMd.copyWith(color: AppColors.primaryFixedDim),
        ),
        if (o != null) ...[
          Gap.md,
          Row(children: [
            Expanded(child: chip(Symbols.memory, o.llmEnabled ? 'Engine: figures + Gemini' : 'Engine: figures only')),
            Expanded(child: chip(Symbols.tune, 'Bench: ${o.workload['state'] ?? '—'}')),
          ]),
        ],
      ]),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight, required this.onAct, required this.onDismiss});

  final Insight insight;
  final VoidCallback onAct;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final (label, tone) = switch (insight.severity) {
      'critical' => ('High Impact', StatusTone.danger),
      'warning' => ('Attention', StatusTone.warning),
      'advice' => ('Suggestion', StatusTone.info),
      _ => ('For your information', StatusTone.neutral),
    };
    final action = insight.action;
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          StatusPill(label: label, tone: tone),
          const Spacer(),
          if (insight.isNew) Text('NEW', style: AppText.labelSm.copyWith(color: AppColors.secondary)),
        ]),
        Gap.sm,
        Text(insight.title, style: AppText.headlineMd),
        Gap.xs,
        Text(insight.body, style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
        Gap.md,
        Row(children: [
          if (action != null && action['label'] != null)
            Expanded(child: AppButton(label: action['label'] as String, size: AppButtonSize.medium, expand: true, onPressed: onAct))
          else
            const Spacer(),
          Gap.sm,
          AppButton(label: 'Dismiss', size: AppButtonSize.medium, variant: AppButtonVariant.tonal, onPressed: onDismiss),
        ]),
      ]),
    );
  }
}

class _PrecisionCard extends StatelessWidget {
  const _PrecisionCard({required this.accuracy});

  final Map<String, dynamic> accuracy;

  @override
  Widget build(BuildContext context) {
    final percent = (accuracy['accuracy_percent'] as num?)?.toDouble();
    final stages = (accuracy['stages'] as num? ?? 0).toInt();
    final byStage = (accuracy['by_stage'] as List? ?? const []).cast<Map<dynamic, dynamic>>();
    final worst = byStage.isEmpty ? null : byStage.first;
    final bias = (accuracy['bias_percent'] as num?)?.toDouble();
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Symbols.speed, size: 18, color: AppColors.onSurfaceVariant),
          Gap.sm,
          Expanded(child: Text('LABOR PRECISION MODEL', style: AppText.overline)),
          if (bias != null) StatusPill(label: '${bias > 0 ? '+' : ''}${bias.toStringAsFixed(1)}% vs plan', tone: bias.abs() <= 10 ? StatusTone.success : StatusTone.warning, showDot: false),
        ]),
        Gap.sm,
        if (percent == null)
          Text('No completed stage with an estimate yet: accuracy appears once jobs are finished.', style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant))
        else ...[
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${percent.toStringAsFixed(1)}%', style: AppText.displayLgMobile),
            Gap.sm,
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text('Estimation accuracy across $stages stage${stages == 1 ? '' : 's'}', style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
              ),
            ),
          ]),
          Gap.sm,
          ClipRRect(
            borderRadius: AppRadius.full,
            child: LinearProgressIndicator(value: percent / 100, minHeight: 6, backgroundColor: AppColors.surfaceContainerHighest, color: AppColors.primaryContainer),
          ),
          Gap.sm,
          Text(
            worst == null
                ? '${accuracy['within_10_percent']}% of stages finished within ±10% of their estimate.'
                : '${worst['name']} runs ${(worst['bias_percent'] as num).abs()}% ${(worst['bias_percent'] as num) > 0 ? 'longer' : 'shorter'} than estimated over ${worst['stages']} stages.',
            style: AppText.bodyMd,
          ),
        ],
      ]),
    );
  }
}

class _CapacityCard extends StatelessWidget {
  const _CapacityCard({required this.workload});

  final Map<String, dynamic> workload;

  String _h(Object? s) {
    final h = ((s as num?) ?? 0) / 3600;
    return h == h.roundToDouble() ? '${h.round()} h' : '${h.toStringAsFixed(1)} h';
  }

  @override
  Widget build(BuildContext context) {
    final state = workload['state'] as String? ?? 'light';
    final util = (workload['utilization_percent'] as num?)?.toDouble();
    final (label, tone) = switch (state) {
      'overbooked' => ('Overbooked', StatusTone.danger),
      'full' => ('Full', StatusTone.warning),
      'optimal' => ('Optimal Load', StatusTone.success),
      _ => ('Light Load', StatusTone.info),
    };
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Symbols.trending_up, size: 18, color: AppColors.onSurfaceVariant),
          Gap.sm,
          Expanded(child: Text('CAPACITY · NEXT 7 DAYS', style: AppText.overline)),
          StatusPill(label: label, tone: tone, showDot: false),
        ]),
        Gap.md,
        Row(children: [
          Expanded(
            child: InsetTile(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Due this week', style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                Text(_h(workload['demand_seconds']), style: AppText.metricNum),
                Text('${workload['jobs_due'] ?? 0} jobs', style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant)),
              ]),
            ),
          ),
          Gap.sm,
          Expanded(
            child: InsetTile(
              padding: const EdgeInsets.all(AppSpace.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Capacity utilization', style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                Text(util == null ? '—' : '${util.round()}%', style: AppText.metricNum.copyWith(color: state == 'overbooked' ? AppColors.error : AppColors.secondary)),
                Text('of ${_h(workload['capacity_seconds'])}', style: AppText.labelSm.copyWith(color: AppColors.onSurfaceVariant)),
              ]),
            ),
          ),
        ]),
        Gap.md,
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(state == 'overbooked' ? Symbols.warning : Symbols.verified, size: 18, color: state == 'overbooked' ? AppColors.error : AppColors.secondary),
          Gap.sm,
          Expanded(
            child: Text(
              state == 'overbooked'
                  ? 'More work is due this week than the bench can do. Move a due date or plan extra hours.'
                  : 'Room for about ${_h(workload['free_seconds'])} more this week without overtime. Total backlog: ${_h(workload['backlog_seconds'])}.',
              style: AppText.bodyMd,
            ),
          ),
        ]),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    if (message.fromUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: const BoxDecoration(color: AppColors.primaryContainer, borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(4), bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12))),
          child: Text(message.text, style: AppText.bodyMd.copyWith(color: AppColors.onPrimary)),
        ),
      );
    }
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Nutɔfe Copilot', style: AppText.labelMd.copyWith(color: AppColors.secondary)),
          const SizedBox(width: 6),
          Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.tertiaryFixedDim, shape: BoxShape.circle)),
          Gap.sm,
          Expanded(
            child: Text(
              message.source == 'analytics' ? 'from your figures' : 'Gemini, grounded',
              style: AppText.labelSm.copyWith(color: AppColors.outline),
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
        Gap.xs,
        Text.rich(answerSpans(message.text, AppText.bodyMd)),
      ]),
    );
  }
}

class _AskBar extends StatelessWidget {
  const _AskBar({required this.controller, required this.busy, required this.onAsk});

  final TextEditingController controller;
  final bool busy;
  final ValueChanged<String> onAsk;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(AppSpace.margin, AppSpace.sm, AppSpace.margin, AppSpace.sm + MediaQuery.paddingOf(context).bottom),
      decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, boxShadow: AppShadows.bottomBar),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: !busy,
            textInputAction: TextInputAction.send,
            maxLength: 1000,
            onSubmitted: onAsk,
            decoration: InputDecoration(
              hintText: 'Ask about your production…',
              counterText: '',
              filled: true,
              fillColor: AppColors.surfaceContainerLow,
              isDense: true,
              border: OutlineInputBorder(borderRadius: AppRadius.full, borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ),
        Gap.sm,
        AppButton(label: 'Ask', icon: Symbols.arrow_upward, size: AppButtonSize.medium, loading: busy, onPressed: () => onAsk(controller.text)),
      ]),
    );
  }
}

/// The language model writes light markdown: `**bold**` becomes bold and "* " / "- " lines become bullets.
/// Job numbers such as "#027" are left as they are.
@visibleForTesting
TextSpan answerSpans(String text, TextStyle style) {
  final lines = text.split('\n').map((line) {
    final m = RegExp(r'^(\s*)[*-]\s+(.*)$').firstMatch(line);
    return m == null ? line : '${m[1]}• ${m[2]}';
  }).join('\n');
  final parts = lines.split('**');
  return TextSpan(style: style, children: [
    for (final (i, part) in parts.indexed)
      // An unmatched trailing "**" leaves an odd count: keep that last part plain.
      TextSpan(text: part, style: i.isOdd && i < parts.length - (parts.length.isEven ? 1 : 0) ? const TextStyle(fontWeight: FontWeight.w700) : null),
  ]);
}
