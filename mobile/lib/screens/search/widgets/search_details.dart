// Part of `search_screen.dart`, split out for readability.
// All imports live in the parent library file.
part of '../search_screen.dart';

/// What a medicine is, laid out so it can actually be read.
///
/// The information is grouped the way a person asks about a medicine, in that
/// order: what is it, what is it for, how is it taken, what should I watch for,
/// and where does this record come from. Each group is a titled section with
/// its text in full — nothing here is capped at four lines and cut.
///
/// Sections with no data say so plainly rather than being hidden. A record with
/// three of five sections missing is a real fact about the local database, and
/// concealing it would leave the user unable to tell a thin record from a
/// complete one.
class _DrugDetailsSheet extends StatelessWidget {
  const _DrugDetailsSheet({
    required this.drug,
    required this.isAdded,
    required this.isAdding,
    required this.onAdd,
  });

  final Drug drug;
  final bool isAdded;
  final bool isAdding;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final description = _cleanDrugText(drug.description);
    final indication = _cleanDrugText(drug.indication);

    final sections = <({String title, String? body, String fallback})>[
      (
        title: 'What it is',
        body: description,
        fallback:
            'The local database has no descriptive summary for this medicine.',
      ),
      (
        title: 'What it is used for',
        body: indication,
        fallback:
            'No approved-use information is recorded for this medicine '
            'locally. The full monograph may carry more.',
      ),
      (
        title: 'How it is taken',
        body: _dosageGuidance(drug),
        fallback:
            'Dose is not part of this reference. Follow the prescription '
            'label, or ask the pharmacy that dispensed it.',
      ),
      (
        title: 'What to watch for',
        body: _safetyReviewFocus(drug),
        fallback:
            'Add this medicine to your regimen and MedGuard will check it '
            'against everything else you take.',
      ),
    ];

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        responsive.pageX,
        responsive.s(4),
        responsive.pageX,
        responsive.s(28),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _DrugDetailsHeader(
            drug: drug,
            isAdded: isAdded,
            isAdding: isAdding,
            onAdd: onAdd,
          ),
          SizedBox(height: responsive.s(24)),

          _DetailSection(
            title: 'At a glance',
            child: _ReferenceFacts(drug: drug),
          ),

          for (final section in sections) ...[
            SizedBox(height: responsive.s(22)),
            _DetailSection(
              title: section.title,
              child: _SectionProse(
                body: section.body,
                fallback: section.fallback,
              ),
            ),
          ],

          SizedBox(height: responsive.s(24)),
          AppButton(
            label: 'Read the full monograph',
            icon: Icons.menu_book_rounded,
            variant: AppButtonVariant.secondary,
            onTap: () {
              Navigator.of(context).pop();
              openDrugMonograph(context, drugId: drug.id, drugName: drug.name);
            },
          ),
        ],
      ),
    );
  }
}

/// The sheet's opening block: what this is, and the one action worth taking
/// from here.
class _DrugDetailsHeader extends StatelessWidget {
  const _DrugDetailsHeader({
    required this.drug,
    required this.isAdded,
    required this.isAdding,
    required this.onAdd,
  });

  final Drug drug;
  final bool isAdded;
  final bool isAdding;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DrugVisual(
              key: ValueKey('drug-detail-visual-${drug.id}'),
              drug: drug,
            ),
            SizedBox(width: responsive.s(14)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The name in full, wrapping. Never truncated: this is the
                  // one string on the page a user must be able to read exactly,
                  // because two medicines can share the first twenty letters.
                  Text(
                    drug.name,
                    style: GoogleFonts.inter(
                      color: colors.ink,
                      fontSize: responsive.font(21),
                      fontWeight: FontWeight.w700,
                      height: 1.18,
                      letterSpacing: -0.5,
                    ),
                  ),
                  SizedBox(height: responsive.s(6)),
                  Text(
                    _drugGroup(drug) ?? 'Medication record',
                    style: GoogleFonts.inter(
                      color: colors.inkMute,
                      fontSize: responsive.font(12.6),
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: responsive.s(18)),
        AppButton(
          label: isAdded ? 'Already in your regimen' : 'Add to my regimen',
          icon: isAdded ? Icons.check_rounded : Icons.add_rounded,
          loading: isAdding,
          onTap: isAdded ? null : onAdd,
        ),
      ],
    );
  }
}

/// The record's structured facts, as label/value rows.
///
/// Values wrap onto their own line rather than being squeezed against the
/// label and ellipsised — an ATC code or a half-life is the kind of value a
/// user copies down, so it has to be complete.
class _ReferenceFacts extends StatelessWidget {
  const _ReferenceFacts({required this.drug});

  final Drug drug;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);

    final rows = <({String label, String? value})>[
      (label: 'Classification code', value: drug.atcCode),
      (label: 'Medicine group', value: _drugGroup(drug)),
      (label: 'Drug type', value: drug.drugType),
      (label: 'Half-life', value: drug.halfLife),
      (label: 'Reference ID', value: drug.drugbankId),
      (label: 'Record status', value: _recordStatus(drug)),
    ].where((r) => r.value?.trim().isNotEmpty ?? false).toList();

    if (rows.isEmpty) {
      return Text(
        'This medicine is in the database by name only — no classification '
        'or identifiers are recorded for it.',
        style: GoogleFonts.inter(
          color: context.colors.inkSoft,
          fontSize: responsive.font(12.8),
          fontWeight: FontWeight.w500,
          height: 1.5,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const CardDivider(),
          _FactRow(label: rows[i].label, value: rows[i].value!.trim()),
        ],
      ],
    );
  }
}

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.inter(
            color: colors.inkMute,
            fontSize: responsive.font(9.6),
            fontWeight: FontWeight.w700,
            letterSpacing: 0.9,
          ),
        ),
        SizedBox(height: responsive.s(4)),
        Text(
          value,
          style: GoogleFonts.inter(
            color: colors.ink,
            fontSize: responsive.font(13),
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

/// A titled group in the sheet: heading on the canvas, content in a card —
/// the same grammar as every other page in the app.
class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(title: title),
        SizedBox(height: sectionHeaderGap(responsive)),
        SurfaceCard(padding: EdgeInsets.all(responsive.s(16)), child: child),
      ],
    );
  }
}

/// A section's prose, or an honest note that the database has none.
class _SectionProse extends StatelessWidget {
  const _SectionProse({required this.body, required this.fallback});

  final String? body;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final value = body?.trim();
    final missing = value == null || value.isEmpty;

    if (missing) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline_rounded,
            size: responsive.icon(15),
            color: colors.inkMute,
          ),
          SizedBox(width: responsive.s(9)),
          Expanded(
            child: Text(
              fallback,
              style: GoogleFonts.inter(
                color: colors.inkMute,
                fontSize: responsive.font(12.4),
                fontWeight: FontWeight.w500,
                height: 1.5,
              ),
            ),
          ),
        ],
      );
    }

    // No maxLines. A clinical description that stops mid-sentence is the
    // problem this screen was rebuilt to fix.
    return Text(
      value,
      style: GoogleFonts.inter(
        color: colors.inkSoft,
        fontSize: responsive.font(13),
        fontWeight: FontWeight.w500,
        height: 1.55,
      ),
    );
  }
}

// -- Derived, plain-language facts about a record ---------------------------
//
// These read the local database structured fields and turn them into sentences
// a non-clinician can act on. They are the reason a thin record still says
// something useful rather than showing four empty sections.

/// The medicine's plain-language family, or null when the record carries no
/// classification code to derive one from.
///
/// Returns null rather than the string 'Unavailable' so callers can choose
/// their own fallback in context — the details header wants "Medication
/// record", the facts list wants the row omitted entirely, and neither wants
/// the word "Unavailable" sitting where a medicine class should be.
String? _drugGroup(Drug drug) => _DrugFamily.forCode(drug.atcCode)?.longLabel;

String _recordStatus(Drug drug) {
  final hasDescription = _cleanDrugText(drug.description)?.isNotEmpty ?? false;
  final hasUse = _cleanDrugText(drug.indication)?.isNotEmpty ?? false;
  final hasCode = drug.atcCode?.trim().isNotEmpty ?? false;
  final items = <String>[
    if (hasDescription) 'description',
    if (hasUse) 'typical use',
    if (hasCode) 'classification',
  ];
  if (items.isEmpty) return 'Basic lookup record';
  return 'Includes ${items.join(', ')}';
}

String _safetyReviewFocus(Drug drug) {
  final name = drug.name.trim().isEmpty ? 'This medicine' : drug.name.trim();
  final family = _DrugFamily.forCode(drug.atcCode);
  if (family == null) {
    return '$name can be added to the medication list, but classification '
        'details are unavailable. Confirm the exact product, dose, and reason '
        'for use before comparing it with other medicines.';
  }
  return '$name ${family.watchFor}';
}

String _dosageGuidance(Drug drug) {
  final name = drug.name.trim().isEmpty ? 'This medicine' : drug.name.trim();
  return '$name dosage depends on product strength, route, age, kidney/liver '
      'context, and the reason for use. MedGuard does not replace the '
      'prescription label; confirm the exact dose before saving reminders.';
}
