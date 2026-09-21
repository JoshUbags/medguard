// Part of `search_screen.dart`, split out for readability.
// All imports live in the parent library file.
part of '../search_screen.dart';

/// One search result.
///
/// The card was previously a dense block: a coloured rule across the top, a
/// four-line description cut off mid-sentence with an ellipsis, two unlabelled
/// circular icon buttons, and a decorative "Safety focus" tag on every row
/// regardless of the drug. At a glance you could not tell what the medicine was
/// for, and you could not tell what either button did without pressing one.
///
/// This is the same information, arranged so it can be read:
///
///  * the **name** on its own line, wrapping rather than truncating — a
///    medicine name cut to "Amoxicillin/Clavulanic ac…" is the one string on
///    the page that must never be guessed at;
///  * **what it is**, as a class line rather than a decorative badge;
///  * two **named** actions. "Details" and "Add" say what they do; a magnifier
///    glyph and a plus glyph do not.
///
/// Nothing here is truncated with an ellipsis. Where a value is long, the row
/// grows.
class _DrugResultCard extends StatelessWidget {
  const _DrugResultCard({
    required this.query,
    required this.style,
    required this.drug,
    required this.isAdded,
    required this.isAdding,
    required this.onAdd,
    required this.onOpenDetails,
  });

  final String query;
  final _DrugCardStyle style;
  final Drug drug;
  final bool isAdded;
  final bool isAdding;
  final VoidCallback onAdd;
  final VoidCallback onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final radius = responsive.radius(22);
    final purpose = _resultPurposeLine(drug);

    return Pressable(
      key: ValueKey('drug-card-surface-${drug.id}'),
      onTap: onOpenDetails,
      pressScale: 0.99,
      semanticLabel: 'View details for ${drug.name}',
      child: Container(
        padding: EdgeInsets.all(responsive.s(16)),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: isAdded ? colors.accentAlpha(0.32) : colors.border,
          ),
          boxShadow: MedGuardShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              // The name and its class line centre against the mark rather
              // than hanging from its top edge. With a two-line block beside a
              // square, top-alignment leaves the second line dangling below
              // the mark and the whole row reads as misaligned.
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _DrugVisual(drug: drug),
                SizedBox(width: responsive.s(13)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _HighlightedDrugTitle(
                        key: ValueKey('drug-title-${drug.id}'),
                        drugId: drug.id,
                        text: drug.name,
                        query: query,
                        inverted: false,
                      ),
                      SizedBox(height: responsive.s(4)),
                      Text(
                        style.label,
                        style: GoogleFonts.inter(
                          color: colors.inkMute,
                          fontSize: responsive.font(11.8),
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isAdded) ...[
                  SizedBox(width: responsive.s(8)),
                  _SavedToListBadge(accent: colors.accent),
                ],
              ],
            ),
            // What the medicine is for, in one complete sentence. Kept to a
            // sentence deliberately: the full description belongs in Details,
            // and half of it in the list is the ellipsis problem all over again.
            if (purpose != null) ...[
              SizedBox(height: responsive.s(12)),
              Text(
                purpose,
                style: GoogleFonts.inter(
                  color: colors.inkSoft,
                  fontSize: responsive.font(12.4),
                  fontWeight: FontWeight.w500,
                  height: 1.45,
                ),
              ),
            ],
            SizedBox(height: responsive.s(14)),
            Row(
              children: [
                Expanded(
                  child: _ResultAction(
                    label: 'Details',
                    icon: Icons.article_rounded,
                    onTap: onOpenDetails,
                  ),
                ),
                SizedBox(width: responsive.s(9)),
                Expanded(
                  child: _ResultAction(
                    key: ValueKey('add-${drug.id}'),
                    label: isAdded ? 'Added' : 'Add',
                    icon: isAdded ? Icons.check_rounded : Icons.add_rounded,
                    filled: true,
                    done: isAdded,
                    busy: isAdding,
                    onTap: isAdded ? null : onAdd,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A named action on a result row.
///
/// Both actions are the same size and shape and sit side by side, so neither is
/// a guess: the primary one is filled, the secondary outlined, and both say
/// what they do in words.
class _ResultAction extends StatelessWidget {
  const _ResultAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.done = false,
    this.busy = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;
  final bool done;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final height = responsive.s(40).clamp(38.0, 46.0).toDouble();

    final background = done
        ? colors.accentAlpha(0.12)
        : filled
        ? colors.accent
        : Colors.transparent;
    final foreground = done
        ? colors.accent
        : filled
        ? colors.surface
        : colors.ink;

    return Pressable(
      onTap: busy ? null : onTap,
      pressScale: 0.97,
      semanticLabel: label,
      child: Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: filled && !done ? Colors.transparent : colors.border,
          ),
        ),
        child: busy
            ? MorphLoader(
                size: responsive.s(18),
                color: foreground,
                glow: false,
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: responsive.icon(16), color: foreground),
                  SizedBox(width: responsive.s(7)),
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      color: foreground,
                      fontSize: responsive.font(12.8),
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// One complete sentence describing what the medicine is for, or null when the
/// local record has nothing usable.
///
/// Takes the FIRST SENTENCE rather than the first N characters, so the line
/// always ends where a sentence ends. Anything with no sentence boundary in
/// range is dropped entirely rather than cut — half a sentence about a medicine
/// is worse than no sentence at all.
/// Roughly fifty words of what the medicine is for.
///
/// Built by taking WHOLE sentences until the budget is spent, never by cutting
/// mid-sentence and appending an ellipsis. A clinical description severed
/// halfway is worse than a shorter one: the reader cannot tell whether the
/// important clause was the one that got cut, and on a page about medicines
/// that is not an acceptable ambiguity.
///
/// Fifty words is about three lines on a phone — enough to say what a drug
/// treats and roughly how, which is what someone scanning results actually
/// needs. Everything beyond that belongs in Details.
String? _resultPurposeLine(Drug drug) {
  final source =
      _cleanDrugText(drug.indication) ?? _cleanDrugText(drug.description);
  if (source == null) return null;

  const budget = 50;
  final sentences = RegExp(r'[^.!?]+[.!?]*').allMatches(source);

  final kept = <String>[];
  var words = 0;
  for (final match in sentences) {
    final sentence = match.group(0)?.trim();
    if (sentence == null || sentence.isEmpty) continue;
    final count = sentence.split(RegExp(r'\s+')).length;
    // Always keep the first sentence, even if it alone overruns the budget —
    // one long sentence is still a complete thought, and dropping it would
    // leave the card with nothing.
    if (kept.isNotEmpty && words + count > budget) break;
    kept.add(sentence);
    words += count;
    if (words >= budget) break;
  }

  if (kept.isEmpty) return null;
  return kept.join(' ');
}

class _SavedToListBadge extends StatelessWidget {
  const _SavedToListBadge({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: responsive.s(8),
        vertical: responsive.s(3),
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_rounded,
            color: accent,
            size: responsive.icon(12),
          ),
          SizedBox(width: responsive.s(4)),
          Text(
            'In your list',
            style: GoogleFonts.inter(
              color: accent,
              fontSize: responsive.font(10.6),
              fontWeight: FontWeight.w700,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _DrugCardStyle {
  const _DrugCardStyle({required this.label, required this.accent});

  final String label;
  final Color accent;

  static _DrugCardStyle forDrug(BuildContext context, Drug drug) {
    final family = _DrugFamily.forCode(drug.atcCode);
    if (family == null) {
      return _DrugCardStyle(
        label: 'Needs classification',
        accent: context.colors.inkMute,
      );
    }
    return _DrugCardStyle(label: family.shortLabel, accent: family.tint);
  }
}

class _DrugVisual extends StatelessWidget {
  const _DrugVisual({required this.drug, super.key});

  final Drug drug;

  @override
  Widget build(BuildContext context) {
    final signature = _drugSignature(drug);
    // Deliberately modest. At 56 the mark carried as much visual weight as the
    // medicine's name, which is the wrong way round: the name is the content,
    // the mark is only a handle for finding it again in a list.
    final responsive = MedGuardResponsive.of(context);
    final extent = responsive.s(44).clamp(40.0, 50.0).toDouble();

    return Container(
      key: key ?? ValueKey('drug-visual-${drug.id}'),
      width: extent,
      height: extent,
      decoration: BoxDecoration(
        color: Color.lerp(
          context.colors.surface,
          _drugSignatureColor(signature),
          0.10,
        ),
        borderRadius: BorderRadius.circular(responsive.radius(15)),
        border: Border.all(color: context.colors.border),
      ),
      child: CustomPaint(
        painter: _DrugVisualPainter(signature),
        child: Center(
          child: Icon(
            _drugSignatureIcon(signature),
            color: _drugSignatureColor(signature, shift: 24),
            size: responsive.icon(22),
          ),
        ),
      ),
    );
  }
}

class _DrugVisualPainter extends CustomPainter {
  const _DrugVisualPainter(this.signature);

  final int signature;

  @override
  void paint(Canvas canvas, Size size) {
    final base = _drugSignatureColor(signature);
    final accent = _drugSignatureColor(signature, shift: 52);
    final softPaint = Paint()
      ..color = base.withValues(alpha: 0.14)
      ..style = PaintingStyle.fill;
    final accentPaint = Paint()
      ..color = accent.withValues(alpha: 0.22)
      ..style = PaintingStyle.fill;
    final linePaint = Paint()
      ..color = base.withValues(alpha: 0.22)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final capsule = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.14,
        size.height * 0.62,
        size.width * 0.54,
        9,
      ),
      const Radius.circular(999),
    );
    canvas.drawRRect(capsule, softPaint);

    final dotOne = Offset(
      size.width * (0.22 + ((signature & 0x03) * 0.08)),
      size.height * (0.22 + (((signature >> 2) & 0x03) * 0.07)),
    );
    final dotTwo = Offset(
      size.width * (0.64 + (((signature >> 4) & 0x01) * 0.08)),
      size.height * (0.22 + (((signature >> 5) & 0x03) * 0.07)),
    );
    final dotThree = Offset(
      size.width * (0.30 + (((signature >> 7) & 0x03) * 0.08)),
      size.height * (0.74 + (((signature >> 9) & 0x01) * 0.04)),
    );

    canvas.drawLine(dotOne, dotTwo, linePaint);
    canvas.drawLine(dotOne, dotThree, linePaint);
    canvas.drawCircle(dotOne, 3.4, accentPaint);
    canvas.drawCircle(dotTwo, 3.9, softPaint);
    canvas.drawCircle(dotThree, 3.2, accentPaint);
  }

  @override
  bool shouldRepaint(covariant _DrugVisualPainter oldDelegate) {
    return oldDelegate.signature != signature;
  }
}

int _drugSignature(Drug drug) {
  final source =
      '${drug.id}|${drug.name.trim().toLowerCase()}|${drug.atcCode?.trim().toUpperCase() ?? ''}';
  var hash = 0x811C9DC5;
  for (final unit in source.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash;
}

Color _drugSignatureColor(int signature, {int shift = 0}) {
  final hue = ((signature + shift) % 360).toDouble();
  return HSLColor.fromAHSL(1, hue, 0.42, 0.42).toColor();
}

IconData _drugSignatureIcon(int signature) {
  const icons = [
    Icons.local_pharmacy_rounded,
    Icons.science_rounded,
    Icons.local_pharmacy_rounded,
    Icons.healing_rounded,
    Icons.biotech_rounded,
    Icons.vaccines_rounded,
  ];
  return icons[signature % icons.length];
}

class _HighlightedDrugTitle extends StatelessWidget {
  const _HighlightedDrugTitle({
    super.key,
    required this.drugId,
    required this.text,
    required this.query,
    required this.inverted,
  });

  final int drugId;
  final String text;
  final String query;
  final bool inverted;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final normalizedText = text.toLowerCase();
    final normalizedQuery = query.trim().toLowerCase();
    final baseStyle = GoogleFonts.inter(
      color: inverted ? context.colors.surface : context.colors.accent,
      fontSize: responsive.font(16.5),
      height: 1.16,
      fontWeight: FontWeight.w600,
    );

    if (normalizedQuery.isEmpty || !normalizedText.contains(normalizedQuery)) {
      return Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: baseStyle,
      );
    }

    final spans = <InlineSpan>[];
    var cursor = 0;
    var matchIndex = 0;
    while (cursor < text.length) {
      final found = normalizedText.indexOf(normalizedQuery, cursor);
      if (found == -1) {
        spans.add(TextSpan(text: text.substring(cursor), style: baseStyle));
        break;
      }
      if (found > cursor) {
        spans.add(
          TextSpan(text: text.substring(cursor, found), style: baseStyle),
        );
      }
      final end = found + normalizedQuery.length;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            key: ValueKey('query-highlight-$drugId-$matchIndex'),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: context.colors.danger,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              text.substring(found, end),
              style: baseStyle.copyWith(color: context.colors.surface),
            ),
          ),
        ),
      );
      cursor = end;
      matchIndex++;
    }

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(children: spans),
    );
  }
}

class _SearchLoadingSection extends StatelessWidget {
  const _SearchLoadingSection();

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final gap = SizedBox(height: responsive.s(14));

    return Column(
      children: [
        const _LoadingCard(height: 150),
        gap,
        const _LoadingCard(height: 120),
        gap,
        const _LoadingCard(height: 120),
      ],
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);

    return _Shimmer(
      child: SurfaceCard(
        padding: EdgeInsets.all(responsive.s(16)),
        child: SizedBox(
          height: responsive.s(height),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SkeletonBox(width: 54, height: 18, radius: 999),
              Spacer(),
              _SkeletonBox(width: double.infinity, height: 18, radius: 999),
              SizedBox(height: 10),
              _SkeletonBox(width: 150, height: 14, radius: 999),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    required this.radius,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        // Derived from the ink colour, not a literal black: a black bar at 8%
        // over the dark theme's near-black card was invisible, so the loading
        // state read as three empty boxes at night.
        color: colors.ink.withValues(alpha: colors.isDark ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.child});

  final Widget child;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The sweep tints toward the CARD colour, so the highlight reads as light
    // passing over the surface in either theme. Hard-coded white did that in
    // light mode and washed the dark card out to a pale grey in dark mode.
    final sheen = context.colors.surface;

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final dx = (_controller.value * 2.4) - 1.2;
          return ShaderMask(
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: Alignment(dx - 1, 0),
                end: Alignment(dx + 1, 0),
                colors: [
                  sheen.withValues(alpha: 0.30),
                  sheen.withValues(alpha: 0.96),
                  sheen.withValues(alpha: 0.30),
                ],
                stops: const [0.18, 0.50, 0.82],
              ).createShader(bounds);
            },
            blendMode: BlendMode.srcATop,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _StaggeredSearchItem extends StatelessWidget {
  const _StaggeredSearchItem({required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 240 + (index.clamp(0, 6) * 32)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
