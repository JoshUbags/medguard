import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/interaction_result.dart';
import '../../models/user_medication.dart';
import '../../services/interaction_checker.dart';
import '../../services/lock_screen_widget_service.dart';
import '../../services/notification_preferences.dart';
import '../../services/user_data_service.dart';
import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';
import '../../theme/medguard_responsive.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/detail_page.dart';
import '../../widgets/common/modal_sheet.dart';
import '../../widgets/common/morph_loader.dart';
import '../../widgets/common/settings_row.dart';
import '../../widgets/common/surface_card.dart';

const _localUserId = 'local-device';
const _bloodTypes = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

class _EmergencySnapshot {
  const _EmergencySnapshot({
    required this.displayName,
    required this.bloodType,
    required this.contactName,
    required this.contactPhone,
    required this.medications,
    required this.criticalInteractions,
  });

  final String displayName;
  final String? bloodType;
  final String? contactName;
  final String? contactPhone;
  final List<UserMedication> medications;
  final List<InteractionResult> criticalInteractions;
}

/// The read-this-in-an-emergency card: who the user is, who to call, what they
/// take, and a QR payload a paramedic can scan for a fast handoff.
///
/// This is a routed secondary screen, so it is a [DetailPage] like Profile,
/// Settings and Notifications — same back pill, same title scale, same page
/// margins, same ambient canvas, same section grammar.
class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({super.key});

  static const String routeName = '/emergency';

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  late Future<_EmergencySnapshot> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  void _reload() => setState(() => _future = _load());

  String get _userId {
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? _localUserId;
    } catch (_) {
      return _localUserId;
    }
  }

  String _displayName() {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final name = user?.displayName?.trim();
      if (name != null && name.isNotEmpty) return name;
      final email = user?.email?.trim();
      if (email != null && email.isNotEmpty) return email;
    } catch (_) {}
    return 'MedGuard user';
  }

  Future<_EmergencySnapshot> _load() async {
    final displayName = _displayName();
    List<UserMedication> medications = const [];
    String? bloodType;
    String? contactName;
    String? contactPhone;
    List<InteractionResult> critical = const [];

    try {
      medications = await UserDataService.instance.getUserMedications(_userId);
    } catch (_) {}
    try {
      bloodType = await NotificationPreferences.bloodType();
      contactName = await NotificationPreferences.emergencyContactName();
      contactPhone = await NotificationPreferences.emergencyContactPhone();
    } catch (_) {}
    if (medications.length >= 2) {
      try {
        final report = await InteractionChecker.analyze(
          medications.map((m) => m.drugId).toList(growable: false),
        );
        critical = report.drugInteractions
            .where((i) => i.riskLevel.isHigh)
            .toList();
      } catch (_) {}
    }

    final snapshot = _EmergencySnapshot(
      displayName: displayName,
      bloodType: bloodType,
      contactName: contactName,
      contactPhone: contactPhone,
      medications: medications,
      criticalInteractions: critical,
    );

    // Keep the Android home/lock-screen widget in sync.
    // Fire-and-forget: a widget update failure must not block rendering
    // the emergency card itself.
    unawaited(
      LockScreenWidgetService.instance.publish(
        userId: _userId,
        displayName: snapshot.displayName,
        bloodType: snapshot.bloodType,
        emergencyContactName: snapshot.contactName,
        emergencyContactNumber: snapshot.contactPhone,
      ),
    );

    return snapshot;
  }

  String _payload(_EmergencySnapshot snap) {
    return jsonEncode({
      'name': snap.displayName,
      if (snap.bloodType != null) 'blood_type': snap.bloodType,
      if (snap.contactName != null)
        'emergency_contact': {
          'name': snap.contactName,
          if (snap.contactPhone != null) 'phone': snap.contactPhone,
        },
      'medications': snap.medications
          .map((m) => m.displayName)
          .toList(growable: false),
      if (snap.criticalInteractions.isNotEmpty)
        'critical_interactions': snap.criticalInteractions
            .map((i) => '${i.drugAName} + ${i.drugBName} (${i.severity})')
            .toList(growable: false),
      'generated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> _editEmergencyContact(_EmergencySnapshot snap) async {
    final nameController = TextEditingController(text: snap.contactName ?? '');
    final phoneController = TextEditingController(
      text: snap.contactPhone ?? '',
    );

    final saved = await showModalSheet<bool>(
      context: context,
      title: 'Emergency contact',
      subtitle:
          'The person a responder should call for you. Shown on this card and '
          'on the lock-screen widget.',
      icon: Icons.phone_in_talk_rounded,
      confirmLabel: 'Save contact',
      onConfirm: () => true,
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: nameController,
            label: 'Name',
            icon: Icons.person_rounded,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          AppTextField(
            controller: phoneController,
            label: 'Phone number',
            icon: Icons.call_rounded,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
          ),
        ],
      ),
    );
    if (saved != true) return;

    await NotificationPreferences.setEmergencyContact(
      name: nameController.text.trim(),
      phone: phoneController.text.trim(),
    );
    if (!mounted) return;
    _reload();
  }

  Future<void> _editBloodType(_EmergencySnapshot snap) async {
    final picked = await showOptionSheet<String>(
      context: context,
      title: 'Blood type',
      subtitle:
          'The first thing a responder looks for. Leave it unrecorded '
          'rather than guessing.',
      selected: snap.bloodType ?? '',
      options: [
        const SheetOption(
          value: '',
          label: 'Not recorded',
          detail: 'Leave this off the card',
          icon: Icons.remove_circle_rounded,
        ),
        for (final type in _bloodTypes)
          SheetOption(value: type, label: type, icon: Icons.bloodtype_rounded),
      ],
    );
    if (picked == null) return;

    await NotificationPreferences.setBloodType(picked.isEmpty ? null : picked);
    if (!mounted) return;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);

    return DetailPage(
      title: 'Emergency card',
      subtitle:
          'What a paramedic or ER clinician needs to know about you, in '
          'one place.',
      onRefresh: () async => _reload(),
      slivers: [
        SliverToBoxAdapter(
          child: responsive.constrain(
            Padding(
              padding: EdgeInsets.symmetric(horizontal: responsive.pageX),
              child: FutureBuilder<_EmergencySnapshot>(
                future: _future,
                builder: (context, snapshot) {
                  final snap = snapshot.data;
                  if (snap == null) {
                    return const LoadingView(
                      message: 'Assembling your card',
                      padding: EdgeInsets.symmetric(vertical: 48),
                    );
                  }
                  return _EmergencyBody(
                    snap: snap,
                    payload: _payload(snap),
                    onEditContact: () => _editEmergencyContact(snap),
                    onEditBlood: () => _editBloodType(snap),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The card itself, as the app's standard stack of sections.
class _EmergencyBody extends StatelessWidget {
  const _EmergencyBody({
    required this.snap,
    required this.payload,
    required this.onEditContact,
    required this.onEditBlood,
  });

  final _EmergencySnapshot snap;
  final String payload;
  final VoidCallback onEditContact;
  final VoidCallback onEditBlood;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final gap = SizedBox(height: sectionGap(responsive));
    final medications = snap.medications;
    final critical = snap.criticalInteractions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionBlock(
          title: 'Card holder',
          subtitle: 'What a responder reads first. Tap a line to change it.',
          card: false,
          child: _HolderCard(
            snap: snap,
            onEditBlood: onEditBlood,
            onEditContact: onEditContact,
          ),
        ),
        gap,
        SectionBlock(
          title: 'Scan to hand off',
          subtitle:
              'Any QR reader opens this card as text, so nothing has to '
              'be read out or typed in.',
          card: false,
          child: _QrCard(payload: payload, medicineCount: medications.length),
        ),
        gap,
        SectionBlock(
          title: 'Current medicines',
          subtitle: 'Everything on your MedGuard regimen right now.',
          action: medications.isEmpty ? 'None' : '${medications.length}',
          card: false,
          child: medications.isEmpty
              ? SurfaceCard(
                  padding: EdgeInsets.all(responsive.s(18)),
                  child: Text(
                    'No medicines saved yet. Anything you add to your regimen '
                    'appears here automatically.',
                    style: GoogleFonts.inter(
                      color: colors.inkSoft,
                      fontSize: responsive.font(12.8),
                      fontWeight: FontWeight.w500,
                      height: 1.5,
                    ),
                  ),
                )
              : _ListCard(
                  lines: [
                    for (final medication in medications)
                      (
                        icon: Icons.medication_rounded,
                        text: medication.displayName,
                        detail: null,
                      ),
                  ],
                ),
        ),
        if (critical.isNotEmpty) ...[
          gap,
          SectionBlock(
            title: 'Critical interactions',
            subtitle:
                'Pairs in your regimen MedGuard has flagged as high '
                'risk. Mention these before anything new is given.',
            action: '${critical.length}',
            card: false,
            child: _ListCard(
              accent: colors.danger,
              lines: [
                for (final interaction in critical)
                  (
                    icon: Icons.warning_amber_rounded,
                    text: '${interaction.drugAName} + ${interaction.drugBName}',
                    detail: interaction.riskLevel.label,
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Whose card this is, and the two facts about them a responder needs first —
/// ONE card, so the name and the details that belong to it read as one record
/// rather than as two unrelated panels stacked on top of each other.
class _HolderCard extends StatelessWidget {
  const _HolderCard({
    required this.snap,
    required this.onEditBlood,
    required this.onEditContact,
  });

  final _EmergencySnapshot snap;
  final VoidCallback onEditBlood;
  final VoidCallback onEditContact;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final disc = responsive.s(46).clamp(42.0, 54.0).toDouble();
    final contactName = snap.contactName?.trim();
    final contactPhone = snap.contactPhone?.trim();
    final hasContact = contactName != null && contactName.isNotEmpty;

    return SurfaceCard(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.s(14),
        vertical: responsive.s(6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(
              top: responsive.s(12),
              bottom: responsive.s(2),
            ),
            child: Row(
              children: [
                Container(
                  width: disc,
                  height: disc,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.dangerAlpha(0.12),
                    borderRadius: BorderRadius.circular(responsive.radius(15)),
                  ),
                  child: Icon(
                    Icons.contact_emergency_rounded,
                    color: colors.danger,
                    size: responsive.icon(22),
                  ),
                ),
                SizedBox(width: responsive.s(14)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Emergency medical information',
                        style: GoogleFonts.inter(
                          color: colors.danger,
                          fontSize: responsive.font(11.6),
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                      SizedBox(height: responsive.s(4)),
                      Text(
                        snap.displayName,
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
                    ],
                  ),
                ),
              ],
            ),
          ),
          const CardDivider(),
          SettingsRow(
            icon: Icons.bloodtype_rounded,
            title: 'Blood type',
            subtitle: 'Checked before anything is given',
            value: snap.bloodType ?? 'Not set',
            tint: colors.danger,
            onTap: onEditBlood,
          ),
          CardDivider(indent: responsive.s(46)),
          SettingsRow(
            icon: Icons.phone_in_talk_rounded,
            title: 'Emergency contact',
            // Name and number share the caption rather than the name riding in
            // the right-hand value slot, where a long name was cut to an
            // ellipsis on exactly the line a responder needs to read in full.
            subtitle: !hasContact
                ? 'Nobody to call yet'
                : (contactPhone == null || contactPhone.isEmpty)
                ? '$contactName · no number saved'
                : '$contactName · $contactPhone',
            value: hasContact ? null : 'Not set',
            onTap: onEditContact,
          ),
        ],
      ),
    );
  }
}

/// The scannable payload, and what it carries.
///
/// The code is painted in FIXED dark ink on a fixed white plate rather than in
/// the theme's ink on the theme's surface: a QR drawn in near-white on white is
/// what the dark theme produced before, and an emergency card that cannot be
/// scanned at night is worse than no card at all. On the light theme the plate
/// is the card's own white, so the code sits directly on the card instead of in
/// a second bordered box inside it.
class _QrCard extends StatelessWidget {
  const _QrCard({required this.payload, required this.medicineCount});

  final String payload;
  final int medicineCount;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final extent = responsive.s(184).clamp(164.0, 216.0).toDouble();
    final medicines =
        '$medicineCount ${medicineCount == 1 ? 'medicine' : 'medicines'}';

    return SurfaceCard(
      padding: EdgeInsets.fromLTRB(
        responsive.s(18),
        responsive.s(14),
        responsive.s(18),
        responsive.s(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(responsive.s(10)),
            decoration: BoxDecoration(
              color: MedGuardPalette.pureWhite,
              borderRadius: BorderRadius.circular(responsive.radius(16)),
            ),
            child: QrImageView(
              data: payload,
              version: QrVersions.auto,
              size: extent,
              padding: EdgeInsets.zero,
              backgroundColor: MedGuardPalette.pureWhite,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: MedGuardPalette.ink,
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: MedGuardPalette.ink,
              ),
            ),
          ),
          SizedBox(height: responsive.s(6)),
          const CardDivider(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.qr_code_2_rounded,
                size: responsive.icon(18),
                color: colors.accent,
              ),
              SizedBox(width: responsive.s(10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Name, blood type, contact and $medicines',
                      style: GoogleFonts.inter(
                        color: colors.ink,
                        fontSize: responsive.font(12.8),
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                    SizedBox(height: responsive.s(2)),
                    Text(
                      'Refreshed each time this card opens',
                      style: GoogleFonts.inter(
                        color: colors.inkMute,
                        fontSize: responsive.font(11.8),
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A short list inside one card: a glyph, a line of text and an optional
/// trailing detail per row, divided by hairlines inset past the glyph.
class _ListCard extends StatelessWidget {
  const _ListCard({required this.lines, this.accent});

  final List<({IconData icon, String text, String? detail})> lines;

  /// Tints the card and its glyphs toward a status colour.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final tone = accent ?? colors.accent;
    final hairline = accent?.withValues(alpha: 0.16) ?? colors.border;

    return SurfaceCard(
      accent: accent,
      padding: EdgeInsets.symmetric(
        horizontal: responsive.s(16),
        vertical: responsive.s(4),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            if (i > 0)
              Container(
                height: 1,
                margin: EdgeInsets.only(left: responsive.s(30)),
                color: hairline,
              ),
            Padding(
              padding: EdgeInsets.symmetric(vertical: responsive.s(12)),
              child: Row(
                children: [
                  Icon(lines[i].icon, size: responsive.icon(17), color: tone),
                  SizedBox(width: responsive.s(13)),
                  Expanded(
                    child: Text(
                      lines[i].text,
                      style: GoogleFonts.inter(
                        color: colors.ink,
                        fontSize: responsive.font(13.6),
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                  if (lines[i].detail != null) ...[
                    SizedBox(width: responsive.s(10)),
                    Text(
                      lines[i].detail!,
                      style: GoogleFonts.inter(
                        color: tone,
                        fontSize: responsive.font(12),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
