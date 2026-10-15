import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/routes.dart';
import '../../../app/section_scaffold.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/filter_pills.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_pill.dart';
import '../../sync/application/sync_providers.dart';
import '../application/customer_providers.dart';
import '../domain/customer.dart';

/// Customers tab — search, active/archived filter, customer cards (layout follows the Stitch jobs list).
class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  CustomerQuery _query = const CustomerQuery();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _query = CustomerQuery(text: text.trim(), status: _query.status)));
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(customerListProvider(_query));
    final total = list.value?.total;

    return SectionScaffold(
      title: 'Customers',
      body: RefreshIndicator(
        edgeOffset: MediaQuery.paddingOf(context).top + 64,
        onRefresh: () => ref.read(syncControllerProvider.notifier).syncNow(),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: headerOnly(context),
              sliver: SliverList.list(children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Customers', style: AppText.headlineLg),
                      Gap.xs,
                      Row(children: [
                        Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            total == null ? 'Loading…' : '$total ${_query.status == 'archived' ? 'archived' : 'active'} customer${total == 1 ? '' : 's'}',
                            style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                    ]),
                  ),
                  AppButton(label: 'Customer', icon: Symbols.person_add, size: AppButtonSize.medium, onPressed: () => context.push(Routes.customerNew)),
                ]),
                Gap.lg,
                AppSearchField(hint: 'Search name, phone or email…', onChanged: _search, initialValue: _query.text),
                Gap.md,
                FilterPills(
                  labels: const ['Active', 'Archived'],
                  selected: _query.status == 'archived' ? 1 : 0,
                  onChanged: (i) => setState(() => _query = CustomerQuery(text: _query.text, status: i == 1 ? 'archived' : 'active')),
                ),
                Gap.lg,
              ]),
            ),
            ...switch (list) {
              AsyncData(:final value) when value.items.isEmpty => [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _query.text.isNotEmpty
                        ? MessageView(icon: Symbols.person_search, title: 'No matches', message: 'No customer matches "${_query.text}".')
                        : _query.status == 'archived'
                            ? const MessageView(icon: Symbols.inventory_2, title: 'No archived customers', message: 'Archived customers are kept with their history and can be restored.')
                            : MessageView(
                                icon: Symbols.contacts,
                                title: 'No customers yet',
                                message: 'Add your first customer to record measurements and create jobs.',
                                actionLabel: 'Add customer',
                                onAction: () => context.push(Routes.customerNew),
                              ),
                  ),
                ],
              AsyncData(:final value) => [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(AppSpace.margin, 0, AppSpace.margin, belowHeaderAboveNav(context).bottom),
                    sliver: SliverList.separated(
                      itemCount: value.items.length,
                      separatorBuilder: (_, _) => Gap.sm,
                      itemBuilder: (context, i) {
                        final customer = value.items[i];
                        return CustomerCard(customer: customer, onTap: () => context.push(Routes.customer(customer.id)));
                      },
                    ),
                  ),
                ],
              AsyncError(:final error) => [SliverFillRemaining(hasScrollBody: false, child: ErrorView(error: error, onRetry: () => ref.invalidate(bootstrapProvider)))],
              _ => [const SliverFillRemaining(hasScrollBody: false, child: LoadingView())],
            },
          ],
        ),
      ),
    );
  }
}

/// Customer row card: initials, name, phone, active-jobs and last-measured pills.
class CustomerCard extends StatelessWidget {
  const CustomerCard({super.key, required this.customer, this.onTap});

  final Customer customer;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final summary = customer.summary;
    return AppCard(
      onTap: onTap,
      child: Row(children: [
        InitialsAvatar(name: customer.fullName),
        Gap.md,
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(customer.fullName, style: AppText.titleSm, overflow: TextOverflow.ellipsis),
            Text(
              customer.phone == null ? (customer.email ?? 'No phone number') : Fmt.phone(customer.phone!),
              style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
            if (summary != null) ...[
              Gap.xs,
              Wrap(spacing: 6, runSpacing: 4, children: [
                if (summary.activeJobs > 0) StatusPill(label: '${summary.activeJobs} active job${summary.activeJobs == 1 ? '' : 's'}', tone: StatusTone.info),
                summary.lastMeasuredAt == null
                    ? const StatusPill(label: 'Not measured', tone: StatusTone.warning)
                    : StatusPill(label: 'Measured ${Fmt.date(summary.lastMeasuredAt!)}', tone: StatusTone.neutral, showDot: false),
              ]),
            ],
          ]),
        ),
        if (onTap != null) const Icon(Symbols.chevron_right, size: 20, color: AppColors.outline),
      ]),
    );
  }
}
