import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/notification_center.dart';
import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';
import '../../theme/medguard_responsive.dart';
import '../../widgets/common/app_snack.dart';
import '../../widgets/common/detail_page.dart';
import '../../widgets/common/section_header.dart';
import '../../widgets/common/surface_card.dart';

/// The notification feed — generated entirely from the user's own live data by
/// [NotificationCenter]. Nothing here is canned: an empty list renders an
/// honest all-caught-up state rather than sample notifications.
///
/// Items are grouped by urgency (Needs attention / Updates) under the app's
/// standard section headings, can be read, swiped away with an undo, or marked
/// read in bulk.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.now});

  static const String routeName = '/notifications';

  /// Injectable clock for tests; defaults to the wall clock.
  final DateTime Function()? now;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<NotificationEntry>? _entries;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await NotificationCenter.instance.refresh(
      now: widget.now?.call(),
    );
    if (!mounted) return;
    setState(() => _entries = entries);
  }

  Future<void> _open(AppNotification item) async {
    await NotificationCenter.instance.markRead(item.id);
    if (!mounted) return;
    setState(() => _entries = NotificationCenter.instance.entries);
    final route = item.actionRoute;
    if (route == null) return;
    Navigator.of(context).pushNamed(route);
  }

  Future<void> _dismiss(AppNotification item) async {
    await NotificationCenter.instance.dismiss(item.id);
    if (!mounted) return;
    setState(() => _entries = NotificationCenter.instance.entries);
    AppSnack.undo(
      context,
      'Notification dismissed',
      onUndo: () async {
        await NotificationCenter.instance.restore(item.id);
        if (!mounted) return;
        setState(() => _entries = NotificationCenter.instance.entries);
      },
    );
  }

  Future<void> _markAllRead() async {
    await NotificationCenter.instance.markAllRead();
    if (!mounted) return;
    setState(() => _entries = NotificationCenter.instance.entries);
    AppSnack.success(context, 'All caught up');
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final entries = _entries;
    final unread = entries?.where((entry) => entry.counts).length ?? 0;

    final attention =
        entries
            ?.where((e) => e.notification.demandsAttention)
            .toList(growable: false) ??
        const <NotificationEntry>[];
    final updates =
        entries
            ?.where((e) => !e.notification.demandsAttention)
            .toList(growable: false) ??
        const <NotificationEntry>[];

    final subtitle = entries == null
        ? 'Checking your latest data'
        : entries.isEmpty
        ? 'You\'re all caught up.'
        : unread == 0
        ? '${entries.length} ${entries.length == 1 ? 'update' : 'updates'}, '
              'all read.'
        : '$unread of ${entries.length} '
              '${unread == 1 ? 'needs' : 'need'} your attention.';

    return DetailPage(
      title: 'Notifications',
      subtitle: subtitle,
      onRefresh: _load,
      actions: [
        if (unread > 0)
          DetailPageAction(
            icon: Icons.done_all_rounded,
            label: 'Mark read',
            semanticLabel: 'Mark all notifications read',
            onTap: _markAllRead,
          ),
      ],
      slivers: [
        if (entries == null)
          const SliverToBoxAdapter(child: _NotificationsLoading())
        else if (entries.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _NotificationsEmpty(),
          )
        else ...[
          if (attention.isNotEmpty)
            _section(responsive, 'Needs attention', attention, first: true),
          if (updates.isNotEmpty)
            _section(responsive, 'Updates', updates, first: attention.isEmpty),
        ],
      ],
    );
  }

  Widget _section(
    MedGuardResponsive responsive,
    String label,
    List<NotificationEntry> entries, {
    required bool first,
  }) {
    return SliverToBoxAdapter(
      child: responsive.constrain(
        Padding(
          padding: EdgeInsets.fromLTRB(
            responsive.pageX,
            first ? 0 : sectionGap(responsive),
            responsive.pageX,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionHeader(title: label, action: '${entries.length}'),
              SizedBox(height: sectionHeaderGap(responsive)),
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) SizedBox(height: responsive.s(12)),
                _NotificationCard(
                  entry: entries[i],
                  onTap: () => _open(entries[i].notification),
                  onDismiss: () => _dismiss(entries[i].notification),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationsLoading extends StatelessWidget {
  const _NotificationsLoading();

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: responsive.pageX),
      child: Column(
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) SizedBox(height: responsive.s(12)),
            Container(
              height: responsive.s(88).clamp(80.0, 104.0).toDouble(),
              decoration: BoxDecoration(
                color: colors.surfaceAlt,
                borderRadius: BorderRadius.circular(responsive.radius(22)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NotificationsEmpty extends StatelessWidget {
  const _NotificationsEmpty();

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final discSize = responsive.s(76).clamp(68.0, 84.0).toDouble();

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: responsive.pageX),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: discSize,
              height: discSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.accentAlpha(0.08),
                border: Border.all(color: colors.accentAlpha(0.16)),
              ),
              child: Icon(
                Icons.notifications_none_rounded,
                color: colors.accent,
                size: discSize * 0.42,
              ),
            ),
            SizedBox(height: responsive.s(18)),
            Text(
              'Nothing needs your attention',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: colors.ink,
                fontSize: responsive.font(16),
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: responsive.s(7)),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                'Safety flags, dose reminders and refill alerts appear here as '
                'soon as your data raises one.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: colors.inkSoft,
                  fontSize: responsive.font(12.8),
                  fontWeight: FontWeight.w400,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One notification.
///
/// Read and unread keep the identical geometry, so the feed settles as it is
/// worked through instead of items jumping about. Unread is carried by a filled
/// glyph plate and a tinted card; read drops to a pale plate on a plain card.
class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.entry,
    required this.onTap,
    required this.onDismiss,
  });

  final NotificationEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final item = entry.notification;
    final accent = _toneColor(colors, item);
    final unread = entry.unread;
    final plate = responsive.s(42).clamp(38.0, 50.0).toDouble();

    return Dismissible(
      key: ValueKey('notification-${item.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: responsive.s(22)),
        decoration: BoxDecoration(
          color: colors.dangerAlpha(0.10),
          borderRadius: BorderRadius.circular(responsive.radius(22)),
        ),
        child: Icon(
          Icons.delete_rounded,
          color: colors.danger,
          size: responsive.icon(20),
        ),
      ),
      child: Semantics(
        button: true,
        label: '${item.title}. ${item.body}',
        child: SurfaceCard(
          onTap: onTap,
          accent: unread ? accent : null,
          padding: EdgeInsets.all(responsive.s(16)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: plate,
                height: plate,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: unread ? accent : accent.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(responsive.radius(14)),
                ),
                child: Icon(
                  _icon(item.kind),
                  color: unread ? MedGuardPalette.pureWhite : accent,
                  size: responsive.icon(20),
                ),
              ),
              SizedBox(width: responsive.s(14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            item.title,
                            style: GoogleFonts.inter(
                              color: colors.ink,
                              fontSize: responsive.font(14.2),
                              fontWeight: unread
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              letterSpacing: -0.15,
                              height: 1.25,
                            ),
                          ),
                        ),
                        SizedBox(width: responsive.s(10)),
                        Padding(
                          padding: EdgeInsets.only(top: responsive.s(1)),
                          child: Text(
                            _relativeTime(item.when),
                            style: GoogleFonts.inter(
                              color: colors.inkMute,
                              fontSize: responsive.font(11.6),
                              fontWeight: FontWeight.w500,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: responsive.s(5)),
                    Text(
                      item.body,
                      style: GoogleFonts.inter(
                        color: colors.inkSoft,
                        fontSize: responsive.font(12.8),
                        fontWeight: FontWeight.w400,
                        height: 1.45,
                      ),
                    ),
                    if (item.actionLabel != null) ...[
                      SizedBox(height: responsive.s(12)),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: responsive.s(12),
                          vertical: responsive.s(7),
                        ),
                        decoration: BoxDecoration(
                          color: colors.accentAlpha(0.10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item.actionLabel!,
                              style: GoogleFonts.inter(
                                color: colors.accent,
                                fontSize: responsive.font(12),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: responsive.s(4)),
                            Icon(
                              Icons.arrow_forward_rounded,
                              color: colors.accent,
                              size: responsive.icon(14),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "12m", "3h", "2d" — a compact age, because a notification feed is read by
  /// recency and a full timestamp is noise at this size.
  static String _relativeTime(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return '${(diff.inDays / 7).floor()}w';
  }

  static IconData _icon(NotificationKind kind) => switch (kind) {
    NotificationKind.interaction => Icons.warning_amber_rounded,
    NotificationKind.allergy => Icons.dangerous_rounded,
    NotificationKind.duplicate => Icons.layers_rounded,
    NotificationKind.dose => Icons.local_pharmacy_rounded,
    NotificationKind.refill => Icons.inventory_2_rounded,
    NotificationKind.conflict => Icons.schedule_rounded,
    NotificationKind.setup => Icons.add_circle_rounded,
    NotificationKind.clear => Icons.verified_rounded,
  };

  static Color _toneColor(MedGuardColors colors, AppNotification item) {
    return switch (item.priority) {
      NotificationPriority.critical => colors.danger,
      NotificationPriority.attention => colors.warning,
      NotificationPriority.info =>
        item.kind == NotificationKind.clear ? colors.accent : colors.inkMute,
    };
  }
}
