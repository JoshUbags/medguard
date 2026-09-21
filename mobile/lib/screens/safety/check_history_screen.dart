import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/check_log_entry.dart';
import '../../models/safety_report.dart';
import '../../models/user_medication.dart';
import '../../services/guest_mode_service.dart';
import '../../services/user_data_service.dart';
import '../../theme/medguard_colors.dart';
import '../../theme/medguard_responsive.dart';
import '../../widgets/common/detail_page.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/item_row.dart';
import '../../widgets/common/modal_sheet.dart';
import '../../widgets/common/morph_loader.dart';
import '../../widgets/common/section_header.dart';
import '../../widgets/common/sign_in_wall.dart';
import '../../widgets/common/surface_card.dart';
import 'safety_report_screen.dart';

/// Chronological audit trail of every InteractionChecker run. Tapping a row
/// re-runs the analysis with the current medication state so the user can
/// see whether the regimen has changed since the snapshot.
///
/// This is the account layer, and the clearest example of what an account is
/// FOR. A single check is a question about right now and needs nothing but the
/// phone; a trail of them is a record — the thing you hand a pharmacist, the
/// thing that has to survive this handset. So a guest still runs every check,
/// and every check is still written down; what waits for sign-in is the record
/// they add up to. Nothing is discarded in the meantime, and the wall says how
/// much is already banked, because an incentive you can count is honest and a
/// vague one is not.
class CheckHistoryScreen extends StatefulWidget {
  const CheckHistoryScreen({super.key});

  static const String routeName = '/safety/history';

  @override
  State<CheckHistoryScreen> createState() => _CheckHistoryScreenState();
}

class _CheckHistoryScreenState extends State<CheckHistoryScreen> {
  List<CheckLogEntry> _entries = const [];
  bool _loading = true;

  String get _userId {
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? 'local-device';
    } catch (_) {
      return 'local-device';
    }
  }

  bool get _locked => GuestModeService.instance.enabled.value;

  @override
  void initState() {
    super.initState();
    _load();
    UserDataService.instance.checkHistoryRevision.addListener(_load);
    // Signing in from the wall below unlocks this page in place — the record
    // is already loaded, so it should appear without a second navigation.
    GuestModeService.instance.enabled.addListener(_onGuestModeChanged);
  }

  @override
  void dispose() {
    UserDataService.instance.checkHistoryRevision.removeListener(_load);
    GuestModeService.instance.enabled.removeListener(_onGuestModeChanged);
    super.dispose();
  }

  void _onGuestModeChanged() {
    if (!mounted) return;
    setState(() {});
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final history = await UserDataService.instance.getCheckHistory(_userId);
      if (!mounted) return;
      setState(() {
        _entries = history;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _rerun(CheckLogEntry entry) async {
    // Reconstruct UserMedication stubs from the stored snapshot so the safety
    // screen can re-run the analysis with today's allergy + medication list.
    final pairs = <UserMedication>[];
    for (var i = 0; i < entry.drugIds.length; i++) {
      final id = entry.drugIds[i];
      final name = i < entry.drugNames.length ? entry.drugNames[i] : '#$id';
      pairs.add(
        UserMedication(
          id: 0,
          userId: entry.userId,
          drugId: id,
          drugName: name,
          atcCode: null,
          addedAt: entry.createdAt,
        ),
      );
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            SafetyReportScreen(userId: entry.userId, medications: pairs),
      ),
    );
  }

  Future<void> _clear() async {
    final confirm = await showConfirmSheet(
      context: context,
      title: 'Clear check history?',
      message:
          'Removes every saved safety-report snapshot on this device. Your '
          'medicines and allergies are untouched, and you can run a fresh '
          'check at any time.',
      confirmLabel: 'Clear history',
      destructive: true,
      icon: Icons.delete_sweep_rounded,
    );
    if (confirm != true) return;
    await UserDataService.instance.clearCheckHistory(_userId);
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);

    return DetailPage(
      title: 'Interaction history',
      subtitle: _subtitle(),
      actions: [
        if (_entries.isNotEmpty && !_locked)
          DetailPageAction(
            icon: Icons.delete_sweep_rounded,
            label: 'Clear',
            semanticLabel: 'Clear history',
            tint: context.colors.inkSoft,
            onTap: _clear,
          ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: responsive.constrain(
            Padding(
              padding: EdgeInsets.symmetric(horizontal: responsive.pageX),
              // The lock is known synchronously, so the wall is drawn straight
              // away rather than behind a spinner for a record it is not going
              // to show. The count of what is waiting fills in underneath it
              // when the read lands — and if the read never lands, the wall is
              // still complete without it.
              child: _locked
                  ? SignInWall(
                      icon: Icons.history_rounded,
                      title: 'Your history lives with your account',
                      message:
                          'A safety check answers a question about today. The '
                          'trail of them is your record — what you show a '
                          'pharmacist, and what has to outlast this phone. '
                          'Sign in and it opens here.',
                      waiting: _entries.isEmpty
                          ? null
                          : '${_entries.length} '
                                '${_entries.length == 1 ? 'check is' : 'checks are'}'
                                ' already saved on this device',
                    )
                  : _loading
                  ? const LoadingView(message: 'Reading your history')
                  : _entries.isEmpty
                  ? const EmptyState(
                      icon: Icons.history_rounded,
                      title: 'No safety checks yet',
                      message:
                          'Review your medicines from the Interactions tab and '
                          'each result is saved here, with the medicines it '
                          'covered.',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _buildGroupedEntries(responsive),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  String _subtitle() {
    if (_locked) {
      // Says plainly that running checks is not what is gated — only the trail
      // they build up. A wall that implies the feature is off would be a lie.
      return 'Checks you run are saved here and open when you sign in.';
    }
    if (_entries.isEmpty) return 'Every safety check you run is recorded here.';
    return '${_entries.length} '
        '${_entries.length == 1 ? 'check' : 'checks'}, newest first.';
  }

  /// The trail under date headings (Today / Yesterday / date), each a standard
  /// section heading with its count, so the page reads like every other feed.
  List<Widget> _buildGroupedEntries(MedGuardResponsive responsive) {
    final groups = <String, List<CheckLogEntry>>{};
    for (final entry in _entries) {
      final label = _dateGroupLabel(entry.createdAt.toLocal());
      groups.putIfAbsent(label, () => []).add(entry);
    }

    final widgets = <Widget>[];
    for (final group in groups.entries) {
      final count = group.value.length;
      if (widgets.isNotEmpty) {
        widgets.add(SizedBox(height: sectionGap(responsive)));
      }
      widgets
        ..add(
          SectionHeader(
            title: group.key,
            action: '$count ${count == 1 ? 'check' : 'checks'}',
          ),
        )
        ..add(SizedBox(height: sectionHeaderGap(responsive)));
      for (var i = 0; i < count; i++) {
        if (i > 0) widgets.add(SizedBox(height: responsive.s(12)));
        final entry = group.value[i];
        widgets.add(_HistoryCard(entry: entry, onTap: () => _rerun(entry)));
      }
    }
    return widgets;
  }

  String _dateGroupLabel(DateTime local) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(local.year, local.month, local.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    final m = _months[local.month - 1];
    return local.year == now.year
        ? '${local.day} $m'
        : '${local.day} $m ${local.year}';
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// One saved check: the verdict it reached, when, how, over which medicines,
/// and what it found.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.entry, required this.onTap});

  final CheckLogEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    // The app's three-tier vocabulary (Low / Moderate / High), plus an "All
    // clear" state when nothing was flagged — worded exactly as the safety
    // report words its verdict.
    final (label, tone, icon) = switch (entry.overallRisk) {
      OverallRisk.safe => ('All clear', colors.accent, Icons.verified_rounded),
      OverallRisk.caution => (
        'Low risk',
        colors.accent,
        Icons.check_circle_rounded,
      ),
      OverallRisk.warning => (
        'Moderate risk',
        colors.warning,
        Icons.warning_amber_rounded,
      ),
      OverallRisk.danger => (
        'High risk',
        colors.danger,
        Icons.report_problem_rounded,
      ),
    };
    final source = entry.source == 'ml' ? 'On-device model' : 'Clinical rules';

    final findings = <({String text, Color? tone})>[
      if (entry.interactionCount > 0)
        (
          text: _count(entry.interactionCount, 'interaction', 'interactions'),
          tone: null,
        ),
      if (entry.allergyCount > 0)
        (
          text: _count(entry.allergyCount, 'allergy match', 'allergy matches'),
          tone: colors.danger,
        ),
      if (entry.duplicateCount > 0)
        (
          text: _count(entry.duplicateCount, 'duplicate', 'duplicates'),
          tone: null,
        ),
      if (entry.foodCount > 0)
        (
          text: _count(entry.foodCount, 'food advisory', 'food advisories'),
          tone: null,
        ),
      if (entry.totalFindings == 0) (text: 'No findings', tone: colors.accent),
    ];

    return Semantics(
      button: true,
      label: '$label, ${_time(entry.createdAt)}. Run this check again.',
      child: SurfaceCard(
        onTap: onTap,
        padding: EdgeInsets.all(responsive.s(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ItemGlyph(icon: icon, tint: tone),
                SizedBox(width: responsive.s(14)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.inter(
                          color: colors.ink,
                          fontSize: responsive.font(14.6),
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                          height: 1.2,
                        ),
                      ),
                      SizedBox(height: responsive.s(3)),
                      Text(
                        '${_time(entry.createdAt)} · $source',
                        style: GoogleFonts.inter(
                          color: colors.inkMute,
                          fontSize: responsive.font(12.2),
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: responsive.s(8)),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.inkMute,
                  size: responsive.icon(20),
                ),
              ],
            ),
            SizedBox(height: responsive.s(12)),
            Text(
              entry.drugNames.isEmpty
                  ? _count(entry.drugIds.length, 'medicine', 'medicines')
                  : entry.drugNames.join(', '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                color: colors.inkSoft,
                fontSize: responsive.font(12.8),
                fontWeight: FontWeight.w500,
                height: 1.45,
              ),
            ),
            SizedBox(height: responsive.s(12)),
            Wrap(
              spacing: responsive.s(6),
              runSpacing: responsive.s(6),
              children: [
                for (final finding in findings)
                  _FindingChip(text: finding.text, tone: finding.tone),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _count(int n, String one, String many) =>
      '$n ${n == 1 ? one : many}';

  static String _time(DateTime utc) {
    final local = utc.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
  }
}

/// A count of one kind of finding. Neutral unless the finding carries its own
/// weight (an allergy match), so a card is not a row of competing colours.
class _FindingChip extends StatelessWidget {
  const _FindingChip({required this.text, this.tone});

  final String text;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final color = tone;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.s(10),
        vertical: responsive.s(5),
      ),
      decoration: BoxDecoration(
        color: color?.withValues(alpha: 0.10) ?? colors.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          color: color ?? colors.inkSoft,
          fontSize: responsive.font(11.6),
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
    );
  }
}
