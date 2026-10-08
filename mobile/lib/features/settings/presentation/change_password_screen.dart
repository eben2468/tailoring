import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app/section_scaffold.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/gap.dart';
import '../../auth/application/session_controller.dart';

/// Change password. Policy is enforced by the server (errors shown inline); the client checks
/// only length and confirmation to save a round trip.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _saving = false;
  Map<String, List<String>> _fieldErrors = const {};
  String? _formError;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _fieldErrors = const {};
      _formError = null;
    });
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(authRepositoryProvider).changePassword(_current.text, _next.text);
      if (!mounted) return;
      showAppSnack(context, 'Password changed. Your other devices were signed out.');
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
      title: 'Change password',
      body: Form(
        key: _formKey,
        child: ListView(
          padding: belowHeader(context),
          children: [
            AppCard(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: AutofillGroup(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (_formError != null) ...[FormBanner(message: _formError!), Gap.md],
                  AppTextField(
                    label: 'Current password',
                    controller: _current,
                    obscure: true,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.next,
                    errorText: _fieldErrors['current_password']?.first,
                    validator: (v) => (v == null || v.isEmpty) ? 'Enter your current password.' : null,
                  ),
                  Gap.md,
                  AppTextField(
                    label: 'New password',
                    controller: _next,
                    obscure: true,
                    autofillHints: const [AutofillHints.newPassword],
                    textInputAction: TextInputAction.next,
                    helperText: 'At least 10 characters. Avoid common words and your email name.',
                    errorText: _fieldErrors['new_password']?.join('\n'),
                    validator: (v) => (v == null || v.length < 10) ? 'Use at least 10 characters.' : null,
                  ),
                  Gap.md,
                  AppTextField(
                    label: 'Confirm new password',
                    controller: _confirm,
                    obscure: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    validator: (v) => v != _next.text ? 'The passwords do not match.' : null,
                  ),
                  Gap.lg,
                  AppButton(label: 'Update password', icon: Symbols.lock_reset, expand: true, loading: _saving, onPressed: _submit),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
