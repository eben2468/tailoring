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
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/bottom_action_bar.dart';
import '../../../core/widgets/feedback.dart';
import '../../../core/widgets/gap.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/segmented_tabs.dart';
import '../../../core/widgets/state_views.dart';
import '../../sync/application/sync_providers.dart';
import '../application/customer_providers.dart';
import '../domain/customer.dart';

/// Add or edit a customer. A phone number already used by someone else triggers a warning sheet
/// ("Open existing" / "Save anyway") instead of silently creating a duplicate.
class CustomerFormScreen extends ConsumerWidget {
  const CustomerFormScreen({super.key, this.customerId});

  /// null = new customer.
  final String? customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (customerId == null) return const _CustomerForm(existing: null);
    final customer = ref.watch(customerProvider(customerId!));
    return switch (customer) {
      AsyncData(:final value) => _CustomerForm(existing: value),
      AsyncError(:final error) => DetailScaffold(
        title: 'Edit customer',
        body: ErrorView(error: error, onRetry: () => ref.invalidate(bootstrapProvider)),
      ),
      _ => const DetailScaffold(title: 'Edit customer', body: LoadingView()),
    };
  }
}

class _CustomerForm extends ConsumerStatefulWidget {
  const _CustomerForm({required this.existing});

  final Customer? existing;

  @override
  ConsumerState<_CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends ConsumerState<_CustomerForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.fullName);
  late final _phone = TextEditingController(text: widget.existing?.phone);
  late final _phoneAlt = TextEditingController(text: widget.existing?.phoneAlt);
  late final _email = TextEditingController(text: widget.existing?.email);
  late final _address = TextEditingController(text: widget.existing?.address);
  late final _style = TextEditingController(text: widget.existing?.stylePreferences);
  late final _notes = TextEditingController(text: widget.existing?.notes);
  late String? _unit = widget.existing?.preferredUnit;
  bool _saving = false;
  Map<String, List<String>> _fieldErrors = const {};
  String? _formError;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    for (final c in [_name, _phone, _phoneAlt, _email, _address, _style, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  CustomerDraft get _draft => CustomerDraft(
    fullName: _name.text.trim(),
    phone: _phone.text,
    phoneAlt: _phoneAlt.text,
    email: _email.text,
    address: _address.text,
    stylePreferences: _style.text,
    notes: _notes.text,
    preferredUnit: _unit,
  );

  Future<void> _save({bool allowDuplicatePhone = false}) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _fieldErrors = const {};
      _formError = null;
    });
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final api = ref.read(customersApiProvider);
    try {
      final saved = _isNew
          ? await api.create(_draft, allowDuplicatePhone: allowDuplicatePhone)
          : await api.update(widget.existing!.id, widget.existing!.version, _draft, allowDuplicatePhone: allowDuplicatePhone);
      ref
        ..invalidate(customerListProvider)
        ..invalidate(customerProvider(saved.id));
      if (!mounted) return;
      showAppSnack(context, _isNew ? '${saved.fullName} added.' : 'Changes saved.');
      if (_isNew) {
        context.pushReplacement(Routes.customer(saved.id));
      } else {
        context.pop();
      }
    } on ConflictException catch (e) {
      if (e.code == 'DUPLICATE_PHONE') {
        setState(() => _saving = false); // the button must not keep spinning behind the warning sheet
        await _onDuplicatePhone();
      } else {
        setState(() => _formError = e.message); // CONFLICT_VERSION: edited elsewhere
      }
    } on ValidationException catch (e) {
      setState(() => _fieldErrors = e.fieldErrors);
    } on ApiException catch (e) {
      setState(() => _formError = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onDuplicatePhone() async {
    final matches = ref.read(customersApiProvider).phoneCheck(_phone.text, exceptId: widget.existing?.id);
    if (!mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true, // above the bottom navigation and timer bar
      useSafeArea: true,
      builder: (context) => _DuplicatePhoneSheet(phone: _phone.text, matches: matches),
    );
    if (!mounted || choice == null) return;
    if (choice == 'save') {
      await _save(allowDuplicatePhone: true);
    } else {
      context.pushReplacement(Routes.customer(choice));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DetailScaffold(
      title: _isNew ? 'New customer' : 'Edit customer',
      bottomBar: BottomActionBar(
        child: AppButton(label: _isNew ? 'Add customer' : 'Save changes', icon: Symbols.check, expand: true, loading: _saving, onPressed: _save),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: belowHeader(context),
          children: [
            if (_formError != null) ...[FormBanner(message: _formError!), Gap.md],
            const Kicker('Customer'),
            AppCard(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Column(
                children: [
                  AppTextField(
                    label: 'Full name',
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.next,
                    autofocus: _isNew,
                    prefixIcon: Symbols.person,
                    errorText: _fieldErrors['full_name']?.first,
                    validator: (v) => (v == null || v.trim().length < 2) ? 'Enter the customer\'s full name.' : null,
                  ),
                  Gap.md,
                  AppTextField(
                    label: 'Phone',
                    controller: _phone,
                    hint: '024 123 4567',
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    prefixIcon: Symbols.call,
                    errorText: _fieldErrors['phone']?.first,
                  ),
                  Gap.md,
                  AppTextField(
                    label: 'Alternative phone (optional)',
                    controller: _phoneAlt,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    prefixIcon: Symbols.phone_in_talk,
                    errorText: _fieldErrors['phone_alt']?.first,
                  ),
                  Gap.md,
                  AppTextField(
                    label: 'Email (optional)',
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    prefixIcon: Symbols.mail,
                    errorText: _fieldErrors['email']?.first,
                    validator: (v) => (v == null || v.trim().isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())) ? null : 'Enter a valid email address.',
                  ),
                  Gap.md,
                  AppTextField(label: 'Address (optional)', controller: _address, prefixIcon: Symbols.location_on, textCapitalization: TextCapitalization.words, errorText: _fieldErrors['address']?.first),
                ],
              ),
            ),
            Gap.xl,
            const Kicker('Measurement unit'),
            SegmentedTabs(
              labels: const ['Studio default', 'Inches', 'Centimetres'],
              selected: switch (_unit) {
                'in' => 1,
                'cm' => 2,
                _ => 0,
              },
              onChanged: (i) => setState(() => _unit = const [null, 'in', 'cm'][i]),
            ),
            Gap.xl,
            const Kicker('Style & notes'),
            AppCard(
              padding: const EdgeInsets.all(AppSpace.lg),
              child: Column(
                children: [
                  AppTextField(
                    label: 'Style preferences',
                    controller: _style,
                    hint: 'e.g. Dark horn buttons, burgundy lining, slim lapels',
                    maxLines: 5,
                    minLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    errorText: _fieldErrors['style_preferences']?.first,
                  ),
                  Gap.md,
                  AppTextField(
                    label: 'Notes',
                    controller: _notes,
                    hint: 'e.g. Prefers early-morning fittings',
                    maxLines: 5,
                    minLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    errorText: _fieldErrors['notes']?.first,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DuplicatePhoneSheet extends StatelessWidget {
  const _DuplicatePhoneSheet({required this.phone, required this.matches});

  final String phone;
  final List<PhoneMatch> matches;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpace.margin, 0, AppSpace.margin, AppSpace.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('This number is already saved', style: AppText.headlineMd),
          Gap.sm,
          Text('Check that this is not the same person before adding a second record.', style: AppText.bodyMd.copyWith(color: AppColors.onSurfaceVariant)),
          Gap.lg,
          for (final match in matches) ...[
            AppCard(
              color: AppColors.surfaceContainerLow,
              onTap: () => Navigator.of(context).pop(match.id),
              child: Row(
                children: [
                  const Icon(Symbols.person, size: 20, color: AppColors.onSurfaceVariant),
                  Gap.md,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(match.fullName, style: AppText.titleSm),
                        Text('${match.phone == null ? phone : Fmt.phone(match.phone!)}${match.isArchived ? ' · archived' : ''}', style: AppText.bodySm.copyWith(color: AppColors.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Text('Open', style: AppText.labelMd.copyWith(color: AppColors.secondary)),
                ],
              ),
            ),
            Gap.sm,
          ],
          Gap.md,
          AppButton(label: 'Save anyway', variant: AppButtonVariant.outline, expand: true, onPressed: () => Navigator.of(context).pop('save')),
          Gap.sm,
          AppButton(label: 'Cancel', variant: AppButtonVariant.text, expand: true, onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}
