import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/brand_mark.dart';
import '../../../core/widgets/gap.dart';
import '../application/session_controller.dart';

/// Sign-in (no Stitch design exists; composed from the design system).
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _submitting = false;
  String? _formError;
  Map<String, List<String>> _fieldErrors = const {};

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _formError = null;
      _fieldErrors = const {};
    });
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      await ref.read(sessionControllerProvider.notifier).signIn(_email.text, _password.text);
      // The router redirects to the dashboard when the session changes.
    } on ValidationException catch (e) {
      setState(() => _fieldErrors = e.fieldErrors);
    } on ApiException catch (e) {
      setState(() => _formError = e.message);
      _password.clear();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final notice = ref.watch(signInNoticeProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.margin, vertical: AppSpace.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const _BrandBlock(),
                      Gap.xl,
                      AppCard(
                        padding: const EdgeInsets.all(AppSpace.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Welcome back', style: AppText.headlineLg),
                            Gap.xs,
                            Text('Sign in to manage your atelier.', style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
                            Gap.lg,
                            if (_formError != null || notice != null) ...[
                              FormBanner(message: _formError ?? notice!, isError: _formError != null),
                              Gap.md,
                            ],
                            AppTextField(
                              label: 'Email',
                              controller: _email,
                              hint: 'you@example.com',
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [AutofillHints.email, AutofillHints.username],
                              prefixIcon: Symbols.mail,
                              errorText: _fieldErrors['email']?.first,
                              validator: (v) {
                                final value = v?.trim() ?? '';
                                if (value.isEmpty) return 'Enter your email.';
                                if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value)) return 'Enter a valid email address.';
                                return null;
                              },
                            ),
                            Gap.md,
                            AppTextField(
                              label: 'Password',
                              controller: _password,
                              obscure: true,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              prefixIcon: Symbols.lock,
                              errorText: _fieldErrors['password']?.first,
                              onSubmitted: (_) => _submit(),
                              validator: (v) => (v == null || v.isEmpty) ? 'Enter your password.' : null,
                            ),
                            Gap.lg,
                            AppButton(
                              label: 'Sign In',
                              icon: Symbols.login,
                              expand: true,
                              loading: _submitting,
                              onPressed: _submit,
                            ),
                          ],
                        ),
                      ),
                      Gap.lg,
                      Text(
                        'Forgot your password? Your system administrator can reset it for you.',
                        style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandBlock extends StatelessWidget {
  const _BrandBlock();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const BrandMark(size: 56),
        Gap.md,
        Text('Nutɔfe', style: AppText.displayLgMobile, textAlign: TextAlign.center),
        Gap.xs,
        Text('Bespoke tailoring studio', style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant), textAlign: TextAlign.center),
      ],
    );
  }
}
