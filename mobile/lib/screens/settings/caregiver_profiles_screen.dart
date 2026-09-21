import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/managed_profile.dart';
import '../../services/active_profile_service.dart';
import '../../services/user_data_service.dart';
import '../../theme/medguard_colors.dart';
import '../../theme/medguard_responsive.dart';
import '../../widgets/common/app_notice.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/detail_page.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/item_row.dart';
import '../../widgets/common/modal_sheet.dart';
import '../../widgets/common/morph_loader.dart';
import '../../widgets/common/surface_card.dart';

/// Care profiles — the people whose medication this device tracks.
///
/// Selecting one switches the ACTIVE context for the whole app: the home feed,
/// the dose schedule, and every safety check then read that person's regimen.
/// That is a big, easily-missed change of state, so the active profile is called
/// out on the row rather than merely implied by a highlight.
///
/// One list, one way to add. The add tile sits at the foot of the single list,
/// where it is in the same place whether the list is empty or full.
class CaregiverProfilesScreen extends StatefulWidget {
  const CaregiverProfilesScreen({super.key, required this.ownerId});

  static const String routeName = '/care-profiles';

  final String ownerId;

  @override
  State<CaregiverProfilesScreen> createState() =>
      _CaregiverProfilesScreenState();
}

class _CaregiverProfilesScreenState extends State<CaregiverProfilesScreen> {
  late Future<List<ManagedProfile>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    UserDataService.instance.profilesRevision.addListener(_reload);
  }

  @override
  void dispose() {
    UserDataService.instance.profilesRevision.removeListener(_reload);
    super.dispose();
  }

  Future<List<ManagedProfile>> _load() =>
      UserDataService.instance.getManagedProfiles(widget.ownerId);

  void _reload() {
    if (!mounted) return;
    setState(() => _future = _load());
  }

  Future<void> _add() async {
    HapticFeedback.selectionClick();
    final nameController = TextEditingController();
    final relationController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final saved = await showModalSheet<bool>(
      context: context,
      title: 'Add a care profile',
      subtitle:
          'Each profile keeps its own medicines, allergies, doses and '
          'safety history, entirely separate from yours.',
      icon: Icons.person_add_alt_1_rounded,
      builder: (ctx) => Form(
        key: formKey,
        child: Column(
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
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'A name is required.';
                if (v.trim().length > 60) return 'Name is too long.';
                return null;
              },
            ),
            const SizedBox(height: 12),
            AppTextField(
              controller: relationController,
              label: 'Relationship (optional)',
              hint: 'Mum, son, or partner',
              icon: Icons.diversity_1_rounded,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
            ),
          ],
        ),
      ),
      confirmLabel: 'Add profile',
      onConfirm: () => formKey.currentState?.validate() == true,
    );

    if (saved != true) return;
    HapticFeedback.lightImpact();
    await UserDataService.instance.addManagedProfile(
      ownerId: widget.ownerId,
      name: nameController.text.trim(),
      relation: relationController.text.trim().isEmpty
          ? null
          : relationController.text.trim(),
    );
    if (!mounted) return;
    showAppNotice(
      context,
      '${nameController.text.trim()} added.',
      type: AppNoticeType.success,
    );
  }

  Future<void> _remove(ManagedProfile profile) async {
    final confirm = await showConfirmSheet(
      context: context,
      title: 'Remove ${profile.name}?',
      message:
          'This permanently deletes the medicines, allergies, dose schedule '
          'and safety history stored for this profile. It cannot be undone.',
      confirmLabel: 'Remove profile',
      destructive: true,
      icon: Icons.person_remove_rounded,
    );
    if (confirm != true || !mounted) return;

    final isActive =
        ActiveProfileService.instance.current.value.activeUserId ==
        profile.profileId;
    if (isActive) await ActiveProfileService.instance.switchToOwner();
    await UserDataService.instance.removeManagedProfile(
      ownerId: widget.ownerId,
      profileId: profile.profileId,
    );
    if (!mounted) return;
    showAppNotice(
      context,
      '${profile.name} removed.',
      type: AppNoticeType.undo,
    );
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);

    return DetailPage(
      title: 'Care profiles',
      subtitle:
          'Switch between the people you look after. The profile you pick '
          'becomes the active context across the whole app.',
      slivers: [
        SliverToBoxAdapter(
          child: responsive.constrain(
            Padding(
              padding: EdgeInsets.symmetric(horizontal: responsive.pageX),
              child: ValueListenableBuilder<ActiveProfile>(
                valueListenable: ActiveProfileService.instance.current,
                builder: (context, active, _) {
                  return FutureBuilder<List<ManagedProfile>>(
                    future: _future,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const LoadingView(
                          message: 'Loading your profiles',
                        );
                      }
                      if (snapshot.hasError) {
                        return AppErrorState(
                          title: 'Could not load profiles',
                          message:
                              'We could not read your profile list. '
                              'Try again in a moment.',
                          onRetry: _reload,
                        );
                      }
                      final profiles = snapshot.data ?? const [];

                      return SectionBlock(
                        title: 'Profiles on this device',
                        subtitle: profiles.isEmpty
                            ? 'Only your own regimen so far. Add someone you '
                                  'look after and their record stays entirely '
                                  'separate from yours.'
                            : 'Your own regimen always sits first and cannot '
                                  'be removed.',
                        action: '${profiles.length + 1}',
                        card: false,
                        children: [
                          _ProfileRow(
                            name: 'Myself',
                            relation: 'Device owner',
                            isActive: active.isOwner,
                            onTap: () async {
                              HapticFeedback.selectionClick();
                              await ActiveProfileService.instance
                                  .switchToOwner();
                            },
                          ),
                          for (final profile in profiles)
                            _ProfileRow(
                              name: profile.name,
                              relation: profile.relation ?? 'No relation set',
                              isActive:
                                  active.activeUserId == profile.profileId,
                              onTap: () async {
                                HapticFeedback.selectionClick();
                                await ActiveProfileService.instance.switchTo(
                                  profile,
                                );
                              },
                              onRemove: () => _remove(profile),
                            ),
                          ItemAddTile(
                            title: 'Add a care profile',
                            subtitle: 'For someone you look after',
                            icon: Icons.person_add_alt_1_rounded,
                            onTap: _add,
                          ),
                        ],
                      );
                    },
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

/// One person. The device owner carries a person glyph; everyone else carries
/// their initial, which is what tells two managed profiles apart at a glance.
class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.name,
    required this.relation,
    required this.isActive,
    required this.onTap,
    this.onRemove,
  });

  final String name;
  final String relation;
  final bool isActive;
  final VoidCallback onTap;

  /// Null for the owner, who cannot be removed.
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final isOwner = onRemove == null;

    return ItemRowCard(
      title: name,
      subtitle: relation,
      onTap: onTap,
      accent: isActive ? colors.accent : null,
      leading: isOwner
          ? ItemGlyph(icon: Icons.person_rounded, tint: colors.accent)
          : _InitialGlyph(
              initial: name.isEmpty ? '?' : name.characters.first.toUpperCase(),
            ),
      trailing: isActive
          ? Container(
              padding: EdgeInsets.symmetric(
                horizontal: responsive.s(10),
                vertical: responsive.s(5),
              ),
              decoration: BoxDecoration(
                color: colors.accentAlpha(0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Active',
                style: GoogleFonts.inter(
                  color: colors.accent,
                  fontSize: responsive.font(11.4),
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : onRemove == null
          ? null
          : RowRemoveButton(label: name, onTap: onRemove!),
    );
  }
}

/// A profile's initial on the list-row glyph plate.
class _InitialGlyph extends StatelessWidget {
  const _InitialGlyph({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final extent = responsive.s(42).clamp(38.0, 50.0).toDouble();

    return Container(
      width: extent,
      height: extent,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.accentAlpha(0.11),
        borderRadius: BorderRadius.circular(responsive.radius(14)),
      ),
      child: Text(
        initial,
        style: GoogleFonts.inter(
          color: colors.accent,
          fontSize: responsive.font(16),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
