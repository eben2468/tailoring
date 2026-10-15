import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/menu_row.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/session_controller.dart';
import '../application/admin_providers.dart';
import '../data/admin_api.dart';
import 'users_screen.dart';

/// Admin: one account — activate/deactivate, change role, reset password, sign out everywhere.
class UserDetailScreen extends ConsumerWidget {
  const UserDetailScreen({super.key, required this.userId});

  final int userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(adminUserProvider(userId));
    final me = ref.watch(sessionControllerProvider).value?.user;

    return DetailScaffold(
      title: 'Account',
      body: switch (user) {
        AsyncData(:final value) => _Body(user: value, isSelf: me?.id == value.id),
        AsyncError(:final error) => ErrorView(error: error, onRetry: () => ref.invalidate(adminUserProvider(userId))),
        _ => const LoadingView(),
      },
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.user, required this.isSelf});

  final AdminUser user;
  final bool isSelf;

  Future<void> _run(BuildContext context, WidgetRef ref, Future<String> Function() action) async {
    try {
      final message = await action();
      ref
        ..invalidate(adminUserProvider(user.id))
        ..invalidate(adminUsersProvider);
      if (context.mounted) showAppSnack(context, message);
    } on ApiException catch (e) {
      if (context.mounted) showAppSnack(context, e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(adminApiProvider);

    return ListView(
      padding: belowHeader(context),
      children: [
        UserCard(user: user),
        Gap.md,
        AppCard(
          child: Column(
            children: [
              _InfoLine(label: 'Phone', value: user.phone ?? '—'),
              _InfoLine(label: 'Last sign-in', value: user.lastLoginAt == null ? 'Never' : Fmt.dateTime(user.lastLoginAt!)),
              _InfoLine(label: 'Created', value: user.createdAt == null ? '—' : Fmt.date(user.createdAt!)),
            ],
          ),
        ),
        Gap.xl,
        const Kicker('Access'),
        MenuGroup(
          children: [
            MenuRow(
              icon: Symbols.badge,
              title: 'Role',
              subtitle: user.role == 'admin' ? 'System admin — business data + administration' : 'Owner — all business features',
              trailing: isSelf
                  ? null
                  : AppButton(
                      label: user.role == 'admin' ? 'Make owner' : 'Make admin',
                      variant: AppButtonVariant.tonal,
                      size: AppButtonSize.small,
                      onPressed: () => _run(context, ref, () async {
                        await api.updateUser(user.id, {'role': user.role == 'admin' ? 'owner' : 'admin'});
                        return 'Role updated.';
                      }),
                    ),
            ),
            MenuRow(
              icon: user.isActive ? Symbols.toggle_on : Symbols.toggle_off,
              title: user.isActive ? 'Account active' : 'Account deactivated',
              subtitle: isSelf ? 'You cannot deactivate your own account' : (user.isActive ? 'Deactivating signs them out everywhere' : 'They cannot sign in'),
              trailing: isSelf
                  ? null
                  : Switch(
                      value: user.isActive,
                      onChanged: (active) async {
                        if (!active &&
                            !await confirmAction(
                              context,
                              title: 'Deactivate ${user.fullName}?',
                              message: 'They will be signed out on every device and cannot sign in until reactivated.',
                              confirmLabel: 'Deactivate',
                              destructive: true,
                            )) {
                          return;
                        }
                        if (!context.mounted) return;
                        await _run(context, ref, () async {
                          await api.updateUser(user.id, {'is_active': active});
                          return active ? 'Account reactivated.' : 'Account deactivated.';
                        });
                      },
                    ),
            ),
          ],
        ),
        Gap.xl,
        const Kicker('Security'),
        MenuGroup(
          children: [
            MenuRow(
              icon: Symbols.lock_reset,
              title: 'Reset password',
              subtitle: 'Set a temporary password and share it privately',
              onTap: () async {
                final password = await _askNewPassword(context, user.fullName);
                if (password == null || !context.mounted) return;
                await _run(context, ref, () async {
                  await api.resetPassword(user.id, password);
                  return 'Password reset. ${user.fullName} was signed out everywhere.';
                });
              },
            ),
            MenuRow(
              icon: Symbols.devices,
              title: 'Sign out on all devices',
              destructive: true,
              onTap: () async {
                if (!await confirmAction(
                  context,
                  title: 'Sign out ${user.fullName} everywhere?',
                  message: 'All of their devices will need to sign in again.',
                  confirmLabel: 'Sign out everywhere',
                  destructive: true,
                )) {
                  return;
                }
                if (!context.mounted) return;
                await _run(context, ref, () async => '${await api.revokeSessions(user.id)} session(s) signed out.');
              },
            ),
          ],
        ),
      ],
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Text(label, style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
          const Spacer(),
          Text(value, style: AppText.bodyMd.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// Bottom sheet asking for a temporary password (server enforces the policy).
Future<String?> _askNewPassword(BuildContext context, String name) => showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true, // above the bottom navigation and timer bar
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PasswordSheet(name: name),
    );

/// Owns its controller, so it is disposed with the sheet (after the closing animation).
class _PasswordSheet extends StatefulWidget {
  const _PasswordSheet({required this.name});

  final String name;

  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
  final controller = TextEditingController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.name;
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpace.margin, 0, AppSpace.margin, AppSpace.lg + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Reset password for $name', style: AppText.headlineMd),
          Gap.sm,
          Text('They will be signed out everywhere and must use this password next time.', style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
          Gap.lg,
          AppTextField(label: 'Temporary password', controller: controller, obscure: true, autofocus: true, helperText: 'At least 10 characters.'),
          Gap.lg,
          AppButton(
            label: 'Reset password',
            expand: true,
            onPressed: () {
              if (controller.text.length >= 10) Navigator.of(context).pop(controller.text);
            },
          ),
        ],
      ),
    );
  }
}
