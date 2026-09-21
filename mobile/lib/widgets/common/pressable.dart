import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Wraps any [child] with a premium tactile press-in / spring-out animation.
///
/// On tap-down: quickly scales to [pressScale] (default 0.95).
/// On tap-up / cancel: springs back to 1.0 with an overshoot bounce.
/// Fires [onTap] after the release snap.
///
/// Accessibility: a bare [GestureDetector] driven by `onTapDown`/`onTapUp`
/// exposes NO semantic tap action, so screen readers (TalkBack/VoiceOver) can
/// neither announce nor activate it. When [semanticLabel] (or [selected]) is
/// supplied, this widget wraps the gesture in a [Semantics] button node that
/// carries the label and a real `onTap` action, so the press becomes both
/// announceable and activatable. Callers that manage their own semantics can
/// leave [semanticLabel] null to keep the original bare behaviour.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    required this.onTap,
    this.pressScale = 0.95,
    this.haptic = true,
    this.disabled = false,
    this.semanticLabel,
    this.selected,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double pressScale;
  final bool haptic;
  final bool disabled;

  /// Spoken label for screen readers. When non-null the press is wrapped in a
  /// semantic button node carrying this label and an activatable tap action.
  final String? semanticLabel;

  /// Toggle/selection state announced to screen readers (e.g. the active nav
  /// tab). Implies the semantic button wrapper even when [semanticLabel] is set
  /// to null.
  final bool? selected;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 320),
    );
    _scale = _buildScale(widget.pressScale);
  }

  @override
  void didUpdateWidget(covariant Pressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pressScale != widget.pressScale) {
      _scale = _buildScale(widget.pressScale);
    }
  }

  Animation<double> _buildScale(double endScale) {
    return Tween<double>(begin: 1.0, end: endScale).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: Curves.easeInOut,
        reverseCurve: Curves.elasticOut,
      ),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (widget.disabled || widget.onTap == null) return;
    _ctrl.forward();
  }

  void _onTapUp(TapUpDetails _) {
    _activate();
  }

  /// Runs the release snap, haptic, and [onTap]. Shared by the pointer path
  /// (`onTapUp`) and the screen-reader path (the [Semantics] `onTap` action),
  /// so both feel identical.
  void _activate() {
    if (widget.disabled || widget.onTap == null) return;
    _ctrl.reverse();
    if (widget.haptic) HapticFeedback.lightImpact();
    widget.onTap!();
  }

  void _onTapCancel() {
    _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final Widget gesture = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scale,
        builder: (context, child) =>
            Transform.scale(scale: _scale.value, child: child),
        child: widget.child,
      ),
    );

    // Only attach a semantic button node when the caller asked for one;
    // otherwise stay a bare gesture so existing self-described callers don't
    // end up with a redundant nested node.
    if (widget.semanticLabel == null && widget.selected == null) {
      return gesture;
    }

    final enabled = !widget.disabled && widget.onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: widget.selected,
      label: widget.semanticLabel,
      onTap: enabled ? _activate : null,
      // The inner GestureDetector contributes no semantic action, so this is
      // the single source of truth for the node — no merge conflict.
      child: gesture,
    );
  }
}
