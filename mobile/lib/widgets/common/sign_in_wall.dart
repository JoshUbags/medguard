import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../screens/auth/login_screen.dart';
import '../../theme/medguard_colors.dart';
import '../../theme/medguard_responsive.dart';
import 'app_button.dart';

/// The one way MedGuard says "this part belongs to an account".
///
/// Guest mode gives the whole on-device safety tool away — every check, every
/// medicine, every report — so the handful of places that genuinely need an
/// account must explain themselves rather than simply refuse. Each wall states
/// what the feature is FOR, why the account is what carries it, and, where
/// there is one, the concrete thing already waiting on this device ("3 checks
/// already saved here"). A locked door with a reason on it is a feature; a
/// locked door without one is a bug the user reports.
///
/// Deliberately not a full page: it is dropped into the screen it gates so the
/// title, back button and chrome stay exactly where the user expects them.
class SignInWall extends StatelessWidget {
  const SignInWall({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.waiting,
    this.signInLabel = 'Sign in',
  });

  /// The gated feature's own icon — the same one its entry point uses, so the
  /// wall reads as that feature rather than as a generic barrier.
  final IconData icon;

  final String title;

  /// Why the account is the thing that carries this, in the user's terms.
  final String message;

  /// What is already on this device and will appear here once signed in, e.g.
  /// "3 safety checks are saved on this device." Omitted when there is nothing
  /// waiting — an invented promise is worse than no line at all.
  final String? waiting;

  final String signInLabel;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.s(8),
        vertical: responsive.s(28),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: responsive.s(72),
            height: responsive.s(72),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colors.accentAlpha(0.10),
              border: Border.all(color: colors.accentAlpha(0.18)),
            ),
            child: Icon(
              icon,
              color: colors.accent,
              size: responsive.icon(30),
            ),
          ),
          SizedBox(height: responsive.s(18)),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: colors.ink,
              fontSize: responsive.font(18),
              fontWeight: FontWeight.w600,
              height: 1.2,
              letterSpacing: -0.2,
            ),
          ),
          SizedBox(height: responsive.s(10)),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: colors.inkSoft,
              fontSize: responsive.font(13.2),
              fontWeight: FontWeight.w400,
              height: 1.46,
            ),
          ),
          if (waiting != null) ...[
            SizedBox(height: responsive.s(16)),
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: responsive.s(13),
                vertical: responsive.s(9),
              ),
              decoration: BoxDecoration(
                color: colors.accentAlpha(0.08),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: colors.accentAlpha(0.16)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.inventory_2_rounded,
                    color: colors.accent,
                    size: responsive.icon(14),
                  ),
                  SizedBox(width: responsive.s(7)),
                  Flexible(
                    child: Text(
                      waiting!,
                      style: GoogleFonts.inter(
                        color: colors.ink,
                        fontSize: responsive.font(12.2),
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: responsive.s(24)),
          AppButton(
            label: signInLabel,
            icon: Icons.login_rounded,
            onTap: () => openSignIn(context),
          ),
          SizedBox(height: responsive.s(12)),
          Text(
            'Everything else in MedGuard keeps working without one.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: colors.inkMute,
              fontSize: responsive.font(11.8),
              fontWeight: FontWeight.w400,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the sign-in screen from anywhere inside the app.
///
/// A push rather than a replacement: a guest who taps "Sign in" out of
/// curiosity and changes their mind must land back on the page they came from,
/// not on a login wall with the app gone from underneath them.
void openSignIn(BuildContext context) {
  Navigator.of(context).pushNamed(LoginScreen.routeName);
}
