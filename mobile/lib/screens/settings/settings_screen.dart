import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/regimen_analysis.dart';
import '../../models/safety_report.dart';
import '../../services/auth_profile_preferences.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../services/dose_reminder_scheduler.dart';
import '../../services/dose_service.dart';
import '../../services/guest_mode_service.dart';
import '../../services/interaction_checker.dart';
import '../../services/notification_preferences.dart';
import '../../services/pharmacist_report.dart';
import '../../services/privacy_service.dart';
import '../../services/regimen_analyser.dart';
import '../../services/user_data_service.dart';
import '../../theme/medguard_colors.dart';
import '../../theme/medguard_responsive.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_notice.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/detail_page.dart';
import '../../widgets/common/modal_sheet.dart';
import '../../widgets/common/morph_loader.dart';
import '../../widgets/common/settings_row.dart';
import '../../widgets/common/sign_in_wall.dart';
import '../../widgets/common/surface_card.dart';
import '../auth/login_screen.dart';
import '../auth/privacy_policy_screen.dart';
import '../auth/terms_conditions_screen.dart';
import '../main_shell.dart';
import '../security/app_lock_settings_screen.dart';

/// The shipping version, stated once. It is read by the Help section's caption
/// and by the problem report's footer, which used to carry their own copies of
/// the string and had no way of staying in step.
const String _appVersion = '1.0.0';

/// Settings — everything the user CONFIGURES, separated from Profile, which is
/// everything the app has LEARNED about them.
///
/// The split is the point. These used to be one 2,100-line screen where a
/// personal adherence chart sat three rows above "delete all my data", so
/// neither read clearly: the profile felt like a preferences dump, and the
/// preferences were buried under statistics.
///
/// Ordering runs from the settings people change often (notifications,
/// appearance) to the ones they touch once or never (legal, deletion). The
/// destructive actions sit at the very bottom, alone, where nobody arrives by
/// accident.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static const String routeName = '/settings';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _doseReminders = true;
  bool _safetyAlerts = true;
  SummaryInterval _summary = SummaryInterval.off;
  AppThemeMode _theme = AppThemeMode.system;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final reminders = await NotificationPreferences.doseReminders();
      final alerts = await NotificationPreferences.safetyAlerts();
      final summary = await NotificationPreferences.summaryInterval();
      if (!mounted) return;
      setState(() {
        _doseReminders = reminders;
        _safetyAlerts = alerts;
        _summary = summary;
        _theme = ThemeController.instance.mode.value;
        _loading = false;
      });
    } catch (_) {
      // SharedPreferences unavailable (tests) — show the defaults.
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _userId {
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? 'local-device';
    } catch (_) {
      return 'local-device';
    }
  }

  // ── Notifications ─────────────────────────────────────────────────────────

  Future<void> _setDoseReminders(bool value) async {
    setState(() => _doseReminders = value);
    await NotificationPreferences.setDoseReminders(value);
    if (!mounted) return;
    showAppNotice(
      context,
      value ? 'Dose reminders on.' : 'Dose reminders off.',
      type: value ? AppNoticeType.success : AppNoticeType.info,
    );
  }

  Future<void> _setSafetyAlerts(bool value) async {
    setState(() => _safetyAlerts = value);
    await NotificationPreferences.setSafetyAlerts(value);
  }

  Future<void> _pickSummaryInterval() async {
    final picked = await showOptionSheet<SummaryInterval>(
      context: context,
      title: 'Summary',
      subtitle:
          'A recap of the doses you took and any safety changes. The cadence '
          'you pick also sets how far back each report looks.',
      selected: _summary,
      options: [
        for (final interval in SummaryInterval.values)
          SheetOption(
            value: interval,
            label: interval.label,
            detail: interval.detail,
            icon: switch (interval) {
              SummaryInterval.off => Icons.notifications_off_rounded,
              SummaryInterval.daily => Icons.today_rounded,
              SummaryInterval.weekly => Icons.date_range_rounded,
              SummaryInterval.monthly => Icons.calendar_month_rounded,
              SummaryInterval.yearly => Icons.event_note_rounded,
            },
          ),
      ],
    );
    if (picked == null || !mounted) return;

    setState(() => _summary = picked);
    await NotificationPreferences.setSummaryInterval(picked);
    try {
      await DoseReminderScheduler.instance.setSummaryInterval(picked);
    } catch (_) {
      // Notification plugin unavailable — the preference still persists, and
      // the scheduler re-reads it next time the app can reach the plugin.
    }
    if (!mounted) return;
    showAppNotice(
      context,
      picked.isOn
          ? '${picked.label} summary scheduled.'
          : 'Summary turned off.',
      type: AppNoticeType.success,
    );
  }

  // ── Appearance ────────────────────────────────────────────────────────────

  Future<void> _pickTheme() async {
    final picked = await showOptionSheet<AppThemeMode>(
      context: context,
      title: 'Appearance',
      subtitle: 'Applies immediately across the whole app.',
      selected: _theme,
      options: const [
        SheetOption(
          value: AppThemeMode.system,
          label: 'Match device',
          detail: 'Follow your phone\'s light or dark setting',
          icon: Icons.brightness_auto_rounded,
        ),
        SheetOption(
          value: AppThemeMode.light,
          label: 'Light',
          detail: 'The standard daytime interface',
          icon: Icons.light_mode_rounded,
        ),
        SheetOption(
          value: AppThemeMode.dark,
          label: 'Dark',
          detail: 'A calmer night interface',
          icon: Icons.dark_mode_rounded,
        ),
        SheetOption(
          value: AppThemeMode.oled,
          label: 'True black',
          detail: 'Pure #000000 — saves power on OLED screens',
          icon: Icons.contrast_rounded,
        ),
      ],
    );
    if (picked == null || !mounted) return;
    setState(() => _theme = picked);
    await ThemeController.instance.set(picked);
  }

  String get _themeLabel => switch (_theme) {
    AppThemeMode.system => 'Match device',
    AppThemeMode.light => 'Light',
    AppThemeMode.dark => 'Dark',
    AppThemeMode.oled => 'True black',
  };

  // ── Data ──────────────────────────────────────────────────────────────────

  Future<PharmacistReportData?> _collectReportData() async {
    try {
      final userId = _userId;
      final medications = await UserDataService.instance.getUserMedications(
        userId,
      );
      final schedules = await DoseService.instance.getSchedules(userId);
      final safety = medications.length >= 2
          ? await InteractionChecker.analyze(
              medications.map((m) => m.drugId).toList(growable: false),
            )
          : const SafetyReport.empty();
      final enzymes = medications.isEmpty
          ? const <DrugEnzymeRecord>[]
          : await DatabaseService.instance.getDrugEnzymes(
              medications.map((m) => m.drugId).toList(growable: false),
            );
      final analysis = RegimenAnalyser.analyze(
        medications: medications,
        report: safety,
        enzymeRecords: enzymes,
      );
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      // The report covers the same window the user chose for their summary, so
      // "monthly" means a month here too rather than a hard-coded week.
      final lookback = _summary.isOn ? _summary.lookbackDays : 7;
      final adherence = await DoseService.instance.adherence(
        userId,
        from: today.subtract(Duration(days: lookback - 1)),
        to: today,
        asOf: now,
      );
      final user = FirebaseAuth.instance.currentUser;
      final emailFallback = user?.email?.trim().isNotEmpty == true
          ? user!.email!.trim()
          : 'MedGuard patient';
      final patientName = AuthProfilePreferences.resolveDisplayName(
        firebaseDisplayName: user?.displayName,
        fallback: emailFallback,
      );
      return PharmacistReportData(
        patientName: patientName,
        generatedAt: now,
        medications: medications,
        schedules: schedules,
        safety: safety,
        analysis: analysis,
        adherence: adherence,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _sharePharmacistReport() async {
    final format = await showOptionSheet<String>(
      context: context,
      title: 'Share with your pharmacist',
      subtitle:
          'A full handoff: current medicines, schedule, adherence and every '
          'flagged interaction.',
      options: const [
        SheetOption(
          value: 'text',
          label: 'As text',
          detail: 'Paste into WhatsApp, SMS or email',
          icon: Icons.text_snippet_rounded,
        ),
        SheetOption(
          value: 'pdf',
          label: 'As PDF',
          detail: 'A printable handoff document',
          icon: Icons.picture_as_pdf_rounded,
        ),
      ],
    );
    if (format == null || !mounted) return;

    final data = await withBlockingLoader(
      context,
      _collectReportData,
      message: 'Assembling your report',
    );
    if (!mounted) return;
    if (data == null) {
      showAppNotice(
        context,
        'Could not assemble the report right now.',
        type: AppNoticeType.error,
      );
      return;
    }

    if (format == 'text') {
      await SharePlus.instance.share(
        ShareParams(
          text: PharmacistReportBuilder.buildText(data),
          subject: 'MedGuard — Pharmacist Handoff Report',
        ),
      );
    } else {
      final bytes = await PharmacistReportBuilder.buildPdf(data);
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'medguard-pharmacist-report.pdf',
      );
    }
  }

  Future<void> _exportData() async {
    try {
      final bytes = await withBlockingLoader(
        context,
        () => PrivacyService.exportUserData(_userId),
        message: 'Packaging your data',
      );
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              bytes,
              name: 'medguard-data-export.json',
              mimeType: 'application/json',
            ),
          ],
          subject: 'MedGuard — Data export',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      showAppNotice(
        context,
        'Could not assemble the export.',
        type: AppNoticeType.error,
      );
    }
  }

  Future<void> _deleteAllData() async {
    // Two gates, on purpose. The first states plainly what is lost; the second
    // asks for a typed phrase, which is what stops a reflexive double-tap from
    // wiping a regimen someone spent an hour entering.
    final first = await showConfirmSheet(
      context: context,
      title: 'Delete everything on this device?',
      message:
          'This wipes every medicine, schedule, dose log, allergy and '
          'preference stored here. It cannot be undone, and MedGuard keeps no '
          'copy to restore from.',
      confirmLabel: 'Continue',
      destructive: true,
      icon: Icons.delete_forever_rounded,
    );
    if (first != true || !mounted) return;

    final controller = TextEditingController();
    final confirmed = await showModalSheet<bool>(
      context: context,
      title: 'Type DELETE to confirm',
      subtitle: 'This is the last step. There is no undo after this.',
      icon: Icons.report_gmailerrorred_rounded,
      iconTint: context.colors.danger,
      confirmLabel: 'Delete everything',
      confirmVariant: AppButtonVariant.danger,
      onConfirm: () => controller.text.trim().toUpperCase() == 'DELETE',
      builder: (ctx) => AppTextField(
        controller: controller,
        label: 'Type DELETE',
        icon: Icons.keyboard_rounded,
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
      ),
    );
    if (confirmed != true || !mounted) return;

    final ok = await withBlockingLoader(
      context,
      () => PrivacyService.wipeLocalData(userId: _userId),
      message: 'Removing your data',
    );
    if (!mounted) return;
    if (ok) {
      // The wipe signs a signed-in user out, so sign-in is where they land.
      // A local-only user was never signed in and did not ask to be: dropping
      // them on a login wall would turn "delete my data" into "and now you
      // need an account", so they return to the app they were already using —
      // empty, and still theirs.
      final destination = GuestModeService.instance.enabled.value
          ? MainShell.routeName
          : LoginScreen.routeName;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(destination, (_) => false);
    } else {
      showAppNotice(
        context,
        'Some data could not be removed.',
        type: AppNoticeType.error,
      );
    }
  }

  Future<void> _reportProblem() async {
    final controller = TextEditingController();
    final sent = await showModalSheet<bool>(
      context: context,
      title: 'Report a problem',
      subtitle:
          'Tell us what went wrong. Your message is sent through your own '
          'email app — nothing leaves this device until you press send there.',
      confirmLabel: 'Compose email',
      onConfirm: () => controller.text.trim().length >= 5,
      builder: (ctx) => AppTextField(
        controller: controller,
        label: 'What went wrong',
        hint: 'What happened, and what were you doing at the time?',
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        maxLines: 5,
        minLines: 4,
      ),
    );
    if (sent != true || !mounted) return;

    // Shared rather than mailto: so the user can pick whichever mail client
    // they actually use, and can see and edit the text before it goes.
    await SharePlus.instance.share(
      ShareParams(
        text:
            '${controller.text.trim()}\n\n'
            '— — —\n'
            'Sent from MedGuard. Please keep the lines below, they help us '
            'reproduce the problem.\n'
            'App: MedGuard $_appVersion\n'
            'When: ${DateTime.now().toIso8601String()}',
        subject: 'MedGuard — Problem report',
      ),
    );
  }

  Future<void> _signOut() async {
    final confirm = await showConfirmSheet(
      context: context,
      title: 'Sign out?',
      message:
          'Your medicines and schedule stay on this device. You will need to '
          'sign in again to sync or restore them.',
      confirmLabel: 'Sign out',
      icon: Icons.logout_rounded,
    );
    if (confirm != true || !mounted) return;
    await AuthService.instance.signOut();
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(LoginScreen.routeName, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);

    return DetailPage(
      title: 'Settings',
      subtitle: 'Reminders, appearance, your data, and how MedGuard behaves.',
      slivers: [
        SliverToBoxAdapter(
          child: responsive.constrain(
            Padding(
              padding: EdgeInsets.symmetric(horizontal: responsive.pageX),
              child: _loading
                  ? const LoadingView(message: 'Loading your settings')
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _sections(context, responsive),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  /// How many of the three notification channels are currently on — the
  /// section's caption, and the one fact about it worth reading without opening
  /// the card.
  String get _notificationsSummary {
    final on = [_doseReminders, _safetyAlerts, _summary.isOn].where((v) => v);
    return switch (on.length) {
      3 => 'All on',
      0 => 'All off',
      final n => '$n of 3 on',
    };
  }

  bool get _isSignedIn {
    try {
      return FirebaseAuth.instance.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  List<Widget> _sections(BuildContext context, MedGuardResponsive responsive) {
    final colors = context.colors;
    final gap = SizedBox(height: sectionGap(responsive));

    return [
      SectionBlock(
        title: 'Notifications',
        subtitle: 'What MedGuard is allowed to interrupt you for.',
        action: _notificationsSummary,
        card: false,
        child: SettingsGroup(
          rows: [
            SettingsSwitch(
              icon: Icons.alarm_rounded,
              title: 'Dose reminders',
              subtitle: 'An alert at each scheduled dose, plus one nudge after',
              value: _doseReminders,
              onChanged: _setDoseReminders,
            ),
            SettingsSwitch(
              icon: Icons.health_and_safety_rounded,
              title: 'Safety alerts',
              subtitle: 'When a new medicine conflicts with your regimen',
              value: _safetyAlerts,
              onChanged: _setSafetyAlerts,
            ),
            SettingsRow(
              icon: Icons.summarize_rounded,
              title: 'Summary',
              subtitle: 'Adherence and safety recap',
              value: _summary.label,
              onTap: _pickSummaryInterval,
            ),
          ],
        ),
      ),
      gap,
      SectionBlock(
        title: 'Appearance',
        subtitle: 'How MedGuard looks. The choice is stored here and does not '
            'follow you to another phone.',
        action: 'This device',
        card: false,
        child: SettingsGroup(
          rows: [
            SettingsRow(
              icon: Icons.palette_rounded,
              title: 'Theme',
              subtitle: 'Light, dark, or match your device',
              value: _themeLabel,
              onTap: _pickTheme,
            ),
          ],
        ),
      ),
      gap,
      SectionBlock(
        title: 'Privacy and security',
        subtitle:
            'Your record is stored encrypted on this device and is never '
            'uploaded without you choosing to share it.',
        action: 'Encrypted',
        card: false,
        child: SettingsGroup(
          rows: [
            SettingsRow(
              icon: Icons.lock_rounded,
              title: 'App lock',
              subtitle: 'Biometric unlock and PIN',
              onTap: () => Navigator.of(
                context,
              ).pushNamed(AppLockSettingsScreen.routeName),
            ),
            SettingsRow(
              icon: Icons.local_pharmacy_rounded,
              title: 'Share with pharmacist',
              subtitle: 'A full handoff, as text or PDF',
              onTap: _sharePharmacistReport,
            ),
            SettingsRow(
              icon: Icons.download_rounded,
              title: 'Export my data',
              subtitle: 'Everything MedGuard holds, as a JSON file',
              onTap: _exportData,
            ),
          ],
        ),
      ),
      gap,
      SectionBlock(
        title: 'Help and legal',
        subtitle: 'Tell us when something breaks, and read what MedGuard '
            'commits to doing with your data.',
        // The build number lives HERE rather than as a floating line at the
        // foot of the page: this is the section a problem report is filed
        // from, and the version is the first thing that report needs.
        action: 'v$_appVersion',
        card: false,
        child: SettingsGroup(
          rows: [
            SettingsRow(
              icon: Icons.flag_rounded,
              title: 'Report a problem',
              subtitle: 'Send us what went wrong',
              onTap: _reportProblem,
            ),
            SettingsRow(
              icon: Icons.privacy_tip_rounded,
              title: 'Privacy policy',
              subtitle: 'How your data is handled',
              onTap: () =>
                  Navigator.of(context).pushNamed(PrivacyPolicyScreen.routeName),
            ),
            SettingsRow(
              icon: Icons.gavel_rounded,
              title: 'Terms and conditions',
              subtitle: 'What MedGuard is, and is not, for',
              onTap: () => Navigator.of(
                context,
              ).pushNamed(TermsConditionsScreen.routeName),
            ),
          ],
        ),
      ),
      gap,
      // The end of the road: arriving or leaving, and erasing. Alone in their
      // own section so neither is ever the row below something the user was
      // scrolling for.
      //
      // Without an account there is nothing to sign OUT of, and a row that says
      // so would be dead weight on the one screen where the user came looking
      // for a switch. The slot carries the action that actually exists.
      SectionBlock(
        title: 'Account',
        subtitle: _isSignedIn
            ? 'Signing out leaves everything here. Deleting does not — '
                  'MedGuard keeps no copy to restore from.'
            : 'MedGuard is running on this device alone. Signing in adds your '
                  'history and a record that outlives this phone.',
        action: _isSignedIn ? 'Signed in' : 'Local only',
        card: false,
        child: SettingsGroup(
          rows: [
            if (_isSignedIn)
              SettingsRow(
                icon: Icons.logout_rounded,
                title: 'Sign out',
                subtitle: 'Your data stays on this device',
                tint: colors.inkMute,
                onTap: _signOut,
              )
            else
              SettingsRow(
                icon: Icons.login_rounded,
                title: 'Sign in',
                subtitle: 'Bring this record into an account',
                onTap: () => openSignIn(context),
              ),
            SettingsRow(
              icon: Icons.delete_forever_rounded,
              title: 'Delete all my data',
              subtitle: 'Permanently wipe this device\'s record',
              destructive: true,
              onTap: _deleteAllData,
            ),
          ],
        ),
      ),
    ];
  }
}
