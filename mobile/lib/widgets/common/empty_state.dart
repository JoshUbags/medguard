import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/medguard_colors.dart';
import '../../theme/medguard_responsive.dart';
import 'app_button.dart';
import 'surface_card.dart';

/// The app's "there is nothing here yet" block.
///
/// Built on [SurfaceCard] and the responsive scale like every other surface, so
/// an empty list sits on the same radius, border and shadow as the populated one
/// it replaces. It used to declare its own container with hard-coded 24/30/56
/// values, which meant the empty state was visibly a different material from the
/// content it stood in for — and stayed the same size on every screen.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final mark = responsive.s(52).clamp(46.0, 60.0).toDouble();
    final label = actionLabel;

    return SurfaceCard(
      padding: EdgeInsets.all(responsive.s(20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: mark,
            height: mark,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.accentAlpha(0.10),
              borderRadius: BorderRadius.circular(responsive.radius(18)),
            ),
            child: Icon(icon, color: colors.accent, size: responsive.icon(25)),
          ),
          SizedBox(height: responsive.s(18)),
          Text(
            title,
            style: GoogleFonts.inter(
              color: colors.ink,
              fontSize: responsive.font(17),
              height: 1.15,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          SizedBox(height: responsive.s(7)),
          Text(
            message,
            style: GoogleFonts.inter(
              color: colors.inkSoft,
              fontSize: responsive.font(12.8),
              height: 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (label != null && onAction != null) ...[
            SizedBox(height: responsive.s(18)),
            AppButton(label: label, onTap: onAction, expand: false),
          ],
        ],
      ),
    );
  }
}

/// The failure counterpart of [EmptyState]: same block, one retry action.
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.warning_amber_rounded,
      title: title,
      message: message,
      actionLabel: 'Retry',
      onAction: onRetry,
    );
  }
}
