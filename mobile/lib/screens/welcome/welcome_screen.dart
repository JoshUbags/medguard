import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';
import '../../widgets/common/continue_button.dart';
import '../onboarding/interaction_review_screen.dart';
import '../onboarding/onboarding_chrome.dart';
import 'welcome_assets.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  static const String routeName = '/welcome';

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _fade = CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  /// Opens the onboarding flow. A plain push, so Back from onboarding step 1
  /// always returns here with the screen exactly as the user left it.
  void _onContinue() {
    Navigator.of(
      context,
    ).push(onboardingSlideRoute(const InteractionReviewScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: medGuardSystemUi(context.colors),
      child: Scaffold(
        backgroundColor: context.colors.scaffold,
        body: Stack(
          fit: StackFit.expand,
          children: [
            const _RichWelcomeImage(),
            const Positioned.fill(child: _WelcomeMask()),
            SafeArea(
              child: Column(
                children: [
                  // Hero copy sits in the lower third, exactly like the
                  // onboarding screens — title, then a one-line subhead.
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                        child: FadeTransition(
                          opacity: _fade,
                          child: SlideTransition(
                            position: _slide,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const OnboardingTag(
                                  icon: Icons.medical_information_rounded,
                                  label: 'Clinical Support',
                                ),
                                const SizedBox(height: 18),
                                Text.rich(
                                  textAlign: TextAlign.center,
                                  TextSpan(
                                    style: GoogleFonts.inter(
                                      color: context.colors.ink,
                                      fontSize: 32,
                                      fontWeight: FontWeight.w600,
                                      height: 1.02,
                                      letterSpacing: -0.4,
                                    ),
                                    children: [
                                      const TextSpan(text: 'Welcome to '),
                                      TextSpan(
                                        text: 'MedGuard',
                                        style: TextStyle(
                                          color: context.colors.accent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 13),
                                Text(
                                  'Medication safety, made clear and confident.',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    color: context.colors.inkSoft,
                                    fontSize: 13.2,
                                    height: 1.46,
                                    fontWeight: FontWeight.w400,
                                    letterSpacing: 0.1,
                                  ),
                                ),
                                const SizedBox(height: 26),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // ── Tap to continue — the flagship CTA. Shares the app-wide
                  // primary button height (the auth Sign In button), with the
                  // white arrow disc pinned to its right end.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 10, 24, 26),
                    child: FadeTransition(
                      opacity: _fade,
                      child: ContinueButton(onPressed: _onContinue),
                    ),
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

class _RichWelcomeImage extends StatelessWidget {
  const _RichWelcomeImage();

  @override
  Widget build(BuildContext context) {
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix([
        1.14,
        0,
        0,
        0,
        -8,
        0,
        1.14,
        0,
        0,
        -8,
        0,
        0,
        1.14,
        0,
        -8,
        0,
        0,
        0,
        1,
        0,
      ]),
      child: Image.asset(
        kWelcomeHeroAsset,
        fit: BoxFit.cover,
        alignment: Alignment.center,
        cacheWidth: kWelcomeHeroCacheWidth,
        filterQuality: FilterQuality.medium,
        errorBuilder: (ctx, e, st) => const _WelcomeFallback(),
      ),
    );
  }
}

class _WelcomeMask extends StatelessWidget {
  const _WelcomeMask();

  @override
  Widget build(BuildContext context) {
    // The hero fades into the page beneath it — white in light, the dark canvas
    // in dark, so the bottom of the baked hero doesn't end in a bright band.
    final base = context.colors.isDark
        ? context.colors.scaffold
        : MedGuardPalette.pureWhite;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            MedGuardPalette.blackAlpha(0.20),
            base.withValues(alpha: 0.00),
            base.withValues(alpha: 0.42),
            base.withValues(alpha: 0.86),
            base.withValues(alpha: 0.98),
            base.withValues(alpha: 1.00),
          ],
          stops: const [0.0, 0.22, 0.40, 0.56, 0.72, 1.0],
        ),
      ),
    );
  }
}

class _WelcomeFallback extends StatelessWidget {
  const _WelcomeFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(color: MedGuardPalette.teal);
  }
}
