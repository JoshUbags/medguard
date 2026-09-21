import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/auth_profile_preferences.dart';
import '../../services/auth_service.dart';
import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/pressable.dart';
import '../../widgets/common/top_text_navigation_action.dart';
import '../home/home_screen.dart';
import 'auth_components.dart';
import 'guest_handoff.dart';
import 'privacy_policy_screen.dart';
import 'social_sign_in_widgets.dart';
import 'terms_conditions_screen.dart';

/// How the account is being created. Email collects credentials; the social
/// providers skip credential entry but still flow through the care-context and
/// consent steps so every account carries the same meaningful profile.
enum SignupMethod { email, google, microsoft, apple }

extension on SignupMethod {
  String get storageKey => name;

  String get displayLabel => switch (this) {
    SignupMethod.email => 'Email',
    SignupMethod.google => 'Google',
    SignupMethod.microsoft => 'Microsoft',
    SignupMethod.apple => 'Apple',
  };

  bool get isSocial => this != SignupMethod.email;
}

enum _PasswordStrength {
  weak('weak', MedGuardPalette.ruby),
  fair('fair', Color(0xFFE8751A)),
  good('good', Color(0xFF5C7CFA)),
  strong('strong', MedGuardPalette.teal);

  const _PasswordStrength(this.label, this.color);

  final String label;
  final Color color;
}

const _totalSteps = 3;

// Option labels are kept short so the choice pills sit two or three across and
// wrap naturally, rather than each long phrase taking up a whole row.
const _careTargetOptions = <String>[
  'Myself',
  'Family',
  'A patient',
  'Multiple',
];

const _medicationLoadOptions = <String>[
  '1 medicine',
  '2-5 medicines',
  '6+ medicines',
];

const _safetyFocusOptions = <String>[
  'Interactions',
  'Dose timing',
  'Allergy alerts',
  'Duplicates',
];

const _healthDetailOptions = <String>[
  'Allergies',
  'Chronic illness',
  'Pregnancy',
  'Kidney or liver',
];

const _reminderPreferenceOptions = <String>[
  'Daily',
  'Every dose',
  'Important only',
  'Check-ins',
];

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.preAuthSocialMethod});

  static const String routeName = '/register';

  /// When set, the user has *already* been authenticated with this social
  /// provider (routed here from the login screen because no MedGuard profile
  /// existed yet). Registration skips the credential step and the re-auth on
  /// submit — it only gathers the care context + consent, then enters the app.
  final SignupMethod? preAuthSocialMethod;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static final _lowerRegExp = RegExp('[a-z]');
  static final _upperRegExp = RegExp('[A-Z]');
  static final _digitRegExp = RegExp(r'\d');
  static final _symbolRegExp = RegExp(r'[^\w\s]');

  final _accountFormKey = GlobalKey<FormState>();
  final _bodyScrollController = ScrollController();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _careTargetOtherCtrl = TextEditingController();
  final _safetyFocusOtherCtrl = TextEditingController();
  final _healthDetailsOtherCtrl = TextEditingController();

  int _step = 0;
  int _furthestStep = 0;
  SignupMethod _method = SignupMethod.email;

  // Step 2 shows one care-context question at a time. [_contextQuestion] is the
  // active question index; [_contextForward] drives the slide direction so
  // moving forward enters from the right and moving back enters from the left.
  int _contextQuestion = 0;
  bool _contextForward = true;

  String? _careTarget;
  String? _medicationLoad;
  final Set<String> _safetyFocusSelections = <String>{};
  final Set<String> _healthDetailSelections = <String>{};
  String? _reminderPreference;

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _careTargetOtherActive = false;
  bool _safetyFocusOtherActive = false;
  bool _healthDetailsOtherActive = false;
  bool _acceptedTerms = false;
  bool _acceptedPrivacy = false;
  bool _submitting = false;

  bool get _hasLegalConsent => _acceptedTerms && _acceptedPrivacy;

  /// True when the user arrived already authenticated via a social provider
  /// (from the login screen). The account exists; we only collect profile.
  bool get _isPreAuthSocial => widget.preAuthSocialMethod != null;

  @override
  void initState() {
    super.initState();
    final preAuth = widget.preAuthSocialMethod;
    if (preAuth != null) {
      // The provider already created the account and signed the user in, so
      // skip the credential step and go straight to the care-context questions.
      // The name is collected there as the first question, pre-filled from the
      // provider profile when available.
      _method = preAuth;
      _step = 1;
      _furthestStep = 2;
      try {
        final providerName = FirebaseAuth.instance.currentUser?.displayName
            ?.trim();
        if (providerName != null && providerName.isNotEmpty) {
          _nameCtrl.text = providerName;
        }
      } catch (_) {
        // Firebase unavailable (tests) — the required name question collects it.
      }
    }
  }

  String get _careTargetAnswer => _careTargetOtherActive
      ? _formatCustomProfileAnswer(_careTargetOtherCtrl.text)
      : _careTarget ?? '';

  String get _safetyFocusAnswer => _selectionSummary(
    _safetyFocusOptions,
    _safetyFocusSelections,
    otherActive: _safetyFocusOtherActive,
    otherText: _safetyFocusOtherCtrl.text,
  );

  String get _healthDetailsAnswer => _selectionSummary(
    _healthDetailOptions,
    _healthDetailSelections,
    otherActive: _healthDetailsOtherActive,
    otherText: _healthDetailsOtherCtrl.text,
  );

  String get _reminderPreferenceAnswer => _reminderPreference ?? '';

  @override
  void dispose() {
    _bodyScrollController.dispose();
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _careTargetOtherCtrl.dispose();
    _safetyFocusOtherCtrl.dispose();
    _healthDetailsOtherCtrl.dispose();
    super.dispose();
  }

  String _selectionSummary(
    List<String> optionOrder,
    Set<String> selected, {
    required bool otherActive,
    required String otherText,
  }) {
    final values = <String>[
      for (final option in optionOrder)
        if (selected.contains(option)) option,
    ];
    if (otherActive) {
      final other = _formatCustomProfileAnswer(otherText);
      if (other.isNotEmpty) values.add(other);
    }
    return values.join(', ');
  }

  static String _formatCustomProfileAnswer(String raw) {
    final text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return '';
    final words = text.split(' ');
    if (words.length <= 4) {
      return words.map(_titleCaseWord).join(' ');
    }
    final sentence = text.toLowerCase();
    return sentence[0].toUpperCase() + sentence.substring(1);
  }

  static String _titleCaseWord(String word) {
    if (word.isEmpty) return word;
    final lower = word.toLowerCase();
    return lower[0].toUpperCase() + lower.substring(1);
  }

  // ── Step navigation ─────────────────────────────────────────────────────

  /// Each step opens at the top so the persistent indicator and the step's
  /// first field are always in view, regardless of where the previous step
  /// was scrolled to.
  void _resetScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_bodyScrollController.hasClients) {
        _bodyScrollController.jumpTo(0);
      }
    });
  }

  void _advanceTo(int step) {
    setState(() {
      _step = step;
      if (step > _furthestStep) _furthestStep = step;
      // Entering the care-context step always opens on the first question.
      if (step == 1) {
        _contextQuestion = 0;
        _contextForward = true;
      }
    });
    _resetScroll();
  }

  void _goToStep(int target) {
    if (target == _step) return;
    // Backward navigation is always free; forward only to a step already
    // reached (data for earlier steps persists in the controllers/state).
    if (target < _step || target <= _furthestStep) {
      setState(() => _step = target);
      _resetScroll();
    }
  }

  void _continueFromAccount() {
    FocusScope.of(context).unfocus();
    setState(() => _method = SignupMethod.email);
    if (!_accountFormKey.currentState!.validate()) return;
    _advanceTo(1);
  }

  void _selectSocial(SignupMethod method) {
    FocusScope.of(context).unfocus();
    // Social sign-up has no credentials to enter here — go straight to the
    // care-context questions, where the name is collected as the first question.
    setState(() => _method = method);
    _advanceTo(1);
  }

  void _continueFromContext() {
    FocusScope.of(context).unfocus();
    // Care context is optional EXCEPT the name (the first question for social
    // sign-ups), which is required so the account is never nameless. Block
    // leaving the step until it's filled, returning to that question.
    if (_contextHasNameQuestion && _nameCtrl.text.trim().isEmpty) {
      showAuthSnackBar(context, 'Please tell us your name to continue.');
      setState(() {
        _contextForward = false;
        _contextQuestion = 0;
      });
      _resetScroll();
      return;
    }
    _advanceTo(2);
  }

  Future<void> _goBack() async {
    // Pre-auth social users arrived already signed in from the login screen and
    // have no credential step to fall back to. Backing out of the first profile
    // step abandons the (already created) social session, so sign out and pop
    // back to whatever screen pushed us here (the login screen).
    if (_isPreAuthSocial && _step <= 1) {
      try {
        await FirebaseAuth.instance.signOut();
      } catch (_) {
        // Best effort — still return to the previous screen.
      }
      if (!mounted) return;
      await Navigator.of(context).maybePop();
      return;
    }
    // Earlier steps of this multi-step screen: step back one.
    if (_step > 0) {
      _goToStep(_step - 1);
      return;
    }
    // First step: return to the immediate previous screen via the stack; no
    // hardcoded destination.
    await Navigator.of(context).maybePop();
  }

  // ── Account creation ────────────────────────────────────────────────────

  Future<void> _createAccount() async {
    FocusScope.of(context).unfocus();
    if (!_hasLegalConsent) {
      showAuthSnackBar(
        context,
        'Please agree to the Terms & Conditions and Privacy Policy.',
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      String displayName = _nameCtrl.text.trim();
      var requiresVerification = false;
      if (_isPreAuthSocial) {
        // Already authenticated by the provider on the login screen — no
        // re-auth needed. Prefer the freshest provider name; otherwise keep the
        // name collected on the prompt step. Persist it so the home/profile
        // (which read currentUser.displayName) never fall back to "Guest".
        final providerName = FirebaseAuth.instance.currentUser?.displayName
            ?.trim();
        if (providerName != null && providerName.isNotEmpty) {
          displayName = providerName;
        }
        await AuthService.instance.persistDisplayName(displayName);
      } else if (_method == SignupMethod.email) {
        final credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(
              email: _emailCtrl.text.trim(),
              password: _passwordCtrl.text,
            );
        await credential.user?.updateDisplayName(displayName);
        // Confirm the address is genuine before granting access: send the
        // verification link now and gate entry until it's confirmed.
        try {
          await credential.user?.sendEmailVerification();
          requiresVerification = !(credential.user?.emailVerified ?? false);
        } catch (_) {
          // Non-fatal: account exists; the user can resend from the login gate.
        }
      } else {
        // In-register social sign-up: authenticate now via the native flow.
        final credential = switch (_method) {
          SignupMethod.google => await AuthService.instance.signInWithGoogle(),
          SignupMethod.microsoft =>
            await AuthService.instance.signInWithMicrosoft(),
          SignupMethod.apple => await AuthService.instance.signInWithApple(),
          SignupMethod.email => throw StateError('email is handled above'),
        };
        final providerName = credential.user?.displayName?.trim();
        if (providerName != null && providerName.isNotEmpty) {
          displayName = providerName;
        }
        await AuthService.instance.persistDisplayName(displayName);
      }

      await AuthProfilePreferences.save(
        SignupProfileContext(
          displayName: displayName,
          signUpMethod: _method.storageKey,
          accountType: _careTargetAnswer,
          careTarget: _careTargetAnswer,
          medicationLoad: _medicationLoad ?? '',
          safetyFocus: _safetyFocusAnswer,
          healthDetails: _healthDetailsAnswer,
          reminderPreference: _reminderPreferenceAnswer,
        ),
      );

      if (!mounted) return;

      if (requiresVerification) {
        // Hold the new account at the door until the email link is confirmed,
        // then send them to the login screen to come back through the gate.
        await FirebaseAuth.instance.signOut();
        if (!mounted) return;
        showAuthSnackBar(
          context,
          'Account created. Check ${_emailCtrl.text.trim()} for a verification '
          'link — look in your spam or junk folder too — then sign in.',
          isError: false,
        );
        _openLogin();
        return;
      }

      // A brand-new account is the likeliest place for a local record to be
      // waiting: trying MedGuard without an account first, then signing up, is
      // the exact path guest mode invites. Offer the hand-over before the
      // stack is wiped, so home opens showing the answer.
      await offerGuestRecordHandoff(
        context,
        userId: FirebaseAuth.instance.currentUser?.uid ?? '',
      );
      if (!mounted) return;

      showAuthSnackBar(
        context,
        'Account created successfully.',
        isError: false,
      );
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(HomeScreen.routeName, (_) => false);
    } catch (error) {
      if (!mounted) return;
      showAuthSnackBar(context, authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── Validation ──────────────────────────────────────────────────────────

  _PasswordStrength _passwordStrength(String value) {
    var score = 0;
    if (value.length >= 8) score++;
    if (value.length >= 12) score++;
    if (_lowerRegExp.hasMatch(value)) score++;
    if (_upperRegExp.hasMatch(value)) score++;
    if (_digitRegExp.hasMatch(value)) score++;
    if (_symbolRegExp.hasMatch(value)) score++;

    if (score >= 5) return _PasswordStrength.strong;
    if (score >= 4) return _PasswordStrength.good;
    if (score >= 2) return _PasswordStrength.fair;
    return _PasswordStrength.weak;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Password is required.';
    if (password.length < 8) return 'Use at least 8 characters.';
    if (_passwordStrength(password) == _PasswordStrength.weak) {
      return 'Use a stronger password.';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    final confirm = value ?? '';
    if (confirm.isEmpty) return 'Confirm your password.';
    if (confirm != _passwordCtrl.text) return 'Passwords do not match.';
    return null;
  }

  void _openTerms() {
    Navigator.of(context).pushNamed(TermsConditionsScreen.routeName);
  }

  void _openPrivacy() {
    Navigator.of(context).pushNamed(PrivacyPolicyScreen.routeName);
  }

  void _openLogin() {
    final navigator = Navigator.of(context);
    // Sign Up is always pushed ON TOP of Sign In (or of the social pre-auth
    // login), so "Sign In" simply pops back to the screen beneath — the back
    // gesture and this link behave identically and never dead-end.
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    // Register somehow started as the root (deep link / restored state):
    // swap to Sign In so the user still lands somewhere useful.
    navigator.pushReplacementNamed('/login');
  }

  // ── Build ─────────────────────────────────────────────────────────────--

  static const _stepTitles = [
    'Create Your Account',
    'Your Care Context',
    'Review & Consent',
  ];

  static const _stepDescriptions = [
    'Set up your secure MedGuard sign-in. Use a real email address — '
        "we'll send a link to confirm it's yours.",
    'Tell us a little about who you care for so we can tailor your safety '
        'checks. This step is optional — skip any question you like.',
    'Check your details and accept the terms to finish setting up your '
        'account.',
  ];

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
                child: _buildCard(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey('register-white-panel'),
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
          // Back action, step header and the form share one continuous white
          // page that scrolls together — no separate fixed band on top.
          child: SingleChildScrollView(
            controller: _bodyScrollController,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TopTextNavigationAction(
                    label: 'Back',
                    icon: Icons.arrow_forward_ios_rounded,
                    iconQuarterTurns: 2,
                    color: context.colors.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    iconSize: 14,
                    edgeAligned: true,
                    onTap: _goBack,
                  ),
                ),
                const SizedBox(height: 22),
                _StepHeader(
                  step: _step,
                  total: _totalSteps,
                  title: _stepTitles[_step],
                  description: _stepDescriptions[_step],
                  onDotTap: _goToStep,
                ),
                const SizedBox(height: 24),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 320),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  layoutBuilder: (current, previous) => Stack(
                    alignment: Alignment.topCenter,
                    children: [...previous, ?current],
                  ),
                  transitionBuilder: (child, animation) {
                    final curved = CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    );
                    return FadeTransition(
                      opacity: curved,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0.06, 0),
                          end: Offset.zero,
                        ).animate(curved),
                        child: child,
                      ),
                    );
                  },
                  child: _buildStepBody(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepBody() {
    return switch (_step) {
      0 => _buildAccountStep(),
      1 => _buildContextStep(),
      _ => _buildConsentStep(),
    };
  }

  // ── Step 1 — Account ──────────────────────────────────────────────────--

  Widget _buildAccountStep() {
    return Column(
      key: const ValueKey('register-step-account'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Form(
          key: _accountFormKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FloatingRegisterField(
                  key: const ValueKey('register-name'),
                  controller: _nameCtrl,
                  label: 'Full name',
                  icon: Icons.person_rounded,
                  keyboardType: TextInputType.name,
                  autofillHints: const [AutofillHints.name],
                  textInputAction: TextInputAction.next,
                  validator: (value) => validateRequired(value, 'Full name'),
                ),
                const SizedBox(height: 16),
                _FloatingRegisterField(
                  key: const ValueKey('register-email'),
                  controller: _emailCtrl,
                  label: 'Email address',
                  icon: Icons.mail_outline_rounded,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  validator: validateEmail,
                ),
                const SizedBox(height: 16),
                _FloatingRegisterField(
                  key: const ValueKey('register-password'),
                  controller: _passwordCtrl,
                  label: 'Password',
                  icon: Icons.lock_rounded,
                  obscure: _obscurePassword,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.next,
                  validator: _validatePassword,
                  onChanged: (_) => setState(() {}),
                  suffix: _ObscureToggle(
                    obscured: _obscurePassword,
                    onTap: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                if (_passwordCtrl.text.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _PasswordStrengthBar(
                    strength: _passwordStrength(_passwordCtrl.text),
                  ),
                ],
                const SizedBox(height: 16),
                _FloatingRegisterField(
                  key: const ValueKey('register-confirm-password'),
                  controller: _confirmPasswordCtrl,
                  label: 'Confirm password',
                  icon: Icons.lock_rounded,
                  obscure: _obscureConfirm,
                  autofillHints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  validator: _validateConfirmPassword,
                  suffix: _ObscureToggle(
                    obscured: _obscureConfirm,
                    onTap: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        _PrimaryButton(
          label: 'Continue',
          loading: false,
          onTap: _submitting ? null : _continueFromAccount,
        ),
        const SizedBox(height: 20),
        const _LabeledDivider('Or sign up with'),
        const SizedBox(height: 16),
        _SocialRow(busy: _submitting, onSelect: _selectSocial),
        const SizedBox(height: 18),
        _RegisterFooter(onOpenLogin: _openLogin),
      ],
    );
  }

  // ── Step 2 — Care context ─────────────────────────────────────────────--

  /// Social sign-ups collect the name as the first care-context question
  /// (pre-filled from the provider, required); email sign-ups already captured
  /// it on the account step, so their carousel is one question shorter.
  bool get _contextHasNameQuestion => _method.isSocial;

  /// How many care-context questions the step walks through, one at a time.
  int get _contextQuestionCount => _contextHasNameQuestion ? 6 : 5;

  /// True when the active question is the required name prompt.
  bool get _onNameQuestion => _contextHasNameQuestion && _contextQuestion == 0;

  /// Whether the question at [index] currently has an answer. Drives the
  /// per-question button label (answered → "Next", blank → "Skip").
  bool _contextAnswered(int index) {
    if (_contextHasNameQuestion) {
      if (index == 0) return _nameCtrl.text.trim().isNotEmpty;
      return _careAnswered(index - 1);
    }
    return _careAnswered(index);
  }

  bool _careAnswered(int index) {
    return switch (index) {
      0 => _careTargetAnswer.isNotEmpty,
      1 => _medicationLoad != null,
      2 => _safetyFocusAnswer.isNotEmpty,
      3 => _healthDetailsAnswer.isNotEmpty,
      _ => _reminderPreferenceAnswer.isNotEmpty,
    };
  }

  void _nextContextQuestion() {
    FocusScope.of(context).unfocus();
    // The name question is required — don't advance until it's filled.
    if (_onNameQuestion && _nameCtrl.text.trim().isEmpty) {
      showAuthSnackBar(context, 'Please tell us your name to continue.');
      return;
    }
    if (_contextQuestion < _contextQuestionCount - 1) {
      setState(() {
        _contextForward = true;
        _contextQuestion++;
      });
      _resetScroll();
    } else {
      _continueFromContext();
    }
  }

  void _previousContextQuestion() {
    FocusScope.of(context).unfocus();
    if (_contextQuestion == 0) return;
    setState(() {
      _contextForward = false;
      _contextQuestion--;
    });
    _resetScroll();
  }

  Widget _buildContextStep() {
    final isLast = _contextQuestion == _contextQuestionCount - 1;
    final answered = _contextAnswered(_contextQuestion);
    // The name question is required, so it never offers "Skip".
    final primary = _PrimaryButton(
      label: isLast
          ? 'Continue'
          : (_onNameQuestion ? 'Next' : (answered ? 'Next' : 'Skip')),
      loading: false,
      onTap: _nextContextQuestion,
    );

    return Column(
      key: const ValueKey('register-step-context'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_method.isSocial) ...[
          _MethodBanner(method: _method),
          const SizedBox(height: 18),
        ],
        _ContextProgress(
          current: _contextQuestion,
          total: _contextQuestionCount,
          // No "Skip for now" while on the required name question.
          onSkip: _onNameQuestion ? null : _continueFromContext,
        ),
        const SizedBox(height: 18),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (current, previous) => Stack(
            alignment: Alignment.topCenter,
            children: [...previous, ?current],
          ),
          transitionBuilder: (child, animation) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: Offset(_contextForward ? 0.08 : -0.08, 0),
                  end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
          child: KeyedSubtree(
            key: ValueKey('register-context-q$_contextQuestion'),
            child: _contextQuestionAt(_contextQuestion),
          ),
        ),
        const SizedBox(height: 22),
        if (_contextQuestion == 0)
          primary
        else
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Back',
                  variant: AppButtonVariant.secondary,
                  onTap: _previousContextQuestion,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: primary),
            ],
          ),
      ],
    );
  }

  Widget _contextQuestionAt(int index) {
    if (_contextHasNameQuestion) {
      if (index == 0) return _nameQuestion();
      return _careQuestionAt(index - 1);
    }
    return _careQuestionAt(index);
  }

  Widget _careQuestionAt(int index) {
    return switch (index) {
      0 => _careTargetQuestion(),
      1 => _medicationLoadQuestion(),
      2 => _safetyFocusQuestion(),
      3 => _healthDetailsQuestion(),
      _ => _reminderPreferenceQuestion(),
    };
  }

  /// The required name question shown first for social sign-ups, styled to match
  /// the care-question cards (numbered badge that flips to a check once filled)
  /// but with a text field instead of choice pills.
  Widget _nameQuestion() {
    final answered = _nameCtrl.text.trim().isNotEmpty;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 17),
      decoration: BoxDecoration(
        color: answered
            ? context.colors.accentAlpha(0.035)
            : context.colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: answered
              ? context.colors.accentAlpha(0.28)
              : MedGuardPalette.inkAlpha(0.07),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: MedGuardPalette.blackAlpha(answered ? 0.045 : 0.03),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: answered
                      ? MedGuardPalette.teal
                      : context.colors.accentAlpha(0.10),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: answered
                      ? const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: MedGuardPalette.pureWhite,
                        )
                      : Text(
                          '1',
                          style: GoogleFonts.inter(
                            color: context.colors.accent,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'What should we call you?',
                      style: GoogleFonts.inter(
                        color: context.colors.ink,
                        fontSize: 14.6,
                        fontWeight: FontWeight.w700,
                        height: 1.22,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Add the name MedGuard should greet you by. '
                      "We'll use this throughout the app.",
                      style: GoogleFonts.inter(
                        color: context.colors.inkMute,
                        fontSize: 12.2,
                        fontWeight: FontWeight.w400,
                        height: 1.38,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          _FloatingRegisterField(
            key: const ValueKey('register-social-name'),
            controller: _nameCtrl,
            label: 'Full name',
            keyboardType: TextInputType.name,
            autofillHints: const [AutofillHints.name],
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
    );
  }

  Widget _careTargetQuestion() {
    return _CareQuestionCard(
      index: 1,
      title: 'Who are you caring for?',
      description:
          'Choose the closest match so MedGuard can label your profile.',
      selectionLabel: 'Choose one',
      options: _careTargetOptions,
      selectedOptions: {
        if (!_careTargetOtherActive && _careTarget != null) _careTarget!,
      },
      onOptionTap: (value) => setState(() {
        if (!_careTargetOtherActive && _careTarget == value) {
          _careTarget = null;
          return;
        }
        _careTarget = value;
        _careTargetOtherActive = false;
        _careTargetOtherCtrl.clear();
      }),
      otherButtonKey: const ValueKey('care-question-care-target-other-button'),
      otherFieldKey: const ValueKey('care-question-care-target-other-field'),
      otherSelected: _careTargetOtherActive,
      otherFieldLabel: 'Describe who you care for',
      otherController: _careTargetOtherCtrl,
      onOtherTap: () => setState(() {
        _careTargetOtherActive = !_careTargetOtherActive;
        _careTarget = null;
        if (!_careTargetOtherActive) _careTargetOtherCtrl.clear();
      }),
      onOtherChanged: (_) => setState(() {}),
    );
  }

  Widget _medicationLoadQuestion() {
    return _CareQuestionCard(
      index: 2,
      title: 'How many medicines do you track?',
      description:
          'A rough range helps tune reminders and safety check density.',
      selectionLabel: 'Choose one',
      options: _medicationLoadOptions,
      selectedOptions: {?_medicationLoad},
      onOptionTap: (value) => setState(() {
        if (_medicationLoad == value) {
          _medicationLoad = null;
          return;
        }
        _medicationLoad = value;
      }),
    );
  }

  Widget _safetyFocusQuestion() {
    return _CareQuestionCard(
      index: 3,
      title: 'What matters most to you?',
      description: 'Select every safety area you want MedGuard to prioritize.',
      selectionLabel: 'Select any',
      options: _safetyFocusOptions,
      selectedOptions: _safetyFocusSelections,
      onOptionTap: (value) => setState(() {
        if (!_safetyFocusSelections.add(value)) {
          _safetyFocusSelections.remove(value);
        }
      }),
      otherButtonKey: const ValueKey('care-question-safety-focus-other-button'),
      otherFieldKey: const ValueKey('care-question-safety-focus-other-field'),
      otherSelected: _safetyFocusOtherActive,
      otherFieldLabel: 'Add another safety focus',
      otherController: _safetyFocusOtherCtrl,
      onOtherTap: () => setState(() {
        _safetyFocusOtherActive = !_safetyFocusOtherActive;
        if (!_safetyFocusOtherActive) _safetyFocusOtherCtrl.clear();
      }),
      onOtherChanged: (_) => setState(() {}),
    );
  }

  Widget _healthDetailsQuestion() {
    return _CareQuestionCard(
      index: 4,
      title: 'Which health details should MedGuard consider?',
      description:
          'Add health factors that can change how medicine guidance is framed.',
      selectionLabel: 'Select any',
      options: _healthDetailOptions,
      selectedOptions: _healthDetailSelections,
      onOptionTap: (value) => setState(() {
        if (!_healthDetailSelections.add(value)) {
          _healthDetailSelections.remove(value);
        }
      }),
      otherButtonKey: const ValueKey(
        'care-question-health-details-other-button',
      ),
      otherFieldKey: const ValueKey('care-question-health-details-other-field'),
      otherSelected: _healthDetailsOtherActive,
      otherFieldLabel: 'Add another health detail',
      otherController: _healthDetailsOtherCtrl,
      onOtherTap: () => setState(() {
        _healthDetailsOtherActive = !_healthDetailsOtherActive;
        if (!_healthDetailsOtherActive) _healthDetailsOtherCtrl.clear();
      }),
      onOtherChanged: (_) => setState(() {}),
    );
  }

  Widget _reminderPreferenceQuestion() {
    return _CareQuestionCard(
      index: 5,
      title: 'How do you prefer medication reminders?',
      description:
          'Choose how assertive medication nudges should feel day to day.',
      selectionLabel: 'Choose one',
      options: _reminderPreferenceOptions,
      selectedOptions: {?_reminderPreference},
      onOptionTap: (value) => setState(() {
        if (_reminderPreference == value) {
          _reminderPreference = null;
          return;
        }
        _reminderPreference = value;
      }),
    );
  }

  // ── Step 3 — Review & consent ─────────────────────────────────────────--

  Widget _buildConsentStep() {
    return Column(
      key: const ValueKey('register-step-consent'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _ReviewLabel('Your details'),
        const SizedBox(height: 12),
        _SummaryCard(
          method: _method,
          name: _nameCtrl.text.trim(),
          careTarget: _careTargetAnswer,
          medicationLoad: _medicationLoad ?? '',
          safetyFocus: _safetyFocusAnswer,
          healthDetails: _healthDetailsAnswer,
          reminderPreference: _reminderPreferenceAnswer,
        ),
        if (_method == SignupMethod.email && _passwordCtrl.text.isNotEmpty) ...[
          const SizedBox(height: 18),
          _PasswordStrengthBar(
            strength: _passwordStrength(_passwordCtrl.text),
            showLabel: true,
          ),
        ],
        const SizedBox(height: 30),
        const _ReviewLabel('Agreements'),
        const SizedBox(height: 12),
        // Consent sits directly on the white page — no surrounding box.
        _ConsentRow(
          value: _acceptedTerms,
          onChanged: _submitting
              ? null
              : (value) => setState(() => _acceptedTerms = value),
          beforeLink: 'I have read and agree to the ',
          linkText: 'Terms & Conditions',
          afterLink: '.',
          onLinkTap: _openTerms,
        ),
        const SizedBox(height: 10),
        _ConsentRow(
          value: _acceptedPrivacy,
          onChanged: _submitting
              ? null
              : (value) => setState(() => _acceptedPrivacy = value),
          beforeLink: 'I have read and agree to the ',
          linkText: 'Privacy Policy',
          afterLink: '.',
          onLinkTap: _openPrivacy,
        ),
        if (_method == SignupMethod.email) ...[
          const SizedBox(height: 18),
          const _VerifyEmailNote(),
        ],
        const SizedBox(height: 28),
        _PrimaryButton(
          label: 'Create Account',
          loading: _submitting,
          onTap: _submitting ? null : _createAccount,
        ),
        const SizedBox(height: 16),
        _RegisterFooter(onOpenLogin: _openLogin),
      ],
    );
  }
}

/// Small uppercase section label used to separate the review groups on step 3
/// with clear whitespace instead of heavy boxes.
class _ReviewLabel extends StatelessWidget {
  const _ReviewLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: GoogleFonts.inter(
        color: context.colors.inkMute,
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

// ── Shared step chrome ───────────────────────────────────────────────────--

class _StepHeader extends StatelessWidget {
  const _StepHeader({
    required this.step,
    required this.total,
    required this.title,
    required this.description,
    required this.onDotTap,
  });

  final int step;
  final int total;
  final String title;
  final String description;
  final ValueChanged<int> onDotTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepDots(current: step, total: total, onTap: onDotTap),
        const SizedBox(height: 16),
        Text(
          'Step ${step + 1} of $total',
          style: GoogleFonts.inter(
            color: context.colors.accent,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          title,
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
          description,
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

class _StepDots extends StatelessWidget {
  const _StepDots({
    required this.current,
    required this.total,
    required this.onTap,
  });

  final int current;
  final int total;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('register-step-dots'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++)
          Padding(
            padding: EdgeInsets.only(right: i == total - 1 ? 0 : 8),
            child: Pressable(
              key: ValueKey('register-step-dot-$i'),
              pressScale: 0.86,
              onTap: () => onTap(i),
              child: Semantics(
                button: true,
                selected: i == current,
                label: 'Step ${i + 1}',
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  height: 8,
                  width: i == current ? 26 : (i < current ? 14 : 8),
                  decoration: BoxDecoration(
                    color: i <= current
                        ? MedGuardPalette.teal
                        : context.colors.accentAlpha(0.20),
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The slim progress header above the step-2 question carousel: a "Question N
/// of M" counter, a determinate bar, and a "Skip for now" action that bails the
/// whole (optional) care-context step straight to review.
class _ContextProgress extends StatelessWidget {
  const _ContextProgress({
    required this.current,
    required this.total,
    required this.onSkip,
  });

  final int current;
  final int total;

  /// When null, the "Skip for now" affordance is hidden — used while the
  /// required name question is showing.
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final onSkip = this.onSkip;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Question ${current + 1} of $total',
              style: GoogleFonts.inter(
                color: context.colors.accent,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            const Spacer(),
            if (onSkip != null)
              Pressable(
                onTap: onSkip,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Skip for now',
                        style: GoogleFonts.inter(
                          color: context.colors.inkMute,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 14,
                        color: context.colors.inkMute,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: LinearProgressIndicator(
            minHeight: 5,
            value: (current + 1) / total,
            backgroundColor: context.colors.accentAlpha(0.12),
            valueColor: const AlwaysStoppedAnimation(MedGuardPalette.teal),
          ),
        ),
      ],
    );
  }
}

// ── Care-context selection ───────────────────────────────────────────────--

/// A single care-context question presented as an elevated card. The leading
/// badge counts up while unanswered and flips to a teal check once a choice is
/// made, and the card's border/shadow warms on completion — giving the
/// optional step a calm, progressive, premium feel.
/// A single care-profile setup question with optional single-select,
/// multi-select, and typed "Other" answers.
class _CareQuestionCard extends StatelessWidget {
  const _CareQuestionCard({
    required this.index,
    required this.title,
    required this.description,
    required this.selectionLabel,
    required this.options,
    required this.selectedOptions,
    required this.onOptionTap,
    this.otherButtonKey,
    this.otherFieldKey,
    this.otherSelected = false,
    this.otherFieldLabel,
    this.otherController,
    this.onOtherTap,
    this.onOtherChanged,
  });

  final int index;
  final String title;
  final String description;
  final String selectionLabel;
  final List<String> options;
  final Set<String> selectedOptions;
  final ValueChanged<String> onOptionTap;
  final Key? otherButtonKey;
  final Key? otherFieldKey;
  final bool otherSelected;
  final String? otherFieldLabel;
  final TextEditingController? otherController;
  final VoidCallback? onOtherTap;
  final ValueChanged<String>? onOtherChanged;

  @override
  Widget build(BuildContext context) {
    final hasOther = otherController != null && onOtherTap != null;
    final answered = selectedOptions.isNotEmpty || otherSelected;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 17),
      decoration: BoxDecoration(
        color: answered
            ? context.colors.accentAlpha(0.035)
            : context.colors.surface,
        borderRadius: BorderRadius.circular(18),
        // Constant border width — only the colour responds to the answered
        // state, so the card never resizes its content when answers change.
        border: Border.all(
          color: answered
              ? context.colors.accentAlpha(0.28)
              : MedGuardPalette.inkAlpha(0.07),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: MedGuardPalette.blackAlpha(answered ? 0.045 : 0.03),
            blurRadius: 18,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: answered
                      ? MedGuardPalette.teal
                      : context.colors.accentAlpha(0.10),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: answered
                      ? const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: MedGuardPalette.pureWhite,
                        )
                      : Text(
                          '$index',
                          style: GoogleFonts.inter(
                            color: context.colors.accent,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.inter(
                        color: context.colors.ink,
                        fontSize: 14.6,
                        fontWeight: FontWeight.w700,
                        height: 1.22,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      description,
                      style: GoogleFonts.inter(
                        color: context.colors.inkMute,
                        fontSize: 12.2,
                        fontWeight: FontWeight.w400,
                        height: 1.38,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _SelectionModeLabel(selectionLabel),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options)
                _CareChoicePill(
                  label: option,
                  selected: selectedOptions.contains(option),
                  onTap: () => onOptionTap(option),
                ),
              if (hasOther)
                _CareChoicePill(
                  key: otherButtonKey,
                  label: 'Other',
                  selected: otherSelected,
                  onTap: onOtherTap!,
                ),
            ],
          ),
          if (hasOther && otherSelected) ...[
            const SizedBox(height: 13),
            TextFormField(
              key: otherFieldKey,
              controller: otherController,
              minLines: 1,
              maxLines: 3,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onChanged: onOtherChanged,
              cursorColor: MedGuardPalette.teal,
              style: GoogleFonts.inter(
                color: context.colors.ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
              decoration: InputDecoration(
                labelText: otherFieldLabel ?? 'Add your answer',
                labelStyle: GoogleFonts.inter(
                  color: context.colors.inkMute,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
                floatingLabelStyle: GoogleFonts.inter(
                  color: context.colors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                prefixIcon: Icon(
                  Icons.edit_note_rounded,
                  color: context.colors.accent,
                  size: 20,
                ),
                filled: true,
                fillColor: context.colors.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: MedGuardPalette.inkAlpha(0.11),
                    width: 1.1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: context.colors.accent,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectionModeLabel extends StatelessWidget {
  const _SelectionModeLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.accentAlpha(0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        child: Text(
          label,
          style: GoogleFonts.inter(
            color: context.colors.accent,
            fontSize: 10.8,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class _CareChoicePill extends StatelessWidget {
  const _CareChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Selection is conveyed by colour only. The pill's geometry — padding,
    // border width, font weight, contents — is identical in both states so
    // toggling an option never resizes the pill or reflows the Wrap.
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: Pressable(
        onTap: onTap,
        pressScale: 0.96,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? MedGuardPalette.teal : context.colors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? MedGuardPalette.teal
                  : MedGuardPalette.inkAlpha(0.12),
              width: 1.2,
            ),
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            style: GoogleFonts.inter(
              color: selected
                  ? MedGuardPalette.pureWhite
                  : context.colors.inkSoft,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

/// Renders the sign-up provider's brand mark at [size]. Email (the non-social
/// path) falls back to a mail glyph. Used in the "selected" banner and the
/// review summary so the provider is shown by its logo, not a generic icon.
class _MethodLogo extends StatelessWidget {
  const _MethodLogo({required this.method, required this.size});

  final SignupMethod method;
  final double size;

  @override
  Widget build(BuildContext context) {
    switch (method) {
      case SignupMethod.google:
        return SocialLogoMark(
          asset: kGoogleLogoAsset,
          fallback: Icons.g_mobiledata_rounded,
          size: size,
        );
      case SignupMethod.apple:
        return SocialLogoMark(
          asset: kAppleLogoAsset,
          fallback: Icons.apple_rounded,
          size: size,
        );
      case SignupMethod.microsoft:
        return SizedBox(
          width: size,
          height: size,
          child: const FittedBox(fit: BoxFit.contain, child: MicrosoftMark()),
        );
      case SignupMethod.email:
        return Icon(
          Icons.alternate_email_rounded,
          size: size,
          color: context.colors.accent,
        );
    }
  }
}

class _MethodBanner extends StatelessWidget {
  const _MethodBanner({required this.method});

  final SignupMethod method;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.colors.accentAlpha(0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.accentAlpha(0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: MedGuardPalette.inkAlpha(0.06)),
            ),
            child: Center(child: _MethodLogo(method: method, size: 20)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Connected with ${method.displayLabel}',
                  style: GoogleFonts.inter(
                    color: context.colors.ink,
                    fontSize: 13.4,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Finish the steps below to create your account.',
                  style: GoogleFonts.inter(
                    color: context.colors.inkMute,
                    fontSize: 11.8,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.check_circle_rounded,
            color: context.colors.accent,
            size: 20,
          ),
        ],
      ),
    );
  }
}

// ── Review summary ───────────────────────────────────────────────────────--

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.method,
    required this.name,
    required this.careTarget,
    required this.medicationLoad,
    required this.safetyFocus,
    required this.healthDetails,
    required this.reminderPreference,
  });

  final SignupMethod method;
  final String name;
  final String careTarget;
  final String medicationLoad;
  final String safetyFocus;
  final String healthDetails;
  final String reminderPreference;

  @override
  Widget build(BuildContext context) {
    final rows = <_SummaryRowData>[
      _SummaryRowData(
        'Signing up with',
        method.displayLabel,
        valueLeading: _MethodLogo(method: method, size: 15),
      ),
      if (name.isNotEmpty) _SummaryRowData('Full name', name),
      if (careTarget.isNotEmpty) _SummaryRowData('Caring for', careTarget),
      if (medicationLoad.isNotEmpty)
        _SummaryRowData('Medicines tracked', medicationLoad),
      if (safetyFocus.isNotEmpty) _SummaryRowData('Focus', safetyFocus),
      if (healthDetails.isNotEmpty)
        _SummaryRowData('Health details', healthDetails),
      if (reminderPreference.isNotEmpty)
        _SummaryRowData('Reminder style', reminderPreference),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MedGuardPalette.inkAlpha(0.08)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i != 0)
              Divider(
                height: 1,
                thickness: 1,
                color: MedGuardPalette.inkAlpha(0.05),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: _SummaryRow(data: rows[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _SummaryRowData {
  const _SummaryRowData(this.label, this.value, {this.valueLeading});

  final String label;
  final String value;

  /// Optional mark shown immediately before the value (e.g. a provider logo).
  final Widget? valueLeading;
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.data});

  final _SummaryRowData data;

  @override
  Widget build(BuildContext context) {
    // The label keeps a fixed column so the value gets the rest of the width
    // and can wrap onto as many lines as it needs — full answers are always
    // shown in the review, never truncated with an ellipsis.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 116,
          child: Text(
            data.label,
            style: GoogleFonts.inter(
              color: context.colors.inkMute,
              fontSize: 13,
              fontWeight: FontWeight.w400,
              height: 1.35,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (data.valueLeading != null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 1.5),
                  child: data.valueLeading!,
                ),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(
                  data.value,
                  textAlign: TextAlign.right,
                  style: GoogleFonts.inter(
                    color: context.colors.ink,
                    fontSize: 13.4,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Reusable form pieces ─────────────────────────────────────────────────--

class _ObscureToggle extends StatelessWidget {
  const _ObscureToggle({required this.obscured, required this.onTap});

  final bool obscured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: obscured ? 'Show password' : 'Hide password',
      icon: Icon(
        obscured ? Icons.visibility_rounded : Icons.visibility_off_rounded,
        color: context.colors.inkMute,
        size: 21,
      ),
      onPressed: onTap,
    );
  }
}

class _FloatingRegisterField extends StatelessWidget {
  const _FloatingRegisterField({
    super.key,
    required this.controller,
    required this.label,
    this.icon,
    this.keyboardType,
    this.obscure = false,
    this.suffix,
    this.autofillHints,
    this.textInputAction,
    this.validator,
    this.onChanged,
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
  final ValueChanged<String>? onChanged;

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
      onChanged: onChanged,
    );
  }
}

class _PasswordStrengthBar extends StatelessWidget {
  const _PasswordStrengthBar({required this.strength, this.showLabel = false});

  final _PasswordStrength strength;
  final bool showLabel;

  double get _value {
    return switch (strength) {
      _PasswordStrength.weak => 0.25,
      _PasswordStrength.fair => 0.50,
      _PasswordStrength.good => 0.75,
      _PasswordStrength.strong => 1.00,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: LinearProgressIndicator(
            minHeight: 5,
            value: _value,
            backgroundColor: context.colors.accentAlpha(0.12),
            valueColor: AlwaysStoppedAnimation(strength.color),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Password strength: ${strength.label}',
          style: GoogleFonts.inter(
            color: showLabel ? strength.color : context.colors.inkSoft,
            fontSize: 12.4,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ConsentRow extends StatelessWidget {
  const _ConsentRow({
    required this.value,
    required this.onChanged,
    required this.beforeLink,
    required this.linkText,
    required this.afterLink,
    required this.onLinkTap,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String beforeLink;
  final String linkText;
  final String afterLink;
  final VoidCallback onLinkTap;

  @override
  Widget build(BuildContext context) {
    final textStyle = GoogleFonts.inter(
      color: context.colors.inkSoft,
      fontSize: 12.8,
      fontWeight: FontWeight.w400,
      height: 1.35,
    );
    final linkStyle = GoogleFonts.inter(
      color: context.colors.accent,
      fontSize: 12.8,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: context.colors.accent,
      height: 1.35,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 34,
          height: 34,
          child: Checkbox(
            value: value,
            onChanged: onChanged == null
                ? null
                : (checked) => onChanged!(checked ?? false),
            activeColor: MedGuardPalette.teal,
            checkColor: MedGuardPalette.pureWhite,
            side: BorderSide(
              color: context.colors.accentAlpha(0.42),
              width: 1.4,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Wrap(
              children: [
                Text(beforeLink, style: textStyle),
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: onLinkTap,
                  child: Text(linkText, style: linkStyle),
                ),
                Text(afterLink, style: textStyle),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Reassures the user what happens right after they tap "Create Account":
/// a confirmation link is sent and the address must be verified to sign in.
class _VerifyEmailNote extends StatelessWidget {
  const _VerifyEmailNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.mark_email_read_rounded,
          size: 17,
          color: context.colors.accent,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            "We'll email you a confirmation link. If it's not in your inbox, "
            'check your spam or junk folder. Verify it, then sign in to start '
            'using MedGuard.',
            style: GoogleFonts.inter(
              color: context.colors.inkSoft,
              fontSize: 12.4,
              fontWeight: FontWeight.w400,
              height: 1.42,
            ),
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.loading,
    required this.onTap,
  });

  final String label;
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AppButton(label: label, loading: loading, onTap: onTap);
  }
}

class _LabeledDivider extends StatelessWidget {
  const _LabeledDivider(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: context.colors.border)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: GoogleFonts.inter(
              color: context.colors.inkMute,
              fontSize: 12.6,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Expanded(child: Container(height: 1, color: context.colors.border)),
      ],
    );
  }
}

class _SocialRow extends StatelessWidget {
  const _SocialRow({required this.busy, required this.onSelect});

  final bool busy;
  final ValueChanged<SignupMethod> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 24,
      runSpacing: 14,
      children: [
        SocialCircleButton(
          key: const ValueKey('google-register'),
          semanticLabel: 'Continue with Google',
          disabled: busy,
          onTap: () => onSelect(SignupMethod.google),
          child: const SocialLogoMark(
            asset: kGoogleLogoAsset,
            fallback: Icons.g_mobiledata_rounded,
            size: 30,
          ),
        ),
        SocialCircleButton(
          key: const ValueKey('microsoft-register'),
          semanticLabel: 'Continue with Microsoft',
          disabled: busy,
          onTap: () => onSelect(SignupMethod.microsoft),
          child: const MicrosoftMark(),
        ),
        SocialCircleButton(
          key: const ValueKey('apple-register'),
          semanticLabel: 'Continue with Apple',
          disabled: busy,
          onTap: () => onSelect(SignupMethod.apple),
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

class _RegisterFooter extends StatelessWidget {
  const _RegisterFooter({required this.onOpenLogin});

  final VoidCallback onOpenLogin;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Already have an account? ',
          style: GoogleFonts.inter(
            color: context.colors.inkSoft,
            fontSize: 12.8,
            fontWeight: FontWeight.w500,
          ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onOpenLogin,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Sign In',
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
