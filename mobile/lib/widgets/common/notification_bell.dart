import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/notification_center.dart';
import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';
import '../../theme/medguard_responsive.dart';
import 'pressable.dart';

/// The notification bell with its live unread badge.
///
/// The badge is driven by [NotificationCenter.unreadCount], so it appears the
/// moment the user's own data raises something that needs attention and clears
/// itself as items are read — it is never a decorative dot. Counts above nine
/// collapse to "9+" so the badge keeps its shape.
class NotificationBell extends StatelessWidget {
  const NotificationBell({
    super.key,
    required this.size,
    required this.onTap,
    this.badgeKey,
  });

  /// Diameter of the circular button — matched to the avatar beside it.
  final double size;
  final VoidCallback onTap;
  final Key? badgeKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = colors.isDark;

    return ValueListenableBuilder<int>(
      valueListenable: NotificationCenter.instance.unreadCount,
      builder: (context, unread, _) {
        return Pressable(
          onTap: onTap,
          pressScale: 0.9,
          semanticLabel: unread == 0
              ? 'Notifications'
              : 'Notifications, $unread unread',
          // The badge overflows the circle, so the stack must not clip it.
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
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
                child: Icon(
                  unread > 0
                      ? Icons.notifications_rounded
                      : Icons.notifications_none_rounded,
                  color: colors.ink,
                  size: size * 0.48,
                ),
              ),
              if (unread > 0)
                Positioned(
                  top: -1,
                  right: -2,
                  child: _Badge(key: badgeKey, count: unread),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final label = count > 9 ? '9+' : '$count';
    final diameter = responsive.s(17).clamp(15.0, 20.0).toDouble();

    return Container(
      constraints: BoxConstraints(minWidth: diameter, minHeight: diameter),
      padding: EdgeInsets.symmetric(horizontal: count > 9 ? 4 : 0),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.danger,
        borderRadius: BorderRadius.circular(100),
        // A ring in the page colour cuts the badge cleanly out of whatever it
        // overlaps, so it reads as a separate mark rather than a smudge.
        border: Border.all(color: colors.scaffold, width: 1.6),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          color: MedGuardPalette.pureWhite,
          fontSize: responsive.font(9.6),
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}
