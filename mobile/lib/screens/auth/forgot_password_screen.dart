import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/medguard_colors.dart';
import '../../widgets/common/app_text_field.dart';
import '../../theme/medguard_palette.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/top_text_navigation_action.dart';
import 'auth_components.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  static const String routeName = '/forgot-password';

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendResetLink() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(
        email: _emailCtrl.text.trim(),
      );
      if (!mounted) return;
      showAuthSnackBar(
        context,
        'Reset link sent. Check your email inbox.',
        isError: false,
      );
    } catch (error) {
      if (!mounted) return;
      showAuthSnackBar(context, authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _goBack() async {
    // Pop to the screen that opened this one; no hardcoded fallback.
    await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: medGuardSystemUi(context.colors),
      child: Scaffold(
        backgroundColor: MedGuardPalette.teal,
        body: Stack(
          children: [
            const Positioned.fill(
              child: ColoredBox(color: MedGuardPalette.teal),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: FractionallySizedBox(
                heightFactor: 0.82,
                widthFactor: 1,
                alignment: Alignment.bottomCenter,
                child: _ResetCard(
                  formKey: _formKey,
                  emailCtrl: _emailCtrl,
                  loading: _loading,
                  onSendResetLink: _sendResetLink,
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: _ResetBackButton(onTap: () => _goBack()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResetCard extends StatelessWidget {
  const _ResetCard({
    required this.formKey,
    required this.emailCtrl,
    required this.loading,
    required this.onSendResetLink,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl;
  final bool loading;
  final VoidCallback onSendResetLink;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('reset-white-panel'),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
        boxShadow: [
          BoxShadow(
            color: MedGuardPalette.blackAlpha(0.10),
            blurRadius: 30,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(34)),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(28, 40, 28, 18),
            child: Form(
              key: formKey,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _ResetHeading(),
                    const SizedBox(height: 34),
                    _FloatingResetField(
                      controller: emailCtrl,
                      label: 'Enter email',
                      icon: Icons.mail_outline_rounded,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.done,
                      validator: validateEmail,
                    ),
                    const SizedBox(height: 24),
                    _ResetButton(
                      loading: loading,
                      onTap: loading ? null : onSendResetLink,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResetBackButton extends StatelessWidget {
  const _ResetBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TopTextNavigationAction(
      label: 'Back',
      icon: Icons.arrow_forward_ios_rounded,
      color: MedGuardPalette.pureWhite,
      fontSize: 14,
      fontWeight: FontWeight.w700,
      iconSize: 14,
      iconQuarterTurns: 2,
      onTap: onTap,
    );
  }
}

class _ResetHeading extends StatelessWidget {
  const _ResetHeading();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'Forgot password',
            style: GoogleFonts.inter(
              color: context.colors.ink,
              fontSize: 32,
              fontWeight: FontWeight.w600,
              height: 1.04,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Enter your email and MedGuard will send a secure reset link.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: context.colors.inkSoft,
            fontSize: 13.2,
            fontWeight: FontWeight.w400,
            height: 1.46,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Your account stays protected.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: context.colors.ink,
            fontSize: 13.2,
            fontWeight: FontWeight.w700,
            height: 1.46,
          ),
        ),
      ],
    );
  }
}

class _FloatingResetField extends StatelessWidget {
  const _FloatingResetField({
    required this.controller,
    required this.label,
    this.icon,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: controller,
      label: label,
      icon: icon,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      validator: validator,
    );
  }
}

class _ResetButton extends StatelessWidget {
  const _ResetButton({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppButton(label: 'Continue', loading: loading, onTap: onTap);
  }
}
