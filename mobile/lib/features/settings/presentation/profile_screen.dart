import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/routes.dart';
import '../../../app/section_scaffold.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/menu_row.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/state_views.dart';
import '../../auth/application/session_controller.dart';
import '../../sync/application/sync_providers.dart';

/// Own profile: name + phone (email and role are managed by the admin), plus session controls.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _phone;
  bool _saving = false;
  Map<String, List<String>> _fieldErrors = const {};

  @override
  void initState() {
    super.initState();
    final user = ref.read(sessionControllerProvider).value?.user;
    _name = TextEditingController(text: user?.fullName ?? '');
    _phone = TextEditingController(text: user?.phone ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _fieldErrors = const {});
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final phone = _phone.text.replaceAll(RegExp(r'\s'), '');
    try {
      await ref.read(sessionControllerProvider.notifier).updateProfile(fullName: _name.text.trim(), phone: phone.isEmpty ? null : phone);
      if (mounted) showAppSnack(context, 'Profile updated.');
    } on ValidationException catch (e) {
      setState(() => _fieldErrors = e.fieldErrors);
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOutEverywhere() async {
    final ok = await confirmAction(
      context,
      title: 'Sign out on all devices?',
      message: 'Every phone or tablet signed in to your account, including this one, will need to sign in again.',
      confirmLabel: 'Sign out everywhere',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(sessionControllerProvider.notifier).signOutEverywhere();
      ref.read(localStoreProvider).wipe();
    } on ApiException catch (e) {
      if (mounted) showAppSnack(context, e.message, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider).value;
    if (session == null) return const DetailScaffold(title: 'Profile', body: LoadingView());
    final user = session.user;

    return DetailScaffold(
      title: 'Profile',
      body: Form(
        key: _formKey,
        child: ListView(
          padding: belowHeader(context),
          children: [
            AppCard(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Row(children: [
                InitialsAvatar(name: user.fullName, size: 56, dark: true),
                Gap.md,
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(user.fullName, style: AppText.headlineMd, overflow: TextOverflow.ellipsis),
                    Text(user.email, style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant), overflow: TextOverflow.ellipsis),
                    Gap.xs,
                    Text(user.isAdmin ? 'SYSTEM ADMIN' : 'OWNER', style: AppText.overline.copyWith(color: AppColors.secondary)),
                  ]),
                ),
              ]),
            ),
            Gap.xl,
            const Kicker('Your details'),
            AppCard(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Column(children: [
                AppTextField(
                  label: 'Full name',
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  errorText: _fieldErrors['full_name']?.first,
                  validator: (v) => (v == null || v.trim().length < 2) ? 'Enter your full name.' : null,
                ),
                Gap.md,
                AppTextField(
                  label: 'Phone (optional)',
                  controller: _phone,
                  hint: '+233 24 123 4567',
                  keyboardType: TextInputType.phone,
                  errorText: _fieldErrors['phone']?.first,
                  helperText: 'International format, e.g. +233241234567',
                  validator: (v) {
                    final value = (v ?? '').replaceAll(' ', '');
                    if (value.isEmpty) return null;
                    return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(value) ? null : 'Use international format, e.g. +233241234567.';
                  },
                ),
                Gap.lg,
                AppButton(label: 'Save changes', icon: Symbols.check, expand: true, loading: _saving, onPressed: _save),
              ]),
            ),
            Gap.xl,
            const Kicker('Security'),
            MenuGroup(children: [
              MenuRow(icon: Symbols.key, title: 'Change password', subtitle: 'Signs out your other devices', onTap: () => context.push(Routes.changePassword)),
              MenuRow(icon: Symbols.devices, title: 'Sign out on all devices', subtitle: 'Use if a phone is lost or shared', destructive: true, onTap: _signOutEverywhere),
            ]),
          ],
        ),
      ),
    );
  }
}
