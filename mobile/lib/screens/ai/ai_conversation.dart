import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:google_fonts/google_fonts.dart';

import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';
import '../../theme/medguard_responsive.dart';
import '../../widgets/common/app_snack.dart';
import '../../widgets/common/floating_nav_bar.dart' show SiriOrb;
import '../../widgets/common/pressable.dart';

/// Who said it.
enum AiRole { user, assistant }

/// One turn in the conversation.
@immutable
class AiMessage {
  const AiMessage({
    required this.role,
    required this.text,
    required this.at,
    this.pending = false,
  });

  factory AiMessage.fromJson(Map<String, dynamic> json) => AiMessage(
    role: json['role'] == 'user' ? AiRole.user : AiRole.assistant,
    text: json['text'] as String? ?? '',
    at: DateTime.tryParse(json['at'] as String? ?? '') ?? DateTime.now(),
  );

  final AiRole role;
  final String text;
  final DateTime at;

  /// The assistant is still composing — rendered as the thinking indicator
  /// rather than as an empty bubble.
  final bool pending;

  bool get isUser => role == AiRole.user;

  Map<String, dynamic> toJson() => {
    'role': isUser ? 'user' : 'assistant',
    'text': text,
    'at': at.toIso8601String(),
  };
}

/// A clock time on the app's 12-hour format, for a turn's meta line.
String aiTurnTime(DateTime at) {
  final hour12 = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final minute = at.minute.toString().padLeft(2, '0');
  return '$hour12:$minute ${at.hour < 12 ? 'am' : 'pm'}';
}

/// A conversation turn.
///
/// Both sides now share ONE structure — a small meta line naming the speaker
/// and the time, then the turn's body beneath it — so the thread scans as a
/// consistent, organised column rather than as two unrelated layouts. What
/// differs between them is only the *material*, which is what still makes the
/// sides instantly distinguishable:
///
///  * the user speaks in a solid brand-teal bubble, right-aligned, with the
///    corner nearest the sender squared off so it points back at them;
///  * the assistant answers on a calm surface card at full reading measure,
///    because its replies are prose and prose needs a measure, a generous
///    line-height and real padding around it.
///
/// Every turn is long-pressable to copy; the assistant's answers also carry a
/// visible copy affordance, since those are the ones people actually keep.
class AiMessageBubble extends StatelessWidget {
  const AiMessageBubble({super.key, required this.message, this.onDark = false});

  final AiMessage message;

  /// The AI page paints its own tinted canvas, so the assistant's text has to
  /// sit on that rather than on a card.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    return message.isUser
        ? _UserTurn(message: message)
        : _AssistantTurn(message: message);
  }
}

/// The small line above every turn: who is speaking and when. One type scale,
/// one colour, one height on both sides — this is the piece that gives the
/// thread its rhythm.
class _TurnMeta extends StatelessWidget {
  const _TurnMeta({required this.label, required this.time, this.leading});

  final String label;
  final String time;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final style = GoogleFonts.inter(
      fontSize: responsive.font(11),
      height: 1.0,
      letterSpacing: 0.1,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (leading != null) ...[
          leading!,
          SizedBox(width: responsive.s(8)),
        ],
        Text(
          label,
          style: style.copyWith(
            color: colors.inkSoft,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(width: responsive.s(6)),
        Container(
          width: 2.5,
          height: 2.5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.inkMute.withValues(alpha: 0.6),
          ),
        ),
        SizedBox(width: responsive.s(6)),
        Text(
          time,
          style: style.copyWith(
            color: colors.inkMute,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Copies [text] and confirms it, so a long-press never looks like it missed.
Future<void> _copyTurn(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (!context.mounted) return;
  AppSnack.show(context, 'Copied to clipboard', tone: AppSnackTone.success);
}

class _UserTurn extends StatelessWidget {
  const _UserTurn({required this.message});

  final AiMessage message;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final radius = responsive.radius(20);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          // Aligns the meta line's right edge with the bubble's, allowing for
          // the bubble's own corner curve.
          padding: EdgeInsets.only(right: responsive.s(6)),
          child: _TurnMeta(label: 'You', time: aiTurnTime(message.at)),
        ),
        SizedBox(height: responsive.s(8)),
        ConstrainedBox(
          // Never the full width: a question that runs edge to edge stops
          // reading as something the user said.
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.80,
          ),
          child: Pressable(
            onTap: () => _copyTurn(context, message.text),
            pressScale: 0.985,
            haptic: false,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: responsive.s(16),
                vertical: responsive.s(13),
              ),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF0A7F72), MedGuardPalette.teal],
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(radius),
                  topRight: Radius.circular(radius),
                  bottomLeft: Radius.circular(radius),
                  // Squared at the sender's corner.
                  bottomRight: Radius.circular(responsive.radius(7)),
                ),
                boxShadow: [
                  BoxShadow(
                    color: MedGuardPalette.teal.withValues(alpha: 0.20),
                    blurRadius: responsive.s(18),
                    spreadRadius: -4,
                    offset: Offset(0, responsive.s(8)),
                  ),
                ],
              ),
              child: Text(
                message.text,
                style: GoogleFonts.inter(
                  color: MedGuardPalette.pureWhite,
                  fontSize: responsive.font(14.6),
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AssistantTurn extends StatelessWidget {
  const _AssistantTurn({required this.message});

  final AiMessage message;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final isDark = colors.isDark;
    final mark = responsive.s(22).clamp(20.0, 26.0).toDouble();
    final radius = responsive.radius(20);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TurnMeta(
          label: 'MedGuard AI',
          time: aiTurnTime(message.at),
          // The same orb that lives in the nav — the app has one face for its
          // AI. Small here, because it is a byline and not the subject.
          leading: IgnorePointer(
            child: SiriOrb(size: mark, active: false, onTap: () {}),
          ),
        ),
        SizedBox(height: responsive.s(8)),
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: responsive.s(16),
            vertical: responsive.s(14),
          ),
          decoration: BoxDecoration(
            // A calm, near-opaque card so prose reads cleanly over the page's
            // tinted glow — the answer is the thing to read, not the backdrop.
            color: isDark
                ? MedGuardPalette.whiteAlpha(0.06)
                : colors.surface.withValues(alpha: 0.86),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(responsive.radius(7)),
              topRight: Radius.circular(radius),
              bottomLeft: Radius.circular(radius),
              bottomRight: Radius.circular(radius),
            ),
            border: Border.all(
              color: isDark
                  ? MedGuardPalette.whiteAlpha(0.09)
                  : colors.ink.withValues(alpha: 0.055),
            ),
          ),
          child: message.pending
              ? const _ThinkingDots()
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      message.text,
                      style: GoogleFonts.inter(
                        color: colors.ink,
                        fontSize: responsive.font(14.8),
                        fontWeight: FontWeight.w400,
                        // Long-form measure: these are answers, not labels.
                        height: 1.62,
                      ),
                    ),
                    SizedBox(height: responsive.s(12)),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: colors.ink.withValues(alpha: isDark ? 0.10 : 0.05),
                    ),
                    SizedBox(height: responsive.s(9)),
                    _TurnAction(
                      icon: Icons.copy_rounded,
                      label: 'Copy answer',
                      onTap: () => _copyTurn(context, message.text),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// A quiet text action beneath an answer.
class _TurnAction extends StatelessWidget {
  const _TurnAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Align(
      alignment: Alignment.centerLeft,
      child: Pressable(
        onTap: onTap,
        pressScale: 0.95,
        semanticLabel: label,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: responsive.s(2)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: responsive.icon(13), color: colors.inkMute),
              SizedBox(width: responsive.s(6)),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: colors.inkMute,
                  fontSize: responsive.font(11.5),
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The assistant composing: three dots rising and falling in sequence.
/// Deliberately not a spinner — a spinner says "loading", this says "typing".
class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cycle;

  static bool get _underTest => WidgetsBinding.instance.runtimeType
      .toString()
      .contains('AutomatedTest');

  @override
  void initState() {
    super.initState();
    _cycle = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (!_underTest) _cycle.repeat();
  }

  @override
  void dispose() {
    _cycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final dot = responsive.s(7).clamp(6.0, 9.0).toDouble();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _cycle,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < 3; i++) ...[
                  Builder(
                    builder: (context) {
                      // Each dot is a third of a cycle behind the last, so the
                      // motion travels rather than pulsing in unison.
                      final phase = (_cycle.value - i * 0.18) % 1.0;
                      final lift = phase < 0.5
                          ? Curves.easeOut.transform(phase * 2)
                          : Curves.easeIn.transform((1 - phase) * 2);
                      return Transform.translate(
                        offset: Offset(0, -lift * dot * 0.7),
                        child: Container(
                          width: dot,
                          height: dot,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.accent.withValues(
                              alpha: 0.35 + lift * 0.55,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  if (i != 2) SizedBox(width: dot * 0.7),
                ],
              ],
            );
          },
        ),
        SizedBox(width: responsive.s(10)),
        Text(
          'Thinking…',
          style: GoogleFonts.inter(
            color: colors.inkMute,
            fontSize: responsive.font(13),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
