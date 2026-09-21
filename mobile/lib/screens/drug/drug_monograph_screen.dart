import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/drug_monograph.dart';
import '../../models/food_interaction_result.dart';
import '../../models/regimen_analysis.dart';
import '../../models/severity.dart';
import '../../services/database_service.dart';
import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';
import '../../theme/medguard_responsive.dart';
import '../../widgets/common/detail_page.dart';
import '../../widgets/common/empty_state.dart';
import '../../widgets/common/morph_loader.dart';
import '../../widgets/common/surface_card.dart';

/// Aggregated payload the monograph screen renders. Built by [_load] in one
/// pass against the bundled DB so the UI can render everything in one shot.
class _MonographData {
  const _MonographData({
    required this.drug,
    required this.synonyms,
    required this.categories,
    required this.foodInteractions,
    required this.enzymes,
    required this.interactionSummary,
  });

  final DrugMonograph drug;
  final List<({String synonym, String? source})> synonyms;
  final List<String> categories;
  final List<FoodInteractionResult> foodInteractions;
  final List<DrugEnzymeRecord> enzymes;
  final Map<String, int> interactionSummary;
}

/// Drug encyclopedia screen — accessible from search results, the medications
/// list, or any pill name on the safety report. Renders every meaningful
/// column from the bundled DrugBank database for one drug, plus its enzyme
/// profile, food advisories, category memberships, and known interactions.
///
/// Laid out in the app's section grammar — heading on the canvas, content in a
/// card — exactly like the safety report, which is the page a user most often
/// arrives here from.
class DrugMonographScreen extends StatefulWidget {
  const DrugMonographScreen({
    super.key,
    required this.drugId,
    required this.drugName,
  });

  static const String routeName = '/drug';

  final int drugId;
  final String drugName;

  @override
  State<DrugMonographScreen> createState() => _DrugMonographScreenState();
}

class _DrugMonographScreenState extends State<DrugMonographScreen> {
  late Future<_MonographData?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_MonographData?> _load() async {
    final db = DatabaseService.instance;
    final drug = await db.getDrugMonograph(widget.drugId);
    if (drug == null) return null;
    final synonyms = await db.getDrugSynonyms(widget.drugId);
    final categories = await db.getDrugCategories(widget.drugId);
    final foods = await db.getFoodInteractions(widget.drugId);
    final enzymes = await db.getDrugEnzymes([widget.drugId]);
    final summary = await db.getInteractionSummaryForDrug(widget.drugId);
    return _MonographData(
      drug: drug,
      synonyms: synonyms,
      categories: categories,
      foodInteractions: foods,
      enzymes: enzymes,
      interactionSummary: summary,
    );
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);

    return DetailPage(
      title: widget.drugName,
      subtitle: 'From the bundled clinical reference.',
      slivers: [
        SliverToBoxAdapter(
          child: responsive.constrain(
            Padding(
              padding: EdgeInsets.symmetric(horizontal: responsive.pageX),
              child: FutureBuilder<_MonographData?>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const LoadingView(message: 'Opening the monograph');
                  }
                  final data = snapshot.data;
                  if (data == null) {
                    // An empty state, not an error state: nothing failed, the
                    // reference simply does not carry this medicine. Offering
                    // a "Retry" here would invite the user to keep tapping at
                    // an outcome that cannot change.
                    return const EmptyState(
                      icon: Icons.menu_book_rounded,
                      title: 'Not in the reference',
                      message:
                          'This medicine is not in the bundled clinical '
                          'database, so there is no monograph to show. Your '
                          'safety checks still cover it.',
                    );
                  }
                  return _MonographView(data: data);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MonographView extends StatelessWidget {
  const _MonographView({required this.data});

  final _MonographData data;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final drug = data.drug;

    final about = _clean(drug.description);
    final indication = _clean(drug.indication);
    final pharmacology = <(String, String)>[
      if (_clean(drug.mechanismOfAction) case final text?)
        ('Mechanism of action', text),
      if (_clean(drug.absorption) case final text?) ('Absorption', text),
      if (_clean(drug.halfLife) case final text?) ('Half-life', text),
      if (_clean(drug.toxicity) case final text?) ('Toxicity', text),
    ];
    final chemistry = <(String, String)>[
      if (_clean(drug.casNumber) case final text?) ('CAS number', text),
      if (_clean(drug.averageMass) case final text?)
        ('Average mass', '$text g/mol'),
      if (_clean(drug.allAtcCodes) case final text?) ('ATC codes', text),
      if (_clean(drug.groups) case final text?)
        ('Approval groups', _sentenceCase(text)),
    ];
    final foods = <String>[
      for (final item in data.foodInteractions) ?_clean(item.description),
    ];

    // ONE gap between every section on the page — the same rhythm as the safety
    // report and every other routed page.
    final sections = <Widget>[
      _HeroCard(drug: drug),
      if (about != null) SectionBlock(title: 'Overview', child: _Prose(about)),
      if (indication != null)
        SectionBlock(
          title: 'Clinical use',
          subtitle: 'What this medicine is prescribed for.',
          child: _Prose(indication),
        ),
      if (pharmacology.isNotEmpty)
        SectionBlock(
          title: 'Pharmacology',
          subtitle: 'How it acts, and how the body handles it.',
          child: _LabelledProse(entries: pharmacology),
        ),
      if (data.interactionSummary.isNotEmpty)
        _InteractionSummary(summary: data.interactionSummary),
      if (data.enzymes.isNotEmpty) _Metabolism(records: data.enzymes),
      if (foods.isNotEmpty)
        SectionBlock(
          title: 'Food and drink',
          subtitle: 'Advisories on record for this medicine.',
          action: '${foods.length}',
          child: _BulletList(items: foods),
        ),
      if (chemistry.isNotEmpty)
        SectionBlock(
          title: 'Chemistry',
          child: _KeyValues(rows: chemistry),
        ),
      if (data.categories.isNotEmpty)
        SectionBlock(
          title: 'Therapeutic categories',
          action: '${data.categories.length}',
          child: _ChipWrap(labels: data.categories, tinted: true),
        ),
      if (data.synonyms.isNotEmpty)
        SectionBlock(
          title: 'Also known as',
          action: '${data.synonyms.length}',
          child: _ChipWrap(
            labels: [for (final s in data.synonyms.take(40)) s.synonym],
            overflow: data.synonyms.length > 40
                ? '+ ${data.synonyms.length - 40} more'
                : null,
          ),
        ),
    ];

    // A Column, not a ListView: DetailPage owns the scroll, and nesting a
    // second scrollable inside it would fight the outer one for the gesture.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) SizedBox(height: sectionGap(responsive)),
          sections[i],
        ],
      ],
    );
  }
}

/// The reference card: what kind of medicine this is, and its identifiers.
///
/// It deliberately does not repeat the medicine's name — that is the page
/// title directly above it, and printing it twice in two sizes was the first
/// thing the eye landed on.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.drug});

  final DrugMonograph drug;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final drugClass = _clean(drug.drugClass);
    final generic = _clean(drug.genericName);
    final showGeneric =
        generic != null && generic.toLowerCase() != drug.name.toLowerCase();
    final tags = <String>[
      if (_clean(drug.drugType) case final type?) _sentenceCase(type),
      if (drug.isApproved) 'Approved',
      if (showGeneric) 'Generic: $generic',
    ];
    final ids = <(String, String)>[
      if (_clean(drug.atcCode) case final atc?) ('ATC', atc),
      if (_clean(drug.rxcui) case final rxcui?)
        (
          'RxCUI',
          rxcui.endsWith('.0') ? rxcui.substring(0, rxcui.length - 2) : rxcui,
        ),
      ('DrugBank', drug.drugbankId),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(responsive.s(20)),
      decoration: BoxDecoration(
        gradient: MedGuardPalette.tealSheen,
        borderRadius: BorderRadius.circular(responsive.radius(22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: responsive.s(42),
                height: responsive.s(42),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: MedGuardPalette.whiteAlpha(0.16),
                  borderRadius: BorderRadius.circular(responsive.radius(14)),
                ),
                child: Icon(
                  Icons.medication_rounded,
                  color: MedGuardPalette.pureWhite,
                  size: responsive.icon(21),
                ),
              ),
              SizedBox(width: responsive.s(14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      drugClass == null ? 'Reference record' : 'Drug class',
                      style: GoogleFonts.inter(
                        color: MedGuardPalette.whiteAlpha(0.72),
                        fontSize: responsive.font(11.6),
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(height: responsive.s(3)),
                    Text(
                      drugClass ?? drug.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: MedGuardPalette.pureWhite,
                        fontSize: responsive.font(17),
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
          if (tags.isNotEmpty) ...[
            SizedBox(height: responsive.s(14)),
            Wrap(
              spacing: responsive.s(6),
              runSpacing: responsive.s(6),
              children: [
                for (final tag in tags)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: responsive.s(10),
                      vertical: responsive.s(5),
                    ),
                    decoration: BoxDecoration(
                      color: MedGuardPalette.whiteAlpha(0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tag,
                      style: GoogleFonts.inter(
                        color: MedGuardPalette.pureWhite,
                        fontSize: responsive.font(11.6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ],
          SizedBox(height: responsive.s(16)),
          Container(height: 1, color: MedGuardPalette.whiteAlpha(0.16)),
          SizedBox(height: responsive.s(14)),
          Row(
            children: [
              for (final id in ids)
                Expanded(
                  child: _MiniStat(label: id.$1, value: id.$2),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            color: MedGuardPalette.whiteAlpha(0.7),
            fontSize: responsive.font(11),
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: responsive.s(3)),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            color: MedGuardPalette.pureWhite,
            fontSize: responsive.font(13.6),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// A block of reading text inside a section's card.
class _Prose extends StatelessWidget {
  const _Prose(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return Text(
      text,
      style: GoogleFonts.inter(
        color: context.colors.inkSoft,
        fontSize: responsive.font(13.2),
        fontWeight: FontWeight.w400,
        height: 1.55,
      ),
    );
  }
}

/// Several labelled passages in one card, divided by hairlines.
class _LabelledProse extends StatelessWidget {
  const _LabelledProse({required this.entries});

  final List<(String, String)> entries;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < entries.length; i++) ...[
          if (i > 0) const CardDivider(),
          Text(
            entries[i].$1,
            style: GoogleFonts.inter(
              color: colors.ink,
              fontSize: responsive.font(13.6),
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
          SizedBox(height: responsive.s(6)),
          _Prose(entries[i].$2),
        ],
      ],
    );
  }
}

/// How many interactions the reference holds for this medicine, by tier — the
/// safety report's "At a glance" row, so a count reads the same on both pages.
class _InteractionSummary extends StatelessWidget {
  const _InteractionSummary({required this.summary});

  final Map<String, int> summary;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    // Three-tier roll-up: collapse the four stored wire levels into the app's
    // Low / Moderate / High tiers (minor → low, moderate → moderate,
    // major + contraindicated → high).
    final tiles = <({RiskLevel level, int count, Color tone})>[
      (
        level: RiskLevel.high,
        count: (summary['contraindicated'] ?? 0) + (summary['major'] ?? 0),
        tone: colors.danger,
      ),
      (
        level: RiskLevel.moderate,
        count: summary['moderate'] ?? 0,
        tone: colors.warning,
      ),
      (level: RiskLevel.low, count: summary['minor'] ?? 0, tone: colors.accent),
    ];
    final total = tiles.fold<int>(0, (n, t) => n + t.count);

    return SectionBlock(
      title: 'Known interactions',
      subtitle:
          '$total ${total == 1 ? 'interaction' : 'interactions'} on record '
          'with other medicines.',
      padding: EdgeInsets.symmetric(
        horizontal: responsive.s(6),
        vertical: responsive.s(16),
      ),
      child: Row(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: responsive.s(38),
                color: colors.border,
              ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${tiles[i].count}',
                    style: GoogleFonts.inter(
                      color: tiles[i].count == 0
                          ? colors.inkMute
                          : tiles[i].tone,
                      fontSize: responsive.font(22),
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                      letterSpacing: -0.6,
                    ),
                  ),
                  SizedBox(height: responsive.s(6)),
                  Text(
                    '${tiles[i].level.label} risk',
                    style: GoogleFonts.inter(
                      color: colors.inkMute,
                      fontSize: responsive.font(11),
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Metabolism extends StatelessWidget {
  const _Metabolism({required this.records});

  final List<DrugEnzymeRecord> records;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final grouped = <String, Set<String>>{};
    for (final r in records) {
      grouped.putIfAbsent(r.enzymeName, () => {}).addAll(r.actions);
    }
    final entries = grouped.entries.toList(growable: false);

    return SectionBlock(
      title: 'Metabolism',
      subtitle: 'Enzymes involved in processing this medicine.',
      action: '${entries.length}',
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) const CardDivider(),
            Row(
              children: [
                Expanded(
                  child: Text(
                    entries[i].key,
                    style: GoogleFonts.inter(
                      color: colors.ink,
                      fontSize: responsive.font(13.2),
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
                SizedBox(width: responsive.s(12)),
                Text(
                  entries[i].value.map(_sentenceCase).join(' · '),
                  style: GoogleFonts.inter(
                    color: colors.accent,
                    fontSize: responsive.font(12.2),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BulletList extends StatelessWidget {
  const _BulletList({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final dot = responsive.s(6).clamp(5.0, 7.0).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) SizedBox(height: responsive.s(10)),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: dot,
                height: dot,
                margin: EdgeInsets.only(top: responsive.s(8)),
                decoration: BoxDecoration(
                  color: colors.accent,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: responsive.s(11)),
              Expanded(child: _Prose(items[i])),
            ],
          ),
        ],
      ],
    );
  }
}

class _KeyValues extends StatelessWidget {
  const _KeyValues({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const CardDivider(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: responsive.s(120).clamp(108.0, 140.0),
                child: Text(
                  rows[i].$1,
                  style: GoogleFonts.inter(
                    color: colors.inkMute,
                    fontSize: responsive.font(12.6),
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  rows[i].$2,
                  style: GoogleFonts.inter(
                    color: colors.ink,
                    fontSize: responsive.font(13),
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({required this.labels, this.tinted = false, this.overflow});

  final List<String> labels;

  /// Teal chips for categories; neutral outlined ones for synonyms.
  final bool tinted;
  final String? overflow;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Wrap(
      spacing: responsive.s(6),
      runSpacing: responsive.s(6),
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final label in labels)
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: responsive.s(10),
              vertical: responsive.s(6),
            ),
            decoration: BoxDecoration(
              color: tinted ? colors.accentAlpha(0.10) : colors.surfaceAlt,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              label,
              style: GoogleFonts.inter(
                color: tinted ? colors.accent : colors.inkSoft,
                fontSize: responsive.font(12),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (overflow != null)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: responsive.s(6)),
            child: Text(
              overflow!,
              style: GoogleFonts.inter(
                color: colors.inkMute,
                fontSize: responsive.font(12),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}

/// Reference text with DrugBank's authoring markup removed, or null when
/// nothing readable is left.
String? _clean(String? raw) {
  if (raw == null) return null;
  final text = cleanReferenceText(raw);
  return text.isEmpty ? null : text;
}

/// Strips the markup DrugBank prose is authored in, so it reads as plain text.
///
/// The reference text arrives with citation keys (`[label,L6616]`, `[A179182]`),
/// linked terms in brackets (`[vitamin K]`), Markdown emphasis (`**Indicated**`)
/// and inline HTML (`KH<sub>2</sub>`). Printed verbatim, a monograph looks like
/// an unrendered source file. Citations are dropped, linked terms keep their
/// words, and sub/superscripts become their Unicode forms where one exists.
String cleanReferenceText(String raw) {
  var text = raw;
  // Citation keys: a bracketed, comma-separated list of reference ids.
  text = text.replaceAll(
    RegExp(
      r'\[\s*(?:label|[A-Z]{1,3}\d+)(?:\s*,\s*(?:label|[A-Z]{1,3}\d+))*\s*\]',
    ),
    '',
  );
  // Linked terms keep their text.
  text = text.replaceAllMapped(RegExp(r'\[([^\[\]]+)\]'), (m) => m[1]!);
  text = text.replaceAll('**', '');
  text = text.replaceAllMapped(
    RegExp(r'<sub>(.*?)</sub>', caseSensitive: false),
    (m) => _mapScript(m[1]!, _subscripts),
  );
  text = text.replaceAllMapped(
    RegExp(r'<sup>(.*?)</sup>', caseSensitive: false),
    (m) => _mapScript(m[1]!, _superscripts),
  );
  text = text.replaceAll(RegExp(r'<[^>]+>'), '');
  // Tidy the gaps a removed citation leaves behind.
  text = text.replaceAllMapped(RegExp(r'[ \t]+([.,;:)])'), (m) => m[1]!);
  text = text.replaceAll(RegExp(r'[ \t]{2,}'), ' ');
  text = text.replaceAll(RegExp(r'[ \t]+\n'), '\n');
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text.trim();
}

const _subscripts = {
  '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄', //
  '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉', //
  '+': '₊', '-': '₋', '=': '₌', '(': '₍', ')': '₎',
};

const _superscripts = {
  '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴', //
  '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹', //
  '+': '⁺', '-': '⁻', '=': '⁼', '(': '⁽', ')': '⁾',
};

String _mapScript(String value, Map<String, String> table) {
  // Only convert when every character has a scripted form; a partial mapping
  // reads worse than the plain characters.
  if (!value.split('').every(table.containsKey)) return value;
  return value.split('').map((c) => table[c]!).join();
}

String _sentenceCase(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return trimmed;
  return trimmed[0].toUpperCase() + trimmed.substring(1);
}

/// Convenience helper used by callers (search results, medication tiles, the
/// safety-report cards) to push the monograph.
Future<void> openDrugMonograph(
  BuildContext context, {
  required int drugId,
  required String drugName,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => DrugMonographScreen(drugId: drugId, drugName: drugName),
    ),
  );
}
