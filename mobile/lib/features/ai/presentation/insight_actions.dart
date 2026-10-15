import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/widgets/feedback.dart';
import '../../inventory/domain/inventory.dart';
import '../../inventory/presentation/stock_sheet.dart';
import '../application/ai_providers.dart';
import '../domain/ai.dart';

/// Runs an insight card's suggested action (AI screen and dashboard). The card is marked seen; the AI
/// never changes data itself — the owner confirms in the screen or sheet that opens.
Future<void> runInsightAction(BuildContext context, WidgetRef ref, Insight insight) async {
  unawaited(ref.read(aiApiProvider).markSeen(insight).catchError((Object _) {}));
  final action = insight.action;
  switch (action?['type']) {
    case 'open_job':
      unawaited(context.push(Routes.job(action!['job_id'] as String)));
    case 'restock':
      final saved = await showStockSheet(context, itemId: action!['item_id'] as String, type: TransactionType.purchase, quantity: (action['quantity'] as num?)?.toDouble());
      if (saved == true && context.mounted) showAppSnack(context, 'Stock received.');
    case 'open_calendar':
      context.go(Routes.calendar);
    case 'open_templates':
      unawaited(context.push(Routes.garmentTypes));
  }
}
