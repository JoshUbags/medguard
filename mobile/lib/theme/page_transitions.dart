import 'package:flutter/material.dart';

/// How long a page change takes. Long enough to be *seen* as a movement rather
/// than a cut; short enough that a user tapping through four screens never waits
/// on the animation. Below roughly 240ms a transition stops registering as
/// motion and just reads as a flicker; above roughly 420ms it starts to feel
/// like the app is slow.
const Duration kPageTransitionDuration = Duration(milliseconds: 340);
const Duration kPageTransitionReverse = Duration(milliseconds: 280);

/// THE app's page transition: a shared-axis glide.
///
/// The arriving page slides a short distance in from the trailing edge while
/// fading up; the departing page slides a *shorter* distance the same way and
/// dims. The asymmetry is the whole trick — equal travel makes two pages look
/// like they are sliding past each other on one plane (a cheap carousel),
/// whereas a shallower, dimmer exit reads as the old page settling *back* a
/// layer while the new one arrives in front of it. That is what gives the
/// movement depth without any visible shadow or scrim.
///
/// Both pages also scale by a couple of percent, in opposite directions, which
/// is what carries the sense of depth on a screen with no perspective.
///
/// Registered once in [PageTransitionsTheme], so every named route, every
/// `MaterialPageRoute`, and every `Navigator.push` in the app inherits it — a
/// screen cannot accidentally opt out and cut instead.
class MedGuardPageTransitionsBuilder extends PageTransitionsBuilder {
  const MedGuardPageTransitionsBuilder();

  @override
  Duration get transitionDuration => kPageTransitionDuration;

  @override
  Duration get reverseTransitionDuration => kPageTransitionReverse;

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return MedGuardSharedAxis(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

/// The transition itself, exposed separately so hand-built routes
/// ([medGuardRoute]) and the theme builder above share one implementation
/// instead of drifting into two similar-looking movements.
class MedGuardSharedAxis extends StatelessWidget {
  const MedGuardSharedAxis({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  /// Travel of the ARRIVING page, as a fraction of its width.
  static const double _enterTravel = 0.06;

  /// Travel of the DEPARTING page. Deliberately a third of the entrance, so the
  /// outgoing page recedes rather than races away.
  static const double _exitTravel = 0.02;

  @override
  Widget build(BuildContext context) {
    final enter = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final exit = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return AnimatedBuilder(
      animation: exit,
      builder: (context, inner) {
        final e = exit.value;
        return Transform.translate(
          // Recedes toward the leading edge as the next page covers it.
          offset: Offset(-e * MediaQuery.sizeOf(context).width * _exitTravel, 0),
          child: Transform.scale(
            scale: 1 - 0.018 * e,
            child: Opacity(opacity: 1 - 0.35 * e, child: inner),
          ),
        );
      },
      child: AnimatedBuilder(
        animation: enter,
        builder: (context, inner) {
          final t = enter.value;
          return Transform.translate(
            offset: Offset(
              (1 - t) * MediaQuery.sizeOf(context).width * _enterTravel,
              0,
            ),
            child: Transform.scale(
              scale: 0.985 + 0.015 * t,
              // Fades in over the first two thirds so the page is fully solid
              // before it finishes settling — arriving already-opaque is what
              // makes a transition feel confident rather than hesitant.
              child: Opacity(opacity: (t * 1.5).clamp(0.0, 1.0), child: inner),
            ),
          );
        },
        child: child,
      ),
    );
  }
}

/// The transition theme to hand [ThemeData.pageTransitionsTheme]. One movement
/// on every platform on purpose: this is a branded transition, and an app that
/// glides on Android but slides Cupertino-style on iOS has two personalities.
const PageTransitionsTheme kMedGuardPageTransitions = PageTransitionsTheme(
  builders: <TargetPlatform, PageTransitionsBuilder>{
    TargetPlatform.android: MedGuardPageTransitionsBuilder(),
    TargetPlatform.iOS: MedGuardPageTransitionsBuilder(),
    TargetPlatform.macOS: MedGuardPageTransitionsBuilder(),
    TargetPlatform.windows: MedGuardPageTransitionsBuilder(),
    TargetPlatform.linux: MedGuardPageTransitionsBuilder(),
    TargetPlatform.fuchsia: MedGuardPageTransitionsBuilder(),
  },
);

/// A route carrying the app transition, for the `Navigator.push` call sites that
/// build their own route instead of using a named one.
Route<T> medGuardRoute<T>(Widget page, {RouteSettings? settings}) {
  return PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: kPageTransitionDuration,
    reverseTransitionDuration: kPageTransitionReverse,
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        MedGuardSharedAxis(
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          child: child,
        ),
  );
}

/// A vertical variant for screens that are conceptually *raised over* the app
/// rather than *next in a sequence* — the profile sheet, a full-screen editor.
/// Rising from below is the universal read for "this is on top of what you were
/// doing, and dismissing it returns you there".
Route<T> medGuardSheetRoute<T>(Widget page, {RouteSettings? settings}) {
  return PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, _, _) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final eased = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.045),
          end: Offset.zero,
        ).animate(eased),
        child: FadeTransition(opacity: eased, child: child),
      );
    },
  );
}

/// An [IndexedStack] that fades THROUGH when the selected index changes: the
/// outgoing child dims and settles back, then the incoming one rises and
/// resolves.
///
/// The IndexedStack is what makes this usable for a tab bar — every tab stays
/// mounted, so scroll positions, in-flight loads and controller state all
/// survive a switch. A plain `AnimatedSwitcher` would animate beautifully and
/// throw away the state of every screen the user leaves.
///
/// The two halves never overlap: the index changes exactly at the midpoint,
/// while the stack is at zero opacity. Cross-fading two full pages is what makes
/// a tab change look muddy — for a beat you can see both screens' text through
/// each other. Fading through nothing is cleaner and reads as more deliberate.
class FadeThroughIndexedStack extends StatefulWidget {
  const FadeThroughIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 300),
  });

  final int index;
  final List<Widget> children;
  final Duration duration;

  @override
  State<FadeThroughIndexedStack> createState() =>
      _FadeThroughIndexedStackState();
}

class _FadeThroughIndexedStackState extends State<FadeThroughIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late int _shownIndex;

  @override
  void initState() {
    super.initState();
    _shownIndex = widget.index;
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant FadeThroughIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index == widget.index) return;

    // Out, swap, in. Driving one controller 1→0→1 (rather than two chained
    // ones) keeps the halves in lockstep even if the tab is changed again
    // mid-flight: the reverse simply restarts from wherever it had got to.
    _controller.reverse().then((_) {
      if (!mounted) return;
      setState(() => _shownIndex = widget.index);
      _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = Curves.easeOut.transform(_controller.value);
        return Opacity(
          opacity: t,
          // A hair of scale so the page settles INTO place rather than simply
          // appearing at full size — the detail that separates a fade from a
          // transition.
          child: Transform.scale(scale: 0.992 + 0.008 * t, child: child),
        );
      },
      child: IndexedStack(index: _shownIndex, children: widget.children),
    );
  }
}
