import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/guest_mode_service.dart';
import '../../services/onboarding_preferences.dart';
import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';
import '../../theme/medguard_responsive.dart';
import '../../theme/medguard_spacing.dart';
import '../../widgets/common/pressable.dart';
import '../../widgets/common/top_text_navigation_action.dart';
import '../auth/login_screen.dart';
import '../main_shell.dart';

const int kOnboardingPageCount = 3;

// Snappy enough that navigation feels immediate (input is blocked during a
// route transition, so long slides read as unresponsive buttons).
Route<T> onboardingSlideRoute<T>(Widget page) => PageRouteBuilder<T>(
  transitionDuration: const Duration(milliseconds: 360),
  reverseTransitionDuration: const Duration(milliseconds: 280),
  pageBuilder: (context, animation, secondaryAnimation) => page,
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    final incoming = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
    );
    final outgoing = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
    );

    return SlideTransition(
      position: Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-0.18, 0),
      ).animate(outgoing),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(incoming),
        child: child,
      ),
    );
  },
);

Future<void> completeOnboardingAndGoToSignIn(BuildContext context) async {
  await markOnboardingComplete();
  if (!context.mounted) return;
  // Onboarding lands on Sign In (returning users are the common case; Sign In
  // links to Sign Up for new accounts, and offers the local-only route for
  // anyone who wants neither). Push — don't wipe the stack — so Back on the
  // sign-in screen returns to the onboarding screen the user came from. The
  // completion flag is persisted above, so a future launch still skips
  // straight past onboarding.
  Navigator.of(context).push(onboardingSlideRoute(const LoginScreen()));
}

/// Enters the app with no account at all.
///
/// The safety engine — the rule database, the interaction checks, the on-device
/// predictor — is entirely local, so there is nothing here for an account to
/// unlock and nothing for the network to be needed for. The stack is wiped
/// because this is an arrival, not a detour: Back from Home must exit the app,
/// not walk the user back through onboarding into the wall they just declined.
Future<void> continueWithoutAccount(BuildContext context) async {
  await markOnboardingComplete();
  await GuestModeService.instance.enter();
  if (!context.mounted) return;
  Navigator.of(
    context,
  ).pushNamedAndRemoveUntil(MainShell.routeName, (_) => false);
}

/// The shared "skip the account" action.
///
/// One component, one wording, one weight, wherever the choice is offered — the
/// end of onboarding and the sign-in screen. Deliberately quiet text rather
/// than a second button: signing in is still the recommended path, this is the
/// door beside it, not a competing call to action.
class ContinueWithoutAccountAction extends StatelessWidget {
  const ContinueWithoutAccountAction({
    super.key,
    this.label = 'Continue without an account',
    this.caption,
    this.color,
  });

  final String label;

  /// One line under the link explaining what the choice costs, so it is never
  /// taken blind.
  final String? caption;

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final tint = color ?? context.colors.accent;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Pressable(
          onTap: () => continueWithoutAccount(context),
          pressScale: 0.97,
          semanticLabel: 'Continue without an account',
          child: Container(
            constraints: const BoxConstraints(minHeight: 44),
            padding: EdgeInsets.symmetric(horizontal: responsive.s(10)),
            alignment: Alignment.center,
            color: Colors.transparent,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.phone_iphone_rounded,
                  color: tint,
                  size: responsive.icon(15),
                ),
                SizedBox(width: responsive.s(7)),
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: tint,
                      fontSize: responsive.font(13.2),
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (caption != null)
          Padding(
            padding: EdgeInsets.only(top: responsive.s(2)),
            child: Text(
              caption!,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: context.colors.inkMute,
                fontSize: responsive.font(11.6),
                fontWeight: FontWeight.w400,
                height: 1.4,
              ),
            ),
          ),
      ],
    );
  }
}

class OnboardingSkipAction extends StatelessWidget {
  const OnboardingSkipAction({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final actionColor = color ?? context.colors.ink;

    return Padding(
      // 24px gutters match the hero copy and footer; the top inset is the
      // app-wide universal screen top gap, so onboarding starts at exactly
      // the same height as home and every other screen.
      padding: EdgeInsets.fromLTRB(
        24,
        MedGuardSpacing.screenTop(responsive),
        24,
        0,
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: TopTextNavigationAction(
          label: 'Skip',
          icon: Icons.chevron_right_rounded,
          iconAfterLabel: true,
          color: actionColor,
          fontSize: 13.2,
          fontWeight: FontWeight.w600,
          iconSize: 15,
          semanticLabel: 'Skip onboarding',
          onTap: () => completeOnboardingAndGoToSignIn(context),
        ),
      ),
    );
  }
}

class OnboardingFooter extends StatelessWidget {
  const OnboardingFooter({
    super.key,
    required this.activeIndex,
    required this.onNext,
    this.onBack,
    this.nextLabel = 'Next',
  });

  final int activeIndex;
  final VoidCallback? onBack;
  final VoidCallback onNext;
  final String nextLabel;

  void _handleBack() {
    HapticFeedback.selectionClick();
    onBack?.call();
  }

  void _handleNext() {
    HapticFeedback.selectionClick();
    onNext();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 24, 22),
      // Back (left), progress dots (centred), and the compact Next pill
      // (right) on a single quiet row. Both controls give immediate haptic +
      // press feedback and carry full 44pt touch targets, so a tap always
      // registers and always FEELS registered.
      child: Row(
        children: [
          // Matched to the Next slot's width so the progress dots stay on the
          // exact centre line of the footer regardless of which side is filled.
          SizedBox(
            width: 104,
            child: onBack == null
                ? const SizedBox.shrink()
                : Align(
                    alignment: Alignment.centerLeft,
                    child: Pressable(
                      onTap: _handleBack,
                      pressScale: 0.94,
                      semanticLabel: 'Back to previous step',
                      child: Container(
                        constraints: const BoxConstraints(
                          minHeight: 44,
                          minWidth: 64,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.centerLeft,
                        color: Colors.transparent,
                        child: Text(
                          'Back',
                          style: GoogleFonts.inter(
                            color: context.colors.inkSoft,
                            fontSize: 13.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          Expanded(
            child: Center(child: _OnboardingPageDots(activeIndex: activeIndex)),
          ),
          SizedBox(
            width: 104,
            child: Align(
              alignment: Alignment.centerRight,
              child: Pressable(
                onTap: _handleNext,
                pressScale: 0.94,
                semanticLabel: '$nextLabel step',
                // The pill hugs its label rather than filling the footer slot —
                // no `alignment` on the Container, which was what stranded
                // "Next" in a sea of teal. The side inset is comfortable, not
                // generous: enough that the label has room to breathe on both
                // sides, short of the pill reading as a full-width button. The
                // 44pt touch target is preserved by the transparent box around
                // the pill, so the tap area never shrinks with it.
                child: Container(
                  constraints: const BoxConstraints(minHeight: 44),
                  color: Colors.transparent,
                  child: Center(
                    widthFactor: 1,
                    child: DecoratedBox(
                      // Flat solid-teal fill, matching the shared primary
                      // button — the deep brand teal in both themes so the
                      // white label keeps ~7:1 contrast.
                      decoration: const ShapeDecoration(
                        color: MedGuardPalette.teal,
                        shape: StadiumBorder(),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 9.5,
                        ),
                        child: Text(
                          nextLabel,
                          maxLines: 1,
                          style: GoogleFonts.inter(
                            color: MedGuardPalette.pureWhite,
                            fontSize: 13.2,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPageDots extends StatelessWidget {
  const _OnboardingPageDots({required this.activeIndex});

  final int activeIndex;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(kOnboardingPageCount, (index) {
        final active = index == activeIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 24 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: active ? context.colors.accent : context.colors.border,
            borderRadius: BorderRadius.circular(100),
          ),
        );
      }),
    );
  }
}

/// The single, shared medicine "pill" used across every onboarding screen, so
/// each pill reads with the same shape, size, corner radius, stroke, colour and
/// spacing. Shows a medicine name, with an optional one-line note beneath it.
class OnboardingDrugPill extends StatelessWidget {
  const OnboardingDrugPill({
    super.key,
    required this.label,
    this.note,
    this.compact = false,
  });

  final String label;
  final String? note;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: context.colors.accentAlpha(0.14)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: GoogleFonts.inter(
              color: context.colors.ink,
              fontSize: compact ? 11.6 : 12,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
          if (note != null) ...[
            SizedBox(height: compact ? 2 : 3),
            Text(
              note!,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: GoogleFonts.inter(
                color: context.colors.inkSoft,
                fontSize: compact ? 10 : 10.4,
                fontWeight: FontWeight.w400,
                height: 1.2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The single, shared onboarding tag — a small icon plus a short label pill,
/// used for every onboarding eyebrow/label (Clinical Support, Severity Signal,
/// Decision Ready, Five Risk Areas, Profile Flags, Context Linked, …). One
/// background, opacity, type, weight, padding, height, radius, and border, with
/// no shadow — matching the flat onboarding surfaces — so every tag belongs to
/// the same component family.
class OnboardingTag extends StatelessWidget {
  const OnboardingTag({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: context.colors.accentAlpha(0.10),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: context.colors.accentAlpha(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: context.colors.accent, size: 15),
          const SizedBox(width: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            style: GoogleFonts.inter(
              color: context.colors.ink,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
