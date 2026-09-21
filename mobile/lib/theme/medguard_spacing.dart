import 'package:flutter/widgets.dart';

import 'medguard_responsive.dart';

class MedGuardSpacing {
  const MedGuardSpacing._();

  static const double sectionDividerBase = 52;

  static double sectionDivider(MedGuardResponsive responsive) {
    return responsive.s(sectionDividerBase).clamp(46.0, 54.0).toDouble();
  }

  /// THE universal gap between the top safe-area / status bar and the first
  /// element of every screen in the app.
  ///
  /// This is the *raw* (pre-scale) value — the form [MedGuardResponsive.pagePadding]
  /// expects, since that helper scales what it is given. Everywhere else, use
  /// [screenTop] (or [screenTopOf]) which returns the value already scaled;
  /// scaling it a second time by hand is the one mistake this pair exists to
  /// prevent.
  ///
  /// The inset sits ON TOP of the status-bar / notch inset, which every screen
  /// clears through its own `SafeArea`, so the gap is measured from the first
  /// pixel the user can actually see. Compact phones give up a few points so a
  /// small screen doesn't lose a third of its first fold to whitespace; tablets
  /// take more, because the same gap reads as cramped on a large canvas.
  static double screenTopGap(MedGuardResponsive responsive) {
    if (responsive.isCompactPhone) return 30;
    if (responsive.isTablet) return 44;
    return 38;
  }

  /// The universal screen top inset, already scaled — the value to drop into a
  /// hand-built [EdgeInsets]. Every top-level page and routed screen begins at
  /// exactly this height, so the app has one top rhythm rather than a dozen.
  static double screenTop(MedGuardResponsive responsive) =>
      responsive.s(screenTopGap(responsive));

  /// [screenTop] resolved straight from a [BuildContext], for call sites that
  /// don't already hold a [MedGuardResponsive].
  static double screenTopOf(BuildContext context) =>
      screenTop(MedGuardResponsive.of(context));

  /// The top inset for a screen whose first element is a fixed/sticky bar that
  /// already carries its own internal padding (a modal sheet's grabber, a
  /// collapsed pinned header). Two thirds of the full gap: enough to clear the
  /// status bar comfortably without double-counting the bar's own breathing
  /// room.
  static double stickyTop(MedGuardResponsive responsive) =>
      responsive.s(screenTopGap(responsive) * 0.62);
}

/// A spacer of exactly the app's universal screen top gap, for screens that
/// build their leading inset as a child rather than as page padding.
class ScreenTopSpacer extends StatelessWidget {
  const ScreenTopSpacer({super.key});

  @override
  Widget build(BuildContext context) =>
      SizedBox(height: MedGuardSpacing.screenTopOf(context));
}
