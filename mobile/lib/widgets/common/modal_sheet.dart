import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/medguard_colors.dart';
import '../../theme/medguard_responsive.dart';
import 'app_button.dart';
import 'pressable.dart';

/// THE modal surface. Every sheet, confirmation and picker in the app is one of
/// the three helpers below, so a decision always arrives in the same shape, in
/// the same place, with its actions in the same order.
///
/// Bottom sheets rather than centre dialogs, deliberately: on a phone held one
/// handed, a centre dialog puts its buttons in the middle of the screen, out of
/// thumb reach and directly over the content the user is being asked about. A
/// sheet rises from the edge nearest the hand and leaves the page visible above
/// it, which is what lets someone check what they were looking at before they
/// answer.
///
/// Destructive confirmations follow one rule throughout: the safe option is
/// always present, always first in reading order, and never the pre-selected
/// bright button.

/// The shared chrome — grabber, title, optional caption, content, actions.
Future<T?> showModalSheet<T>({
  required BuildContext context,
  required String title,
  required Widget Function(BuildContext) builder,
  String? subtitle,
  String? confirmLabel,
  String cancelLabel = 'Cancel',

  /// Return false to keep the sheet open (a failed validation). Return true to
  /// close it with `true`.
  bool Function()? onConfirm,
  AppButtonVariant confirmVariant = AppButtonVariant.primary,
  IconData? icon,
  Color? iconTint,
}) {
  final colors = context.colors;

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: colors.ink.withValues(alpha: colors.isDark ? 0.62 : 0.34),
    builder: (ctx) {
      final r = MedGuardResponsive.of(ctx);
      final c = ctx.colors;
      return Padding(
        // Lifts clear of the keyboard when the sheet holds a text field.
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(r.radius(28)),
            ),
            border: Border(top: BorderSide(color: c.border)),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  r.pageX,
                  r.s(12),
                  r.pageX,
                  r.s(18),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // The grabber: the universal "this can be dragged away"
                    // affordance. Without it a sheet reads as a screen that has
                    // trapped you.
                    Center(
                      child: Container(
                        width: r.s(38),
                        height: 4,
                        decoration: BoxDecoration(
                          color: c.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    SizedBox(height: r.s(18)),
                    if (icon != null) ...[
                      Center(
                        child: Container(
                          width: r.s(52),
                          height: r.s(52),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: (iconTint ?? c.accent).withValues(
                              alpha: 0.12,
                            ),
                          ),
                          child: Icon(
                            icon,
                            size: r.icon(24),
                            color: iconTint ?? c.accent,
                          ),
                        ),
                      ),
                      SizedBox(height: r.s(14)),
                    ],
                    Text(
                      title,
                      textAlign: icon == null
                          ? TextAlign.start
                          : TextAlign.center,
                      style: GoogleFonts.inter(
                        color: c.ink,
                        fontSize: r.font(18),
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                        height: 1.2,
                      ),
                    ),
                    if (subtitle != null) ...[
                      SizedBox(height: r.s(6)),
                      Text(
                        subtitle,
                        textAlign: icon == null
                            ? TextAlign.start
                            : TextAlign.center,
                        style: GoogleFonts.inter(
                          color: c.inkSoft,
                          fontSize: r.font(13),
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    SizedBox(height: r.s(20)),
                    builder(ctx),
                    if (confirmLabel != null) ...[
                      SizedBox(height: r.s(22)),
                      AppButton(
                        label: confirmLabel,
                        variant: confirmVariant,
                        onTap: () {
                          if (onConfirm != null && !onConfirm()) return;
                          HapticFeedback.lightImpact();
                          // The built-in footer answers a yes/no question, so
                          // it pops `true` — but only when the caller's result
                          // type can actually hold it. A sheet whose content
                          // pops its own richer value (an option row, a picked
                          // date) closes with nothing here.
                          if (true is T) {
                            Navigator.of(ctx).pop(true as T);
                          } else {
                            Navigator.of(ctx).pop();
                          }
                        },
                      ),
                      SizedBox(height: r.s(10)),
                      Center(
                        child: Pressable(
                          onTap: () => Navigator.of(ctx).pop(),
                          pressScale: 0.96,
                          semanticLabel: cancelLabel,
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: r.s(20),
                              vertical: r.s(10),
                            ),
                            child: Text(
                              cancelLabel,
                              style: GoogleFonts.inter(
                                color: c.inkMute,
                                fontSize: r.font(13),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// A yes/no decision. Returns true only if the user explicitly confirmed.
///
/// [destructive] swaps the confirm button to ruby and tints the icon — the two
/// signals that this action does not come back.
Future<bool?> showConfirmSheet({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  bool destructive = false,
  IconData? icon,
}) {
  final colors = context.colors;
  return showModalSheet<bool>(
    context: context,
    title: title,
    subtitle: message,
    icon:
        icon ??
        (destructive
            ? Icons.warning_amber_rounded
            : Icons.help_outline_rounded),
    iconTint: destructive ? colors.danger : colors.accent,
    confirmLabel: confirmLabel,
    cancelLabel: cancelLabel,
    confirmVariant: destructive
        ? AppButtonVariant.danger
        : AppButtonVariant.primary,
    builder: (_) => const SizedBox.shrink(),
  );
}

/// One choice from a short list. Returns the chosen value, or null if dismissed.
///
/// Used for share formats, report intervals, theme modes — anywhere a settings
/// row opens onto a small fixed set. A radio list rather than a dropdown: on a
/// phone the whole set is worth showing at once, and the current selection
/// should be visible without opening anything.
Future<T?> showOptionSheet<T>({
  required BuildContext context,
  required String title,
  required List<SheetOption<T>> options,
  String? subtitle,
  T? selected,
}) {
  return showModalSheet<T>(
    context: context,
    title: title,
    subtitle: subtitle,
    builder: (ctx) {
      final r = MedGuardResponsive.of(ctx);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) SizedBox(height: r.s(8)),
            _OptionRow<T>(
              option: options[i],
              isSelected: options[i].value == selected,
              onTap: () {
                HapticFeedback.selectionClick();
                Navigator.of(ctx).pop(options[i].value);
              },
            ),
          ],
        ],
      );
    },
  );
}

/// One row of a [showOptionSheet].
class SheetOption<T> {
  const SheetOption({
    required this.value,
    required this.label,
    this.detail,
    this.icon,
    this.enabled = true,
  });

  final T value;
  final String label;
  final String? detail;
  final IconData? icon;

  /// Set false for a choice that is real but not currently available — one the
  /// user has already made, say. It stays on screen, dimmed and inert, rather
  /// than disappearing: an option that vanishes once taken leaves the user
  /// wondering whether they imagined it, and a list whose length changes
  /// between visits is harder to learn.
  final bool enabled;
}

class _OptionRow<T> extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final SheetOption<T> option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = MedGuardResponsive.of(context);
    final c = context.colors;

    final on = option.enabled;

    return Pressable(
      onTap: on ? onTap : null,
      pressScale: 0.985,
      selected: isSelected,
      semanticLabel: option.label,
      child: Opacity(
        opacity: on ? 1 : 0.45,
        child: Container(
        padding: EdgeInsets.symmetric(horizontal: r.s(14), vertical: r.s(13)),
        decoration: BoxDecoration(
          color: isSelected ? c.accentAlpha(0.08) : c.surfaceAlt,
          borderRadius: BorderRadius.circular(r.radius(16)),
          border: Border.all(
            color: isSelected ? c.accentAlpha(0.34) : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            if (option.icon != null) ...[
              Icon(
                option.icon,
                size: r.icon(20),
                color: isSelected ? c.accent : c.inkMute,
              ),
              SizedBox(width: r.s(12)),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    option.label,
                    style: GoogleFonts.inter(
                      color: c.ink,
                      fontSize: r.font(14),
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  if (option.detail != null) ...[
                    SizedBox(height: r.s(2)),
                    Text(
                      option.detail!,
                      style: GoogleFonts.inter(
                        color: c.inkMute,
                        fontSize: r.font(12.2),
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: r.s(10)),
            // A check that is PRESENT-or-absent rather than an empty circle
            // that fills: with several rows on screen, a set of empty rings
            // reads as a checklist waiting to be completed.
            AnimatedOpacity(
              duration: const Duration(milliseconds: 160),
              opacity: isSelected ? 1 : 0,
              child: Icon(
                Icons.check_circle_rounded,
                size: r.icon(21),
                color: c.accent,
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}
