import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../../../core/widgets/hero_panel.dart';
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

    // Navy brand panel (the app's hero-panel look) with the sign-in card overlapping its lower edge.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        body: SingleChildScrollView(
          child: Column(
            children: [
              HeroPanel(
                radius: const BorderRadius.vertical(bottom: Radius.circular(28)),
                padding: EdgeInsets.fromLTRB(AppSpace.margin, MediaQuery.paddingOf(context).top + 48, AppSpace.margin, 96),
                child: const SizedBox(width: double.infinity, child: _BrandBlock()),
              ),
              Transform.translate(
                offset: const Offset(0, -64),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.margin),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: AutofillGroup(
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AppCard(
                              padding: const EdgeInsets.all(AppSpace.lg),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text('Welcome back', style: AppText.headlineLg),
                                  Gap.xs,
                                  Text('Sign in to manage your atelier.', style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
                                  Gap.lg,
                                  if (_formError != null || notice != null) ...[FormBanner(message: _formError ?? notice!, isError: _formError != null), Gap.md],
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
                                  AppButton(label: 'Sign In', icon: Symbols.login, expand: true, loading: _submitting, onPressed: _submit),
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
            ],
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
        const BrandMark(size: 64, onDark: true),
        Gap.lg,
        Text(
          'Nutɔfe',
          style: AppText.displayLg.copyWith(color: AppColors.onPrimary),
          textAlign: TextAlign.center,
        ),
        Gap.xs,
        Text(
          'Bespoke tailoring studio',
          style: AppText.bodyLg.copyWith(color: AppColors.primaryFixedDim),
          textAlign: TextAlign.center,
        ),
        Gap.md,
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: AppColors.onPrimary.withValues(alpha: 0.1), borderRadius: AppRadius.full),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(color: AppColors.tertiaryFixedDim, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: FittedBox(fit: BoxFit.scaleDown, child: Text('PRODUCTION · MEASUREMENTS · SCHEDULE', style: AppText.labelSm.copyWith(color: AppColors.primaryFixed, fontSize: 10))),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
