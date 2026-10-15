import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/filter_pills.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/state_views.dart';
import '../../sync/application/sync_providers.dart';
import '../application/customer_providers.dart';
import '../domain/customer.dart';

/// Opens the customer picker; returns the chosen customer or null.
Future<Customer?> pickCustomer(BuildContext context) => showModalBottomSheet<Customer>(
      context: context,
      useRootNavigator: true, // above the bottom navigation and timer bar
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const CustomerPicker(),
    );

/// Searchable customer list (who a job or appointment is for).
class CustomerPicker extends ConsumerStatefulWidget {
  const CustomerPicker({super.key});

  @override
  ConsumerState<CustomerPicker> createState() => CustomerPickerState();
}

class CustomerPickerState extends ConsumerState<CustomerPicker> {
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
                AsyncError(:final error) => ErrorView(error: error, onRetry: () => ref.invalidate(bootstrapProvider)),
                _ => const LoadingView(),
              },
            ),
          ],
        ),
      ),
    );
  }
}
