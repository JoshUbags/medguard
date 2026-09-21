import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import 'app_notice.dart';

/// Semantic tone for an [AppSnack] toast.
enum AppSnackTone { neutral, success, warning, error }

/// Centralised, design-system-consistent popup messages.
///
/// This is a thin façade over [showAppNotice] — the app's single toast
/// presentation. It used to build Material [SnackBar]s instead, which is why
/// messages raised from the AI screen looked and sat differently from the rest
/// of the app: a floating SnackBar is positioned by the host [Scaffold], and
/// the AI tab is the one screen with no bottom navigation, so its toasts landed
/// at a different height in a different shape. Routing everything through the
/// overlay pill removes that class of drift entirely — one position, one
/// shape, one type scale, on every screen.
///
/// Tone is conveyed consistently: teal = success, amber = warning,
/// ruby = error, teal-neutral = information.
class AppSnack {
  AppSnack._();

  static void show(
    BuildContext context,
    String message, {
    AppSnackTone tone = AppSnackTone.neutral,
  }) {
    // Gentle confirmation buzz; a firmer one for errors so the hand registers
    // something went wrong without looking.
    switch (tone) {
      case AppSnackTone.success:
        HapticFeedback.lightImpact();
      case AppSnackTone.error:
        HapticFeedback.heavyImpact();
      case AppSnackTone.warning:
        HapticFeedback.mediumImpact();
      case AppSnackTone.neutral:
        HapticFeedback.selectionClick();
    }

    showAppNotice(
      context,
      message,
      type: switch (tone) {
        AppSnackTone.success => AppNoticeType.success,
        AppSnackTone.warning => AppNoticeType.warning,
        AppSnackTone.error => AppNoticeType.error,
        AppSnackTone.neutral => AppNoticeType.info,
      },
    );
  }

  /// Teal confirmation toast (e.g. "Added to your regimen").
  static void success(BuildContext context, String message) =>
      show(context, message, tone: AppSnackTone.success);

  /// Amber caution toast (e.g. "This may interact with a saved medicine").
  static void warning(BuildContext context, String message) =>
      show(context, message, tone: AppSnackTone.warning);

  /// Ruby error toast (e.g. "Couldn't save").
  static void error(BuildContext context, String message) =>
      show(context, message, tone: AppSnackTone.error);

  /// A neutral "removed" toast with an UNDO action — the safety net behind
  /// every swipe-to-delete so an accidental swipe is always recoverable.
  static void undo(
    BuildContext context,
    String message, {
    required VoidCallback onUndo,
  }) {
    HapticFeedback.mediumImpact();
    showAppNotice(
      context,
      message,
      type: AppNoticeType.undo,
      actionLabel: 'UNDO',
      onAction: onUndo,
    );
  }
}
