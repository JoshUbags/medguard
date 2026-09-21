import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/managed_profile.dart';
import '../../services/active_profile_service.dart';
import '../../services/auth_profile_preferences.dart';
import '../../services/dose_service.dart';
import '../../services/guest_data_migration.dart';
import '../../services/guest_mode_service.dart';
import '../../services/login_activity_service.dart';
import '../../services/notification_preferences.dart';
import '../../services/session_service.dart';
import '../../services/user_data_service.dart';
import '../../theme/medguard_colors.dart';
import '../../theme/medguard_responsive.dart';
import '../../widgets/common/account_avatar.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_notice.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/detail_page.dart';
import '../../widgets/common/modal_sheet.dart';
import '../../widgets/common/morph_loader.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/pressable.dart';
import '../../widgets/common/sign_in_wall.dart';
import '../../widgets/common/surface_card.dart';
import '../allergies/allergy_management_screen.dart';
import '../auth/guest_handoff.dart';
import '../dose/dose_screen.dart';
import '../emergency/emergency_screen.dart';
import '../foods/food_management_screen.dart';
import '../medications/medications_screen.dart';
import '../safety/check_history_screen.dart';
import '../settings/caregiver_profiles_screen.dart';
import '../settings/settings_screen.dart';

/// Profile — what MedGuard KNOWS about this person, as opposed to Settings,
/// which is what they have told it to do.
///
/// Everything here is a fact about the user's record: who they are, what is in
/// that record, how consistently they take their doses, who else they manage.
/// Nothing on this page is a preference — those all live in [SettingsScreen],
/// reachable from the gear in the header.
///
/// The page runs identity → record → activity → context. That order is
/// deliberate: the record section is the only thing here that can prompt an
/// action which makes the rest of the app more accurate, so it sits high.
///
/// Each area appears EXACTLY once. The record's four areas used to be described
/// by three separate blocks — a row of counts, a completeness checklist, and a
/// pair of shortcut tiles — so "medicines" was stated three times and the
/// emergency card had two entrances two sections apart. One section now carries
/// the count, the completeness state and the way in for each area.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  static const String routeName = '/profile';

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final user = _currentUser();
    final displayName = AuthProfilePreferences.resolveDisplayName(
      firebaseDisplayName: user?.displayName?.trim(),
      fallback: 'MedGuard user',
    );
    final email = user?.email?.trim();
    final gap = SizedBox(height: sectionGap(responsive));

    return DetailPage(
      title: 'Profile',
      subtitle: 'Your record, and how complete it is.',
      leadingActions: [
        DetailPageAction(
          icon: Icons.settings_rounded,
          semanticLabel: 'Settings',
          onTap: () =>
              Navigator.of(context).pushNamed(SettingsScreen.routeName),
        ),
      ],
      slivers: [
        SliverToBoxAdapter(
          child: responsive.constrain(
            Padding(
              padding: EdgeInsets.symmetric(horizontal: responsive.pageX),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _IdentityCard(
                    name: displayName,
                    email: email?.isNotEmpty == true
                        ? email!
                        : 'Local safety workspace',
                    photoUrl: headerPhotoUrl(),
                    onEditName: _editName,
                  ),
                  gap,
                  const _AccountSection(),
                  const _RecordSection(),
                  gap,
                  const _ActivitySection(),
                  gap,
                  const _CareProfileSection(),
                  const _CareCircleSection(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  User? _currentUser() {
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      return null;
    }
  }

  Future<void> _editName() async {
    final user = _currentUser();
    final controller = TextEditingController(
      text: AuthProfilePreferences.resolveDisplayName(
        firebaseDisplayName: user?.displayName?.trim(),
        fallback: '',
      ),
    );

    final saved = await showModalSheet<bool>(
      context: context,
      title: 'Your name',
      subtitle:
          'Used on the home screen and on any report you share with a '
          'pharmacist or clinician.',
      confirmLabel: 'Save',
      onConfirm: () => controller.text.trim().isNotEmpty,
      builder: (_) => AppTextField(
        controller: controller,
        label: 'Display name',
        icon: Icons.person_rounded,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
      ),
    );
    if (saved != true || !mounted) return;

    final name = controller.text.trim();
    // Cached locally first so the change is visible immediately even if the
    // Firebase write is slow or the device is offline; the remote update then
    // catches up in the background.
    AuthProfilePreferences.cacheDisplayName(name);
    try {
      await user?.updateDisplayName(name);
    } catch (_) {
      // Offline or signed out — the local cache still drives the UI.
    }
    if (!mounted) return;
    setState(() {});
    showAppNotice(context, 'Name updated.', type: AppNoticeType.success);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Identity
// ─────────────────────────────────────────────────────────────────────────────

/// The person, as a card: avatar, name, account, and the one thing that is
/// editable about them here.
class _IdentityCard extends StatelessWidget {
  const _IdentityCard({
    required this.name,
    required this.email,
    required this.photoUrl,
    required this.onEditName,
  });

  final String name;
  final String email;
  final String? photoUrl;
  final VoidCallback onEditName;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final avatarSize = responsive.s(64).clamp(58.0, 76.0).toDouble();

    return SurfaceCard(
      padding: EdgeInsets.all(responsive.s(18)),
      child: Row(
        children: [
          // The account's own picture, at the largest size it appears anywhere
          // in the app — this is the one screen that is ABOUT the account.
          AccountAvatar(
            name: name,
            photoUrl: photoUrl,
            size: avatarSize,
            avatarKey: const ValueKey('profile-avatar'),
          ),
          SizedBox(width: responsive.s(16)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: colors.ink,
                    fontSize: responsive.font(18),
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    height: 1.2,
                  ),
                ),
                SizedBox(height: responsive.s(3)),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: colors.inkMute,
                    fontSize: responsive.font(12.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: responsive.s(10)),
                Pressable(
                  onTap: onEditName,
                  pressScale: 0.96,
                  semanticLabel: 'Edit name',
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: responsive.s(12),
                      vertical: responsive.s(6),
                    ),
                    decoration: BoxDecoration(
                      color: colors.accentAlpha(0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.edit_rounded,
                          size: responsive.icon(13),
                          color: colors.accent,
                        ),
                        SizedBox(width: responsive.s(5)),
                        Text(
                          'Edit name',
                          style: GoogleFonts.inter(
                            color: colors.accent,
                            fontSize: responsive.font(11.8),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Account
// ─────────────────────────────────────────────────────────────────────────────

/// The state of the account itself — and the only section on this page that
/// disappears entirely when there is nothing to say.
///
/// It covers the two moments where the guest/account boundary is visible:
///
///  * **No account.** Says what is already working (all of it) and what an
///    account adds, so the offer is a description rather than a nag.
///  * **Signed in, with a local record left behind.** Someone who chose "Not
///    now" during the hand-over needs a second way to finish it — otherwise
///    that answer silently strands a medication list on the device forever.
///    Both endings live here: adopt it, or delete it deliberately.
class _AccountSection extends StatefulWidget {
  const _AccountSection();

  @override
  State<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<_AccountSection> {
  GuestRecordSummary _leftover = GuestRecordSummary.empty;
  bool _busy = false;

  bool get _guest => GuestModeService.instance.enabled.value;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLeftover());
    GuestModeService.instance.enabled.addListener(_onGuestModeChanged);
  }

  @override
  void dispose() {
    GuestModeService.instance.enabled.removeListener(_onGuestModeChanged);
    super.dispose();
  }

  void _onGuestModeChanged() {
    if (!mounted) return;
    setState(() {});
    unawaited(_loadLeftover());
  }

  /// Only meaningful once signed in: while in guest mode the local rows ARE the
  /// user's record, not something left over from a previous life.
  Future<void> _loadLeftover() async {
    if (_guest) {
      if (mounted) setState(() => _leftover = GuestRecordSummary.empty);
      return;
    }
    final summary = await GuestDataMigration.instance.summarise();
    if (!mounted) return;
    setState(() => _leftover = summary);
  }

  Future<void> _adopt() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final moved = await GuestDataMigration.instance.adopt(
        GuestDataMigration.currentAccountId(),
      );
      if (!mounted) return;
      showAppNotice(
        context,
        moved > 0
            ? 'Added to your account.'
            : 'Your account already had all of it.',
        type: AppNoticeType.success,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _loadLeftover();
  }

  Future<void> _discard() async {
    if (_busy) return;
    final removed = await confirmDiscardGuestRecord(context);
    if (removed) await _loadLeftover();
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final gap = SizedBox(height: sectionGap(responsive));

    if (_guest) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_buildGuestCard(responsive), gap],
      );
    }
    if (_leftover.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [_buildLeftoverCard(responsive), gap],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildGuestCard(MedGuardResponsive responsive) {
    final colors = context.colors;

    return SectionBlock(
      title: 'Account',
      subtitle:
          'MedGuard is running entirely on this phone. Nothing is missing — '
          'an account is what makes the record survive it.',
      action: 'Local only',
      card: false,
      child: SurfaceCard(
        padding: EdgeInsets.all(responsive.s(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: responsive.s(42),
                  height: responsive.s(42),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.accentAlpha(0.12),
                    borderRadius: BorderRadius.circular(responsive.radius(14)),
                  ),
                  child: Icon(
                    Icons.phone_iphone_rounded,
                    color: colors.accent,
                    size: responsive.icon(20),
                  ),
                ),
                SizedBox(width: responsive.s(14)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'No account',
                        style: GoogleFonts.inter(
                          color: colors.ink,
                          fontSize: responsive.font(14),
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                      SizedBox(height: responsive.s(3)),
                      Text(
                        'Every safety check runs offline, on this device.',
                        style: GoogleFonts.inter(
                          color: colors.inkMute,
                          fontSize: responsive.font(12.2),
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: responsive.s(14)),
            const _AccountPerk(
              icon: Icons.history_rounded,
              text: 'Your check history opens up',
            ),
            const _AccountPerk(
              icon: Icons.diversity_3_rounded,
              text: 'Manage profiles for people you care for',
            ),
            const _AccountPerk(
              icon: Icons.restore_rounded,
              text: 'Your record survives losing this phone',
            ),
            SizedBox(height: responsive.s(14)),
            AppButton(
              label: 'Sign in',
              icon: Icons.login_rounded,
              onTap: () => openSignIn(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftoverCard(MedGuardResponsive responsive) {
    final colors = context.colors;

    return SectionBlock(
      title: 'Local record',
      subtitle:
          'Saved on this device before you signed in, and not part of your '
          'account yet.',
      action: 'Not linked',
      card: false,
      child: SurfaceCard(
        padding: EdgeInsets.all(responsive.s(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: responsive.s(42),
                  height: responsive.s(42),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.accentAlpha(0.12),
                    borderRadius: BorderRadius.circular(responsive.radius(14)),
                  ),
                  child: Icon(
                    Icons.inventory_2_rounded,
                    color: colors.accent,
                    size: responsive.icon(20),
                  ),
                ),
                SizedBox(width: responsive.s(14)),
                Expanded(
                  child: Text(
                    _leftover.describe(),
                    style: GoogleFonts.inter(
                      color: colors.ink,
                      fontSize: responsive.font(13.4),
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: responsive.s(14)),
            AppButton(
              label: 'Bring it into my account',
              icon: Icons.move_up_rounded,
              loading: _busy,
              onTap: _busy ? null : _adopt,
            ),
            SizedBox(height: responsive.s(8)),
            AppButton(
              label: 'Delete it',
              variant: AppButtonVariant.secondary,
              onTap: _busy ? null : _discard,
            ),
          ],
        ),
      ),
    );
  }
}

/// One line of what an account adds. A plain icon-and-text row, so the list
/// reads as facts rather than as marketing bullets.
class _AccountPerk extends StatelessWidget {
  const _AccountPerk({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Padding(
      padding: EdgeInsets.only(bottom: responsive.s(7)),
      child: Row(
        children: [
          Icon(icon, color: colors.accent, size: responsive.icon(15)),
          SizedBox(width: responsive.s(9)),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                color: colors.inkSoft,
                fontSize: responsive.font(12.4),
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The record
// ─────────────────────────────────────────────────────────────────────────────

/// One area of the user's record: how much of it there is, whether that counts
/// as filled in, and where to go to change it.
class _RecordArea {
  const _RecordArea({
    required this.icon,
    required this.label,
    required this.detail,
    required this.filled,
    required this.route,
  });

  final IconData icon;
  final String label;

  /// The live state of this area, in the user's terms — "4 saved", "None yet".
  final String detail;

  /// Whether the area counts toward a complete record.
  final bool filled;

  final String route;
}

/// What MedGuard is working from, and what it is still missing.
///
/// One block for both questions. They were two — a row of four counters and a
/// completeness checklist below it — which restated the same four facts in two
/// visual languages, and left the emergency card reachable only while it was
/// still incomplete. Here every area is always present, always tappable, and
/// carries its own count; the ring above them is the summary, not a second list.
class _RecordSection extends StatefulWidget {
  const _RecordSection();

  @override
  State<_RecordSection> createState() => _RecordSectionState();
}

class _RecordSectionState extends State<_RecordSection> {
  int? _medications;
  int? _allergies;
  int? _foods;
  int? _schedules;
  bool _hasEmergencyContact = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
    UserDataService.instance.medicationsRevision.addListener(_load);
    UserDataService.instance.allergiesRevision.addListener(_load);
    UserDataService.instance.foodsRevision.addListener(_load);
  }

  @override
  void dispose() {
    UserDataService.instance.medicationsRevision.removeListener(_load);
    UserDataService.instance.allergiesRevision.removeListener(_load);
    UserDataService.instance.foodsRevision.removeListener(_load);
    super.dispose();
  }

  /// One pass for all five areas. The counts and the completeness state used to
  /// be loaded by two separate widgets, which read the medication and allergy
  /// tables twice over on every visit to this page.
  Future<void> _load() async {
    final userId = _activeUserId();
    int? meds, allergies, foods, schedules;
    var hasContact = false;
    try {
      meds = (await UserDataService.instance.getUserMedications(userId)).length;
    } catch (_) {}
    try {
      allergies = (await UserDataService.instance.getUserAllergies(
        userId,
      )).length;
    } catch (_) {}
    try {
      foods = (await UserDataService.instance.getUserFoods(userId)).length;
    } catch (_) {}
    try {
      schedules = (await DoseService.instance.getSchedules(userId)).length;
    } catch (_) {}
    try {
      final contact = await NotificationPreferences.emergencyContactName();
      hasContact = contact != null && contact.isNotEmpty;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _medications = meds;
      _allergies = allergies;
      _foods = foods;
      _schedules = schedules;
      _hasEmergencyContact = hasContact;
      _loaded = true;
    });
  }

  /// "Checking…" until counted, [empty] at zero, otherwise [describe]'s phrase.
  /// A phrase builder rather than a noun to pluralise: appending an "s" is what
  /// produced "2 recordeds" and "3 saveds".
  static String _countLabel(
    int? value,
    String Function(int count) describe,
    String empty,
  ) {
    if (value == null) return 'Checking…';
    if (value == 0) return empty;
    return describe(value);
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    final areas = <_RecordArea>[
      _RecordArea(
        icon: Icons.medication_rounded,
        label: 'Medicines',
        detail: _countLabel(
          _medications,
          (n) => '$n ${n == 1 ? 'medicine' : 'medicines'} saved',
          'Nothing saved yet',
        ),
        filled: (_medications ?? 0) > 0,
        route: MedicationsScreen.routeName,
      ),
      _RecordArea(
        icon: Icons.dangerous_rounded,
        label: 'Allergies',
        detail: _countLabel(_allergies, (n) => '$n recorded', 'None recorded'),
        filled: (_allergies ?? 0) > 0,
        route: AllergyManagementScreen.routeName,
      ),
      _RecordArea(
        icon: Icons.restaurant_rounded,
        label: 'Foods and drinks',
        detail: _countLabel(_foods, (n) => '$n saved', 'None saved'),
        filled: (_foods ?? 0) > 0,
        route: FoodManagementScreen.routeName,
      ),
      _RecordArea(
        icon: Icons.event_repeat_rounded,
        label: 'Dose reminders',
        detail: _countLabel(
          _schedules,
          (n) => '$n ${n == 1 ? 'schedule' : 'schedules'}',
          'No schedule yet',
        ),
        filled: (_schedules ?? 0) > 0,
        route: DoseScreen.routeName,
      ),
      _RecordArea(
        icon: Icons.contact_emergency_rounded,
        label: 'Emergency card',
        detail: _hasEmergencyContact
            ? 'Next of kin on file'
            : 'No contact yet',
        filled: _hasEmergencyContact,
        route: EmergencyScreen.routeName,
      ),
    ];

    final done = areas.where((a) => a.filled).length;
    final complete = done == areas.length;

    return SectionBlock(
      title: 'Your record',
      subtitle: complete
          ? 'Complete — every check runs against your full record.'
          : 'The safety checks are only as good as what MedGuard knows '
                'about you.',
      // The trailing caption states the section's state at a glance, so the
      // page can be read without opening the card.
      action: !_loaded
          ? null
          : complete
          ? 'Complete'
          : '$done of ${areas.length}',
      card: false,
      child: SurfaceCard(
        padding: EdgeInsets.all(responsive.s(18)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Indeterminate until the record has actually been read. A
                // ring resting at 0% is a claim about the user's record, and
                // it must not be made before the record has been counted.
                _CompletenessRing(
                  percent: _loaded ? done / areas.length : null,
                  complete: complete,
                ),
                SizedBox(width: responsive.s(16)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        !_loaded
                            ? 'Checking your record'
                            : complete
                            ? 'Your record is complete'
                            : '$done of ${areas.length} areas filled in',
                        style: GoogleFonts.inter(
                          color: colors.ink,
                          fontSize: responsive.font(15),
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          letterSpacing: -0.2,
                        ),
                      ),
                      SizedBox(height: responsive.s(4)),
                      Text(
                        !_loaded
                            ? 'Reading what you have saved on this device.'
                            : complete
                            ? 'Nothing left to add. Every medicine you take '
                                  'is being checked.'
                            : 'Each one you finish makes every safety check '
                                  'more accurate.',
                        style: GoogleFonts.inter(
                          color: colors.inkSoft,
                          fontSize: responsive.font(12.4),
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // The rows are structure, not data, so they are present from the
            // first frame and fill their counts in as the reads land. Hiding
            // them behind a spinner made the page's tallest card jump twice on
            // every visit.
            for (final area in areas) ...[
              const CardDivider(),
              _RecordRow(area: area),
            ],
          ],
        ),
      ),
    );
  }
}

/// One record area, as a row: what it is, how much of it there is, and a way in.
class _RecordRow extends StatelessWidget {
  const _RecordRow({required this.area});

  final _RecordArea area;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    // Filled areas take the accent; an empty one drops to muted ink so the gaps
    // in the record are legible down the column without a second badge.
    final tint = area.filled ? colors.accent : colors.inkMute;
    final disc = responsive.s(34);

    return Pressable(
      onTap: () => Navigator.of(context).pushNamed(area.route),
      pressScale: 0.985,
      semanticLabel: '${area.label}. ${area.detail}',
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: responsive.s(3)),
        child: Row(
          children: [
            Container(
              width: disc,
              height: disc,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(responsive.radius(11)),
              ),
              child: Icon(area.icon, size: responsive.icon(18), color: tint),
            ),
            SizedBox(width: responsive.s(13)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    area.label,
                    style: GoogleFonts.inter(
                      color: colors.ink,
                      fontSize: responsive.font(13.8),
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: responsive.s(2)),
                  Text(
                    area.detail,
                    style: GoogleFonts.inter(
                      color: colors.inkMute,
                      fontSize: responsive.font(12),
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
              size: responsive.icon(18),
              color: colors.inkMute,
            ),
          ],
        ),
      ),
    );
  }
}

/// The completeness dial. A ring rather than a bar: a bar reads as *progress
/// through a task*, which implies the user is partway through something they
/// started. A ring reads as *a proportion of a whole*, which is what this is.
class _CompletenessRing extends StatelessWidget {
  const _CompletenessRing({required this.percent, required this.complete});

  /// Null until the record has been read, which draws the ring indeterminate
  /// and leaves the centre empty rather than asserting "0%".
  final double? percent;
  final bool complete;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final size = responsive.s(62).clamp(56.0, 72.0).toDouble();
    final value = percent;

    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (value == null)
            // A still, empty track — NOT an indeterminate spinner. The ring
            // sits inside a card that is already legible while the counts land,
            // and a perpetual animation on a page this static reads as though
            // something is stuck.
            CircularProgressIndicator(
              value: 0,
              strokeWidth: size * 0.085,
              strokeCap: StrokeCap.round,
              backgroundColor: colors.surfaceAlt,
              valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
            )
          else ...[
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: value),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, animated, _) => CircularProgressIndicator(
                value: animated,
                strokeWidth: size * 0.085,
                strokeCap: StrokeCap.round,
                backgroundColor: colors.surfaceAlt,
                valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
              ),
            ),
            if (complete)
              Icon(Icons.check_rounded, size: size * 0.42, color: colors.accent)
            else
              Text(
                '${(value * 100).round()}%',
                style: GoogleFonts.inter(
                  color: colors.ink,
                  fontSize: responsive.font(14),
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Activity
// ─────────────────────────────────────────────────────────────────────────────

/// What the user has actually been doing: doses kept, and safety checks run.
///
/// The 30-day strip matters more than the percentage. A single "84%" tells the
/// user nothing about WHERE the misses were; thirty small marks show at a glance
/// whether they had one bad week or are drifting steadily.
///
/// The day streak rides in this section's caption rather than in a counter tile
/// of its own — a streak is a statement about dose behaviour, and it belongs
/// beside the chart that explains it.
class _ActivitySection extends StatefulWidget {
  const _ActivitySection();

  @override
  State<_ActivitySection> createState() => _ActivitySectionState();
}

class _ActivitySectionState extends State<_ActivitySection> {
  static const int _days = 30;

  double? _rate;
  List<bool?>? _daily;
  int? _checks;
  int? _streak;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
    UserDataService.instance.checkHistoryRevision.addListener(_load);
  }

  @override
  void dispose() {
    UserDataService.instance.checkHistoryRevision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final userId = _activeUserId();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final from = today.subtract(const Duration(days: _days - 1));
    double? rate;
    List<bool?>? daily;
    int? checks;
    int? streak;

    try {
      // One pass over the dose tables gives both the headline rate and the
      // per-day cells — the same board the Dose screen renders from, so the
      // two screens can never disagree about the same window.
      final board = await DoseService.instance.loadBoard(
        userId,
        from: from,
        to: today,
        selectedDay: today,
        asOf: now,
      );
      rate = board.rangeSummary.scheduled == 0
          ? null
          : board.rangeSummary.percent;

      // One mark per day: true when everything due that day was adhered to,
      // false when something was missed or skipped, null when nothing was due.
      // A day with no doses is not a failure and must never be drawn as one.
      daily = [
        for (var i = _days - 1; i >= 0; i--)
          () {
            final day = today.subtract(Duration(days: i));
            final stat = board.dayStats[_dayKey(day)];
            if (stat == null || !stat.hasDoses) return null;
            final settled = stat.due - stat.pending;
            if (settled <= 0) return null;
            return stat.adhered >= settled;
          }(),
      ];
    } catch (_) {
      // Dose store unavailable — the empty state below covers it.
    }
    try {
      checks = (await UserDataService.instance.getCheckHistory(userId)).length;
    } catch (_) {}
    try {
      final days = await LoginActivityService.instance.activeDays();
      streak = LoginActivityService.streakFrom(days);
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _rate = rate;
      _daily = daily;
      _checks = checks;
      _streak = streak;
      _loaded = true;
    });
  }

  static String _dayKey(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final rate = _rate;
    final daily = _daily;
    final hasData = daily != null && daily.any((d) => d != null);
    final streak = _streak ?? 0;
    final checks = _checks;

    return SectionBlock(
      title: 'Your activity',
      subtitle: 'The last 30 days of scheduled doses, and every safety check '
          'you have run.',
      action: !_loaded || streak <= 0 ? null : '$streak-day streak',
      card: false,
      children: [
        SurfaceCard(
          padding: EdgeInsets.all(responsive.s(18)),
          child: !_loaded
              ? const LoadingView(padding: EdgeInsets.symmetric(vertical: 22))
              : !hasData
              ? const _AdherenceEmpty()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          rate == null ? '—' : '${(rate * 100).round()}%',
                          style: GoogleFonts.inter(
                            color: colors.ink,
                            fontSize: responsive.font(32),
                            fontWeight: FontWeight.w700,
                            height: 1.0,
                            letterSpacing: -1.2,
                          ),
                        ),
                        SizedBox(width: responsive.s(10)),
                        Padding(
                          padding: EdgeInsets.only(bottom: responsive.s(4)),
                          child: Text(
                            'of doses taken',
                            style: GoogleFonts.inter(
                              color: colors.inkMute,
                              fontSize: responsive.font(12.4),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: responsive.s(16)),
                    _AdherenceStrip(daily: daily),
                    SizedBox(height: responsive.s(12)),
                    Row(
                      children: [
                        _LegendDot(color: colors.accent, label: 'All taken'),
                        SizedBox(width: responsive.s(14)),
                        _LegendDot(color: colors.danger, label: 'Missed'),
                        SizedBox(width: responsive.s(14)),
                        _LegendDot(
                          color: colors.surfaceAlt,
                          label: 'Nothing due',
                        ),
                      ],
                    ),
                  ],
                ),
        ),
        SurfaceCard(
          onTap: () =>
              Navigator.of(context).pushNamed(CheckHistoryScreen.routeName),
          padding: EdgeInsets.all(responsive.s(16)),
          child: Row(
            children: [
              Container(
                width: responsive.s(42),
                height: responsive.s(42),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.accentAlpha(0.12),
                  borderRadius: BorderRadius.circular(responsive.radius(14)),
                ),
                child: Icon(
                  Icons.fact_check_rounded,
                  color: colors.accent,
                  size: responsive.icon(20),
                ),
              ),
              SizedBox(width: responsive.s(14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Check history',
                      style: GoogleFonts.inter(
                        color: colors.ink,
                        fontSize: responsive.font(14),
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: responsive.s(3)),
                    Text(
                      checks == null
                          ? 'Every safety check you have run'
                          : checks == 0
                          ? 'No checks run yet'
                          : '$checks check${checks == 1 ? '' : 's'} run',
                      style: GoogleFonts.inter(
                        color: colors.inkMute,
                        fontSize: responsive.font(12.2),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colors.inkMute,
                size: responsive.icon(20),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AdherenceStrip extends StatelessWidget {
  const _AdherenceStrip({required this.daily});

  final List<bool?> daily;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return SizedBox(
      height: responsive.s(34),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < daily.length; i++) ...[
            if (i > 0) SizedBox(width: responsive.s(2.5)),
            Expanded(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Duration(milliseconds: 300 + i * 12),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) => Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(heightFactor: t, child: child),
                ),
                child: Container(
                  // A missed day is drawn SHORTER as well as red, so the
                  // pattern is legible without relying on colour alone.
                  height: switch (daily[i]) {
                    true => responsive.s(34),
                    false => responsive.s(17),
                    null => responsive.s(9),
                  },
                  decoration: BoxDecoration(
                    color: switch (daily[i]) {
                      true => colors.accent,
                      false => colors.danger,
                      null => colors.surfaceAlt,
                    },
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: responsive.s(7),
          height: responsive.s(7),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        SizedBox(width: responsive.s(5)),
        Text(
          label,
          style: GoogleFonts.inter(
            color: context.colors.inkMute,
            fontSize: responsive.font(10.8),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _AdherenceEmpty extends StatelessWidget {
  const _AdherenceEmpty();

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'No dose history yet',
          style: GoogleFonts.inter(
            color: colors.ink,
            fontSize: responsive.font(14.4),
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: responsive.s(5)),
        Text(
          'Once you set a reminder and start marking doses, your last 30 days '
          'will be charted here.',
          style: GoogleFonts.inter(
            color: colors.inkSoft,
            fontSize: responsive.font(12.6),
            fontWeight: FontWeight.w500,
            height: 1.4,
          ),
        ),
        SizedBox(height: responsive.s(14)),
        Pressable(
          onTap: () => Navigator.of(context).pushNamed(DoseScreen.routeName),
          pressScale: 0.97,
          semanticLabel: 'Set a reminder',
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: responsive.s(16),
              vertical: responsive.s(9),
            ),
            decoration: BoxDecoration(
              color: colors.accentAlpha(0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'Set a reminder',
              style: GoogleFonts.inter(
                color: colors.accent,
                fontSize: responsive.font(12.4),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sign-up care profile
// ─────────────────────────────────────────────────────────────────────────────

/// What the user told MedGuard about themselves when they signed up.
///
/// These answers already shape the app — the reminder style, which safety
/// checks are emphasised — so showing them back is not decoration: it is the
/// only place a user can see WHY the app behaves the way it does for them, and
/// notice when an answer has gone out of date.
///
/// Renders nothing at all when there is no captured context (an account created
/// before the questions existed), rather than an empty card explaining its own
/// emptiness. The trailing [SizedBox] in the page's column is why this widget
/// owns the gap BELOW it rather than the page doing so: an absent section must
/// not leave a double gap behind.
class _CareProfileSection extends StatefulWidget {
  const _CareProfileSection();

  @override
  State<_CareProfileSection> createState() => _CareProfileSectionState();
}

class _CareProfileSectionState extends State<_CareProfileSection> {
  SignupProfileContext? _context;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    SignupProfileContext? loaded;
    try {
      loaded = await AuthProfilePreferences.load();
    } catch (_) {
      // Preferences unavailable — the section simply does not appear.
    }
    if (!mounted) return;
    setState(() {
      _context = loaded;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final profile = _context;
    if (!_loaded || profile == null) return const SizedBox.shrink();

    final rows = <({IconData icon, String label, String value})>[
      if (profile.careTarget.isNotEmpty)
        (
          icon: Icons.people_alt_rounded,
          label: 'Managing for',
          value: profile.careTarget,
        ),
      if (profile.medicationLoad.isNotEmpty)
        (
          icon: Icons.format_list_numbered_rounded,
          label: 'Medication load',
          value: profile.medicationLoad,
        ),
      if (profile.safetyFocus.isNotEmpty)
        (
          icon: Icons.shield_rounded,
          label: 'Safety focus',
          value: profile.safetyFocus,
        ),
      if (profile.healthDetails.isNotEmpty)
        (
          icon: Icons.monitor_heart_rounded,
          label: 'Health details',
          value: profile.healthDetails,
        ),
      if (profile.reminderPreference.isNotEmpty)
        (
          icon: Icons.notifications_active_rounded,
          label: 'Reminder style',
          value: profile.reminderPreference,
        ),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionBlock(
          title: 'Your care profile',
          subtitle: 'The answers you gave when you set MedGuard up. They are '
              'what tune the reminders and the checks to you.',
          action: '${rows.length} answer${rows.length == 1 ? '' : 's'}',
          card: false,
          child: SurfaceCard(
            padding: EdgeInsets.symmetric(
              horizontal: responsive.s(16),
              vertical: responsive.s(6),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) CardDivider(indent: responsive.s(46)),
                  _CareProfileRow(
                    icon: rows[i].icon,
                    label: rows[i].label,
                    value: rows[i].value,
                  ),
                ],
              ],
            ),
          ),
        ),
        SizedBox(height: sectionGap(responsive)),
      ],
    );
  }
}

/// One captured answer.
///
/// Icon, then the question, then the answer beneath it. The answers used to sit
/// in a fixed 112pt label column with the value squeezed into whatever was left,
/// so a long answer wrapped into a narrow ragged block while short ones left
/// half the card empty. Stacked, every answer gets the full width of the card.
class _CareProfileRow extends StatelessWidget {
  const _CareProfileRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final disc = responsive.s(34);

    return Padding(
      padding: EdgeInsets.symmetric(vertical: responsive.s(11)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: disc,
            height: disc,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: colors.accentAlpha(0.11),
              borderRadius: BorderRadius.circular(responsive.radius(11)),
            ),
            child: Icon(
              icon,
              size: responsive.icon(18),
              color: colors.accent,
            ),
          ),
          SizedBox(width: responsive.s(13)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: colors.inkMute,
                    fontSize: responsive.font(11.6),
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    letterSpacing: 0.2,
                  ),
                ),
                SizedBox(height: responsive.s(3)),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    color: colors.ink,
                    fontSize: responsive.font(13.4),
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Care circle
// ─────────────────────────────────────────────────────────────────────────────

/// Who this device tracks. Shows the ACTIVE profile prominently, because the
/// rest of the app silently follows it — a caregiver looking at Home needs to
/// be able to find out whose regimen they are looking at.
///
/// Account-only, and for a structural reason rather than a commercial one: a
/// managed profile's id embeds its owner's, so one created against the
/// local-device fixture could not follow the caregiver into an account later.
/// Building a dependent's medication list on a foundation that cannot be moved
/// is a worse outcome than being asked to sign in first.
class _CareCircleSection extends StatefulWidget {
  const _CareCircleSection();

  @override
  State<_CareCircleSection> createState() => _CareCircleSectionState();
}

class _CareCircleSectionState extends State<_CareCircleSection> {
  late Future<List<ManagedProfile>> _future;

  bool get _locked => GuestModeService.instance.enabled.value;

  @override
  void initState() {
    super.initState();
    _future = _load();
    UserDataService.instance.profilesRevision.addListener(_reload);
    GuestModeService.instance.enabled.addListener(_reload);
  }

  @override
  void dispose() {
    UserDataService.instance.profilesRevision.removeListener(_reload);
    GuestModeService.instance.enabled.removeListener(_reload);
    super.dispose();
  }

  Future<List<ManagedProfile>> _load() async {
    try {
      return await UserDataService.instance.getManagedProfiles(
        SessionService.instance.identity.value.ownerUserId,
      );
    } catch (_) {
      return const [];
    }
  }

  void _reload() {
    if (!mounted) return;
    setState(() => _future = _load());
  }

  void _open() {
    if (_locked) {
      openSignIn(context);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CaregiverProfilesScreen(
          ownerId: SessionService.instance.identity.value.ownerUserId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    if (_locked) return _buildLocked(responsive, colors);

    return ValueListenableBuilder<ActiveProfile>(
      valueListenable: ActiveProfileService.instance.current,
      builder: (context, active, _) {
        return FutureBuilder<List<ManagedProfile>>(
          future: _future,
          builder: (context, snapshot) {
            final profiles = snapshot.data ?? const <ManagedProfile>[];
            final activeName = active.isOwner
                ? 'Myself'
                : profiles
                          .where((p) => p.profileId == active.activeUserId)
                          .firstOrNull
                          ?.name ??
                      'Managed profile';

            return SectionBlock(
              title: 'Care circle',
              subtitle: profiles.isEmpty
                  ? 'Track medicines for someone you look after, kept '
                        'entirely separate from your own.'
                  : 'Everything you see in the app belongs to the active '
                        'profile.',
              action: profiles.isEmpty ? 'Add' : 'Manage',
              onAction: _open,
              card: false,
              child: SurfaceCard(
                onTap: _open,
                padding: EdgeInsets.all(responsive.s(16)),
                child: Row(
                  children: [
                    Container(
                      width: responsive.s(42),
                      height: responsive.s(42),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.accentAlpha(0.12),
                        borderRadius: BorderRadius.circular(
                          responsive.radius(14),
                        ),
                      ),
                      child: Icon(
                        Icons.diversity_3_rounded,
                        color: colors.accent,
                        size: responsive.icon(20),
                      ),
                    ),
                    SizedBox(width: responsive.s(14)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Active: $activeName',
                            style: GoogleFonts.inter(
                              color: colors.ink,
                              fontSize: responsive.font(14),
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                          SizedBox(height: responsive.s(3)),
                          Text(
                            profiles.isEmpty
                                ? 'No other profiles yet'
                                : '${profiles.length} other '
                                      'profile${profiles.length == 1 ? '' : 's'} '
                                      'on this device',
                            style: GoogleFonts.inter(
                              color: colors.inkMute,
                              fontSize: responsive.font(12.2),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colors.inkMute,
                      size: responsive.icon(20),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// The local-only variant: the same section, in the same place, saying what
  /// it would do and what it needs — rather than vanishing, which would leave a
  /// caregiver believing MedGuard cannot do this at all.
  Widget _buildLocked(MedGuardResponsive responsive, MedGuardColors colors) {
    return SectionBlock(
      title: 'Care circle',
      subtitle:
          'Track medicines for someone you look after, kept entirely separate '
          'from your own.',
      action: 'Sign in',
      onAction: _open,
      card: false,
      child: SurfaceCard(
        onTap: _open,
        padding: EdgeInsets.all(responsive.s(16)),
        child: Row(
          children: [
            Container(
              width: responsive.s(42),
              height: responsive.s(42),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.accentAlpha(0.12),
                borderRadius: BorderRadius.circular(responsive.radius(14)),
              ),
              child: Icon(
                Icons.diversity_3_rounded,
                color: colors.accent,
                size: responsive.icon(20),
              ),
            ),
            SizedBox(width: responsive.s(14)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Needs an account',
                    style: GoogleFonts.inter(
                      color: colors.ink,
                      fontSize: responsive.font(14),
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: responsive.s(3)),
                  Text(
                    'A managed profile belongs to the account that looks '
                    'after it, so it can move with you.',
                    style: GoogleFonts.inter(
                      color: colors.inkMute,
                      fontSize: responsive.font(12.2),
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: responsive.s(6)),
            Icon(
              Icons.lock_rounded,
              color: colors.inkMute,
              size: responsive.icon(18),
            ),
          ],
        ),
      ),
    );
  }
}

/// The profile whose data every section on this page reads. Follows the
/// caregiver switch, so viewing a managed profile shows THEIR record.
String _activeUserId() {
  try {
    return SessionService.instance.identity.value.activeUserId;
  } catch (_) {
    return 'local-device';
  }
}
