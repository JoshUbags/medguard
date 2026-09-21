import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/auth_profile_preferences.dart';
import '../../services/connectivity_service.dart';
import '../../theme/medguard_colors.dart';
import '../../theme/medguard_responsive.dart';
import 'account_avatar.dart';
import 'glass_surface.dart';
import '../../theme/medguard_palette.dart';
import 'pressable.dart';

/// The account avatar's standard header size — the same expression the home
/// header derives its avatar from, so every page's avatar is identical.
double headerAvatarSize(MedGuardResponsive r) =>
    r.font(13) + r.s(5).clamp(4.0, 6.0) + r.font(22);

/// Breathing room the header's glass capsule adds around its contents.
const double kHeaderGlassPad = 5;

/// Full height of a header row built around [HeaderGlassActions] — the capsule
/// is the tallest element, so it sets the row.
double headerRowHeight(MedGuardResponsive r) =>
    headerAvatarSize(r) + kHeaderGlassPad * 2;

/// THE page-title type scale. Every screen's heading is built from these, so a
/// title is the same size and weight whether it sits on a tab, a routed page,
/// or a full-screen sheet. Screens previously re-typed their own header and had
/// drifted to 20, 22, 24 and 30pt titles with four different subtitle sizes.
const double kPageTitleSize = 24;
const FontWeight kPageTitleWeight = FontWeight.w600;
const double kPageTitleTracking = -0.4;
const double kPageSubtitleSize = 13;
const FontWeight kPageSubtitleWeight = FontWeight.w400;

/// The shared page title, for screens that lay out their own header row.
TextStyle pageTitleStyle(MedGuardResponsive r, Color color) =>
    GoogleFonts.inter(
      color: color,
      fontSize: r.font(kPageTitleSize),
      fontWeight: kPageTitleWeight,
      letterSpacing: kPageTitleTracking,
      height: 1.1,
    );

/// The shared page subtitle, paired with [pageTitleStyle].
TextStyle pageSubtitleStyle(MedGuardResponsive r, Color color) =>
    GoogleFonts.inter(
      color: color,
      fontSize: r.font(kPageSubtitleSize),
      fontWeight: kPageSubtitleWeight,
      height: 1.45,
    );

/// The signed-in display name, or null when there isn't one yet.
String? headerDisplayName() {
  String? firebaseName;
  try {
    firebaseName = FirebaseAuth.instance.currentUser?.displayName;
  } catch (_) {}
  final resolved = AuthProfilePreferences.resolveDisplayName(
    firebaseDisplayName: firebaseName,
    fallback: '',
  );
  return resolved.isEmpty ? null : resolved;
}

/// The signed-in profile photo URL, or null.
String? headerPhotoUrl() {
  try {
    final url = FirebaseAuth.instance.currentUser?.photoURL?.trim();
    return (url != null && url.isNotEmpty) ? url : null;
  } catch (_) {
    return null;
  }
}

/// The shared title block for a primary destination: a page title, a one-line
/// subtitle, and the profile avatar on the right.
///
/// Every top-level page uses this so the title size, the subtitle size, the gap
/// between them and the avatar's position are identical across the app — the
/// header was previously re-typed per screen and had drifted by a point or two
/// in several places. The notification bell stays exclusive to Home; the other
/// pages carry the avatar alone.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onOpenProfile,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final VoidCallback onOpenProfile;

  /// Icon actions carried INSIDE the glass capsule, to the left of the avatar —
  /// the same slot Home's notification bell occupies. Each is built at
  /// [headerAvatarSize] so the cluster stays one clean row.
  ///
  /// Deliberately not a free-form `trailing` widget: the previous signature let
  /// each page park an arbitrary control beside the avatar at whatever size it
  /// liked, which is how the header drifted apart page to page.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: pageTitleStyle(responsive, colors.ink)),
              SizedBox(height: responsive.s(6)),
              Text(
                subtitle,
                style: pageSubtitleStyle(responsive, colors.inkSoft),
              ),
            ],
          ),
        ),
        SizedBox(width: responsive.s(12)),
        // The avatar rides in the shared glass capsule here too, so the profile
        // control is the SAME object in the same place on every page — Home,
        // Dose, Interactions, Insights and the AI tab alike. It used to be a
        // bare avatar on the pages that used this header and a capsule on the
        // two that hand-rolled theirs, which is exactly the drift that made the
        // app feel stitched together.
        HeaderGlassActions(
          key: const ValueKey('page-header-actions'),
          avatarSize: headerAvatarSize(responsive),
          name: headerDisplayName(),
          photoUrl: headerPhotoUrl(),
          onAvatarTap: onOpenProfile,
          avatarKey: const ValueKey('page-header-avatar'),
          actions: actions,
        ),
      ],
    );
  }
}

/// A header's trailing action cluster: any icon actions plus the profile
/// avatar, sitting together on ONE clear liquid-glass capsule — a real backdrop
/// blur under a faint tint with a luminous hairline, so the page reads through
/// it as it scrolls past.
///
/// This is the Home header's cluster, extracted so other pages can carry the
/// identical treatment instead of inventing a second header language. Sizing,
/// tint, blur, rim and spacing all live here, which is what keeps Home and Dose
/// pixel-identical rather than merely similar.
///
/// Built on the shared [GlassSurface], so it is the same material as the AI
/// input — blurred, saturation-lifted, with the raking lit rim that makes a
/// pane read as glass rather than as a translucent rectangle. It runs a touch
/// sheerer than a full chrome pane because it frames a photo on the page's own
/// canvas, where a heavier tint would read as a floating slab.
class HeaderGlassActions extends StatelessWidget {
  const HeaderGlassActions({
    super.key,
    required this.avatarSize,
    required this.name,
    required this.photoUrl,
    required this.onAvatarTap,
    this.actions = const [],
    this.connectivityService,
    this.avatarKey,
    this.statusDotKey,
  });

  final double avatarSize;
  final String? name;
  final String? photoUrl;
  final VoidCallback onAvatarTap;

  /// Icon actions shown to the LEFT of the avatar, in order. Each is sized to
  /// [avatarSize] by its own builder so the cluster stays one clean row.
  final List<Widget> actions;

  final ConnectivityService? connectivityService;
  final Key? avatarKey;
  final Key? statusDotKey;

  @override
  Widget build(BuildContext context) {
    final capsuleRadius = BorderRadius.circular(
      (avatarSize + kHeaderGlassPad * 2) / 2,
    );

    // Plain defaults on purpose: THIS capsule is the app's reference glass, so
    // it must be the component's untouched output. Anything that tuned it here
    // would silently make every other pane a near-miss.
    return GlassSurface(
      borderRadius: capsuleRadius,
      padding: const EdgeInsets.all(kHeaderGlassPad),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final action in actions) ...[
            action,
            const SizedBox(width: kHeaderGlassPad + 1),
          ],
          AccountAvatar(
            name: name,
            photoUrl: photoUrl,
            size: avatarSize,
            onTap: onAvatarTap,
            connectivityService: connectivityService,
            avatarKey: avatarKey,
            statusDotKey: statusDotKey,
          ),
        ],
      ),
    );
  }
}

/// A circular icon action for a [PageHeader]'s glass capsule.
///
/// Built to the exact geometry [NotificationBell] uses — same diameter, same
/// fill, same hairline — so the Home header's bell and the Interactions
/// header's search button occupy the identical slot at the identical size. The
/// bell carries its own unread badge and so stays a widget of its own; this is
/// for every other header icon.
class HeaderIconAction extends StatelessWidget {
  const HeaderIconAction({
    super.key,
    required this.icon,
    required this.size,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;

  /// Diameter — matched to the avatar beside it.
  final double size;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = colors.isDark;

    return Pressable(
      onTap: onTap,
      pressScale: 0.9,
      semanticLabel: semanticLabel,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark
              ? MedGuardPalette.whiteAlpha(0.08)
              : colors.surface.withValues(alpha: 0.92),
          border: Border.all(
            color: isDark
                ? MedGuardPalette.whiteAlpha(0.10)
                : colors.ink.withValues(alpha: 0.06),
          ),
        ),
        child: Icon(icon, size: size * 0.46, color: colors.ink),
      ),
    );
  }
}
