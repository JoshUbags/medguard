import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/auth_service.dart';
import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/top_text_navigation_action.dart';
import '../home/home_screen.dart';
import '../onboarding/onboarding_chrome.dart';
import 'auth_components.dart';
import 'forgot_password_screen.dart';
import 'guest_handoff.dart';
import 'register_screen.dart';
import 'social_sign_in_widgets.dart';

enum _SocialProviderKind { google, microsoft, apple }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  static const String routeName = '/login';

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _obscure = true;
  bool _rememberMe = false;
  bool _emailLoading = false;
  _SocialProviderKind? _socialLoading;

  bool get _busy => _emailLoading || _socialLoading != null;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _signInWithEmail() async {
    FocusScope.of(context).unfocus();
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _emailLoading = true);
    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      // Confirm the address is genuine: an email/password account that has
      // never confirmed its verification link can't enter the app. We resend
      // the link and sign the session back out so the gate holds.
      final user = credential.user;
      if (user != null && !user.emailVerified) {
        try {
          await user.sendEmailVerification();
        } catch (_) {
          // Best-effort resend; the message below still guides the user.
        }
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        showAuthSnackBar(
          context,
          'Please verify your email first. We just sent a new link to '
          '${_emailCtrl.text.trim()} — check your inbox, and your spam or junk '
          "folder if it's not there.",
        );
        return;
      }

      if (!mounted) return;
      // Asked BEFORE the stack is wiped: the answer decides what the home
      // screen will be showing when it appears, so it cannot be asked over
      // the top of it.
      await offerGuestRecordHandoff(context, userId: user?.uid ?? '');
      if (!mounted) return;
      showAuthSnackBar(context, 'Signed in successfully.', isError: false);
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(HomeScreen.routeName, (_) => false);
    } catch (error) {
      if (!mounted) return;
      showAuthSnackBar(context, authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _emailLoading = false);
    }
  }

  Future<void> _signInWithSocial(_SocialProviderKind kind) async {
    FocusScope.of(context).unfocus();
    if (_busy) return;

    setState(() => _socialLoading = kind);
    try {
      final credential = switch (kind) {
        _SocialProviderKind.google =>
          await AuthService.instance.signInWithGoogle(),
        _SocialProviderKind.microsoft =>
          await AuthService.instance.signInWithMicrosoft(),
        _SocialProviderKind.apple =>
          await AuthService.instance.signInWithApple(),
      };

      if (credential.additionalUserInfo?.isNewUser ?? false) {
        // First time on MedGuard with this provider: the account is now created
        // and signed in. Carry them into registration to gather their care
        // context and capture the required Terms & Privacy consent before they
        // enter the app — they stay authenticated throughout.
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                RegisterScreen(preAuthSocialMethod: _signupMethodFor(kind)),
          ),
        );
        return;
      }

      if (!mounted) return;
      await offerGuestRecordHandoff(
        context,
        userId: credential.user?.uid ?? '',
      );
      if (!mounted) return;
      showAuthSnackBar(context, 'Signed in successfully.', isError: false);
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(HomeScreen.routeName, (_) => false);
    } catch (error) {
      if (!mounted) return;
      showAuthSnackBar(context, authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _socialLoading = null);
    }
  }

  SignupMethod _signupMethodFor(_SocialProviderKind kind) {
    return switch (kind) {
      _SocialProviderKind.google => SignupMethod.google,
      _SocialProviderKind.microsoft => SignupMethod.microsoft,
      _SocialProviderKind.apple => SignupMethod.apple,
    };
  }

  void _openRegister() {
    // Push Sign Up ON TOP of Sign In: back (or the Sign In link on the
    // register screen, which pops) always returns here — no dead ends after
    // a sign-out clears the stack beneath.
    Navigator.of(context).pushNamed(RegisterScreen.routeName);
  }

  void _openForgotPassword() {
    Navigator.of(context).pushNamed(ForgotPasswordScreen.routeName);
  }

  Future<void> _goBack() async {
    // Return to the immediate previous screen via the navigation stack. When
    // login is the first route (e.g. a returning user opened straight here)
    // there is no previous screen, so back is a no-op — never a hardcoded jump.
    await Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: medGuardSystemUi(context.colors),
      child: Scaffold(
        backgroundColor: MedGuardPalette.teal,
        body: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
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
                    child: _LoginCard(
                      emailCtrl: _emailCtrl,
                      passwordCtrl: _passwordCtrl,
                      formKey: _formKey,
                      obscure: _obscure,
                      rememberMe: _rememberMe,
                      busy: _busy,
                      emailLoading: _emailLoading,
                      socialLoading: _socialLoading,
                      // After a sign-out clears the stack, Sign In is the root:
                      // there is nowhere to go back to, so no dead Back control.
                      showBack: Navigator.of(context).canPop(),
                      onBack: _goBack,
                      onTogglePassword: () =>
                          setState(() => _obscure = !_obscure),
                      onRememberChanged: (value) {
                        setState(() => _rememberMe = value);
                      },
                      onForgotPassword: _openForgotPassword,
                      onLogin: _signInWithEmail,
                      onRegister: _openRegister,
                      onSocialLogin: _signInWithSocial,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.formKey,
    required this.obscure,
    required this.rememberMe,
    required this.busy,
    required this.emailLoading,
    required this.socialLoading,
    required this.showBack,
    required this.onBack,
    required this.onTogglePassword,
    required this.onRememberChanged,
    required this.onForgotPassword,
    required this.onLogin,
    required this.onRegister,
    required this.onSocialLogin,
  });

  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final GlobalKey<FormState> formKey;
  final bool obscure;
  final bool rememberMe;
  final bool busy;
  final bool emailLoading;
  final _SocialProviderKind? socialLoading;

  /// Whether a previous screen exists to return to. False when Sign In is the
  /// stack root (e.g. right after signing out) — the Back control is hidden
  /// entirely instead of sitting there doing nothing.
  final bool showBack;
  final VoidCallback onBack;
  final VoidCallback onTogglePassword;
  final ValueChanged<bool> onRememberChanged;
  final VoidCallback onForgotPassword;
  final VoidCallback onLogin;
  final VoidCallback onRegister;
  final ValueChanged<_SocialProviderKind> onSocialLogin;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('login-white-panel'),
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
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 14),
            child: Form(
              key: formKey,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showBack) ...[
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TopTextNavigationAction(
                          label: 'Back',
                          icon: Icons.arrow_back_ios_new_rounded,
                          color: context.colors.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          iconSize: 14,
                          edgeAligned: true,
                          onTap: onBack,
                        ),
                      ),
                      const SizedBox(height: 22),
                    ] else
                      const SizedBox(height: 10),
                    const _LoginHeading(),
                    const SizedBox(height: 28),
                    _FloatingLoginField(
                      controller: emailCtrl,
                      label: 'Email address',
                      icon: Icons.mail_outline_rounded,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      validator: validateEmail,
                    ),
                    const SizedBox(height: 18),
                    _FloatingLoginField(
                      controller: passwordCtrl,
                      label: 'Password',
                      icon: Icons.lock_rounded,
                      obscure: obscure,
                      autofillHints: const [AutofillHints.password],
                      textInputAction: TextInputAction.done,
                      validator: (value) => validateRequired(value, 'Password'),
                      suffix: IconButton(
                        tooltip: obscure ? 'Show password' : 'Hide password',
                        icon: Icon(
                          obscure
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                          color: context.colors.inkMute,
                          size: 21,
                        ),
                        onPressed: onTogglePassword,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _LoginOptionsRow(
                      rememberMe: rememberMe,
                      onRememberChanged: onRememberChanged,
                      onForgotPassword: onForgotPassword,
                    ),
                    const SizedBox(height: 24),
                    _LoginButton(
                      loading: emailLoading,
                      onTap: busy ? null : onLogin,
                    ),
                    const SizedBox(height: 24),
                    const _SignInDivider(),
                    const SizedBox(height: 18),
                    _SocialLoginRow(
                      loading: socialLoading,
                      busy: busy,
                      onSocialLogin: onSocialLogin,
                    ),
                    const SizedBox(height: 24),
                    _LoginFooter(onRegister: onRegister),
                    const SizedBox(height: 6),
                    const _LocalOnlyDivider(),
                    const SizedBox(height: 6),
                    // The way past this screen when there is no network — the
                    // whole reason it can no longer be a dead end. It sits
                    // below the account options, not beside them: signing in
                    // is still the recommended path.
                    const ContinueWithoutAccountAction(
                      caption: 'Full safety checks, kept on this phone.',
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

class _LoginHeading extends StatelessWidget {
  const _LoginHeading();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'MedGuard',
          style: GoogleFonts.inter(
            color: context.colors.accent,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'Welcome Back',
          style: GoogleFonts.inter(
            color: context.colors.ink,
            fontSize: 26,
            fontWeight: FontWeight.w600,
            height: 1.05,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter your details to pick up your medication safety review.',
          style: GoogleFonts.inter(
            color: context.colors.inkSoft,
            fontSize: 13.2,
            fontWeight: FontWeight.w400,
            height: 1.46,
          ),
        ),
      ],
    );
  }
}

class _FloatingLoginField extends StatelessWidget {
  const _FloatingLoginField({
    required this.controller,
    required this.label,
    this.icon,
    this.keyboardType,
    this.obscure = false,
    this.suffix,
    this.autofillHints,
    this.textInputAction,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final IconData? icon;
  final TextInputType? keyboardType;
  final bool obscure;
  final Widget? suffix;
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
      obscure: obscure,
      suffix: suffix,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      validator: validator,
    );
  }
}

class _LoginOptionsRow extends StatelessWidget {
  const _LoginOptionsRow({
    required this.rememberMe,
    required this.onRememberChanged,
    required this.onForgotPassword,
  });

  final bool rememberMe;
  final ValueChanged<bool> onRememberChanged;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => onRememberChanged(!rememberMe),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: Checkbox(
                  value: rememberMe,
                  onChanged: (checked) => onRememberChanged(checked ?? false),
                  activeColor: MedGuardPalette.teal,
                  checkColor: MedGuardPalette.pureWhite,
                  side: BorderSide(
                    color: context.colors.accentAlpha(0.70),
                    width: 1.4,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Remember me',
                style: GoogleFonts.inter(
                  color: context.colors.accent,
                  fontSize: 13.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onForgotPassword,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            child: Text(
              'Forgot password?',
              style: GoogleFonts.inter(
                color: context.colors.accent,
                fontSize: 13.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 400) return content;
        return FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: SizedBox(width: 400, child: content),
        );
      },
    );
  }
}

class _LoginButton extends StatelessWidget {
  const _LoginButton({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppButton(label: 'Sign In', loading: loading, onTap: onTap);
  }
}

class _SignInDivider extends StatelessWidget {
  const _SignInDivider();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final label = Text(
          'Sign in with',
          style: GoogleFonts.inter(
            color: context.colors.inkMute,
            fontSize: 12.6,
            fontWeight: FontWeight.w500,
          ),
        );

        if (constraints.maxWidth < 170) return Center(child: label);

        return Row(
          children: [
            Expanded(
              child: Container(height: 1, color: context.colors.border),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: label,
            ),
            Expanded(
              child: Container(height: 1, color: context.colors.border),
            ),
          ],
        );
      },
    );
  }
}

class _SocialLoginRow extends StatelessWidget {
  const _SocialLoginRow({
    required this.loading,
    required this.busy,
    required this.onSocialLogin,
  });

  final _SocialProviderKind? loading;
  final bool busy;
  final ValueChanged<_SocialProviderKind> onSocialLogin;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 24,
      runSpacing: 14,
      children: [
        SocialCircleButton(
          key: const ValueKey('google-login'),
          semanticLabel: 'Sign in with Google',
          loading: loading == _SocialProviderKind.google,
          disabled: busy,
          onTap: () => onSocialLogin(_SocialProviderKind.google),
          child: const SocialLogoMark(
            asset: kGoogleLogoAsset,
            fallback: Icons.g_mobiledata_rounded,
            size: 30,
          ),
        ),
        SocialCircleButton(
          key: const ValueKey('microsoft-login'),
          semanticLabel: 'Sign in with Microsoft',
          loading: loading == _SocialProviderKind.microsoft,
          disabled: busy,
          onTap: () => onSocialLogin(_SocialProviderKind.microsoft),
          child: const MicrosoftMark(),
        ),
        SocialCircleButton(
          key: const ValueKey('apple-login'),
          semanticLabel: 'Sign in with Apple',
          loading: loading == _SocialProviderKind.apple,
          disabled: busy,
          onTap: () => onSocialLogin(_SocialProviderKind.apple),
          child: const SocialLogoMark(
            asset: kAppleLogoAsset,
            fallback: Icons.apple_rounded,
            size: 28,
          ),
        ),
      ],
    );
  }
}

/// A hairline between the two account options above and the no-account option
/// below. Quieter than [_SignInDivider] — it separates two kinds of answer, not
/// two ways of giving the same one.
class _LocalOnlyDivider extends StatelessWidget {
  const _LocalOnlyDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Container(height: 1, color: context.colors.border),
    );
  }
}

class _LoginFooter extends StatelessWidget {
  const _LoginFooter({required this.onRegister});

  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          "Don't have an account? ",
          style: GoogleFonts.inter(
            color: context.colors.inkSoft,
            fontSize: 12.8,
            fontWeight: FontWeight.w500,
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onRegister,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Sign Up',
              style: GoogleFonts.inter(
                color: context.colors.accent,
                fontSize: 12.8,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
