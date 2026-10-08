import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

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
import '../../../core/widgets/section_header.dart';
import '../application/admin_providers.dart';

/// Admin: create an owner or admin account.
class NewUserScreen extends ConsumerStatefulWidget {
  const NewUserScreen({super.key});

  @override
  ConsumerState<NewUserScreen> createState() => _NewUserScreenState();
}

class _NewUserScreenState extends ConsumerState<NewUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  String _role = 'owner';
  bool _saving = false;
  Map<String, List<String>> _fieldErrors = const {};
  String? _formError;

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _fieldErrors = const {};
      _formError = null;
    });
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final phone = _phone.text.replaceAll(RegExp(r'\s'), '');
    try {
      await ref.read(adminApiProvider).createUser(
            fullName: _name.text.trim(),
            email: _email.text.trim(),
            role: _role,
            password: _password.text,
            phone: phone.isEmpty ? null : phone,
          );
      ref.invalidate(adminUsersProvider);
      if (!mounted) return;
      showAppSnack(context, 'Account created. Share the password privately.');
      context.pop();
    } on ValidationException catch (e) {
      setState(() => _fieldErrors = e.fieldErrors);
    } on ApiException catch (e) {
      setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      title: 'New account',
      body: Form(
        key: _formKey,
        child: ListView(
          padding: belowHeader(context),
          children: [
            const Kicker('Role'),
            Row(children: [
              Expanded(child: _RoleChoice(label: 'Owner', description: 'Runs the business', icon: Symbols.storefront, selected: _role == 'owner', onTap: () => setState(() => _role = 'owner'))),
              Gap.sm,
              Expanded(child: _RoleChoice(label: 'Admin', description: 'System support', icon: Symbols.admin_panel_settings, selected: _role == 'admin', onTap: () => setState(() => _role = 'admin'))),
            ]),
            Gap.xl,
            const Kicker('Details'),
            AppCard(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_formError != null) ...[FormBanner(message: _formError!), Gap.md],
                AppTextField(
                  label: 'Full name',
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  errorText: _fieldErrors['full_name']?.first,
                  validator: (v) => (v == null || v.trim().length < 2) ? 'Enter the full name.' : null,
                ),
                Gap.md,
                AppTextField(
                  label: 'Email',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  errorText: _fieldErrors['email']?.first,
                  validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v?.trim() ?? '') ? null : 'Enter a valid email address.',
                ),
                Gap.md,
                AppTextField(
                  label: 'Phone (optional)',
                  controller: _phone,
                  hint: '+233 24 123 4567',
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  errorText: _fieldErrors['phone']?.first,
                ),
                Gap.md,
                AppTextField(
                  label: 'Temporary password',
                  controller: _password,
                  obscure: true,
                  helperText: 'At least 10 characters. They can change it after signing in.',
                  errorText: _fieldErrors['password']?.join('\n'),
                  validator: (v) => (v == null || v.length < 10) ? 'Use at least 10 characters.' : null,
                ),
              ]),
            ),
            Gap.xl,
            AppButton(label: 'Create account', icon: Symbols.person_add, expand: true, loading: _saving, onPressed: _submit),
          ],
        ),
      ),
    );
  }
}

/// Selectable card like the "Production Priority" choices on the create-job design.
class _RoleChoice extends StatelessWidget {
  const _RoleChoice({required this.label, required this.description, required this.icon, required this.selected, required this.onTap});

  final String label;
  final String description;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? AppColors.secondaryFixed : AppColors.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.control,
          side: BorderSide(color: selected ? AppColors.secondary : Colors.transparent, width: 1.5),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.control,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.md, horizontal: AppSpace.sm),
            child: Column(children: [
              Icon(icon, size: 20, color: selected ? AppColors.secondary : AppColors.onSurfaceVariant, fill: selected ? 1 : 0),
              Gap.xs,
              Text(label, style: AppText.labelMd.copyWith(color: selected ? AppColors.onSecondaryFixed : AppColors.onSurface)),
              Text(description, style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant), textAlign: TextAlign.center),
            ]),
          ),
        ),
      ),
    );
  }
}
