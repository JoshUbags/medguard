import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/ai_chat_store.dart';
import '../../services/auth_profile_preferences.dart';
import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';
import '../../theme/medguard_responsive.dart';
import '../../theme/medguard_spacing.dart';
import '../../widgets/common/app_snack.dart';
import '../../widgets/common/floating_nav_bar.dart';
import '../../widgets/common/glass_surface.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/pressable.dart';
import '../profile/profile_screen.dart';
import '../search/search_screen.dart';
import 'ai_conversation.dart';
import '../../widgets/common/morph_loader.dart';
import '../../widgets/common/modal_sheet.dart';

/// An opener on the empty state — a glyph and a real question, sized to its
/// text so the four flow naturally rather than sitting in a rigid grid.
class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({
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
    return Pressable(
      onTap: onTap,
      pressScale: 0.95,
      semanticLabel: label,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: responsive.s(13),
          vertical: responsive.s(9),
        ),
        decoration: BoxDecoration(
          color: colors.surface.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(100),
          border: Border.all(color: colors.accentAlpha(0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: colors.accent, size: responsive.icon(14)),
            SizedBox(width: responsive.s(7)),
            Text(
              label,
              style: GoogleFonts.inter(
                color: colors.inkSoft,
                fontSize: responsive.font(12.6),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The MedGuard AI tab — an immersive, full-screen assistant home that follows
/// the app's light/dark theme and its shared spacing, margin and type scale.
///
/// The bottom nav is hidden here; navigation to the rest of the app happens
/// through the side menu (top-left). Sending is an honest "coming soon" until
/// the conversational backend lands — but the *chat* itself is fully real:
/// conversations are kept on the device, "New chat" genuinely starts a new one,
/// and Recents lists the threads you can go back to.
class AiScreen extends StatefulWidget {
  const AiScreen({
    super.key,
    this.showNavigation = true,
    this.bottomContentPadding = 0,
    this.currentTab,
    this.onSelectTab,
    this.onOpenProfile,
  });

  static const String routeName = '/ai';

  final bool showNavigation;
  final double bottomContentPadding;

  /// The shell's current tab, so the side menu can mark the active page. Null
  /// when the screen is shown standalone.
  final AppNavTab? currentTab;

  /// Switches the host shell's tab from the side menu. Null when standalone —
  /// the menu then falls back to named-route navigation.
  final ValueChanged<AppNavTab>? onSelectTab;

  /// Opens the profile screen. Null when standalone.
  final VoidCallback? onOpenProfile;

  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _thread = ScrollController();
  late final String _prompt;

  final AiChatStore _store = AiChatStore.instance;
  StreamSubscription<List<AiChatSession>>? _storeSubscription;

  /// The conversation on screen. A fresh, unsaved session until the first
  /// question is asked.
  AiChatSession _session = AiChatSession.fresh();

  /// Saved conversations, newest first, for the drawer's Recents list.
  List<AiChatSession> _recents = const <AiChatSession>[];

  /// The conversation so far. Empty means the opening state.
  List<AiMessage> get _messages => _session.messages;

  /// True while a question is being handed off, so the send button shows real
  /// progress instead of the tap appearing to do nothing.
  bool _sending = false;

  /// Openers offered on the empty state. Real questions the app can eventually
  /// answer, not filler — a blank prompt is the hardest thing to start from.
  static const List<(IconData, String)> _suggestions = [
    (Icons.swap_horiz_rounded, 'Do any of my medicines clash?'),
    (Icons.restaurant_rounded, 'What should I avoid eating?'),
    (Icons.schedule_rounded, 'When is my next dose due?'),
    (Icons.help_outline_rounded, 'What is this medicine for?'),
  ];

  // A different, warm prompt each time the assistant is opened.
  static const List<String> _prompts = [
    'How can I help you today?',
    'What can I look into for you?',
    'Ask me anything about your meds.',
    'What would you like to check?',
    'How can I support your care?',
    'What can I clear up for you?',
  ];

  @override
  void initState() {
    super.initState();
    _prompt = _prompts[DateTime.now().millisecondsSinceEpoch % _prompts.length];
    _input.addListener(() => setState(() {}));
    // History is device-local and tiny, so it loads without a spinner; the
    // drawer simply fills in the moment it resolves.
    _storeSubscription = _store.changes.listen((sessions) {
      if (!mounted) return;
      setState(() => _recents = sessions);
    });
    unawaited(
      _store.load().then((sessions) {
        if (!mounted) return;
        setState(() => _recents = sessions);
      }),
    );
  }

  @override
  void dispose() {
    // A conversation left open when the tab is torn down is still a real
    // conversation — persist it rather than losing it.
    unawaited(_store.save(_session));
    _storeSubscription?.cancel();
    _input.dispose();
    _inputFocus.dispose();
    _thread.dispose();
    super.dispose();
  }

  String? _displayName() {
    String? firebaseName;
    try {
      firebaseName = FirebaseAuth.instance.currentUser?.displayName;
    } catch (_) {}
    final resolved = AuthProfilePreferences.resolveDisplayName(
      firebaseDisplayName: firebaseName,
      fallback: '',
    );
    return resolved.isEmpty ? null : resolved;
  }

  String? _photoUrl() {
    try {
      final url = FirebaseAuth.instance.currentUser?.photoURL?.trim();
      return (url != null && url.isNotEmpty) ? url : null;
    } catch (_) {
      return null;
    }
  }

  String _firstName() {
    final name = _displayName();
    if (name == null) return 'there';
    return name.split(RegExp(r'\s+')).first;
  }

  void _openProfile() {
    final handler = widget.onOpenProfile;
    if (handler != null) {
      handler();
      return;
    }
    Navigator.of(context).pushNamed(ProfileScreen.routeName);
  }

  void _goToTab(AppNavTab tab) {
    Navigator.of(context).pop(); // close the drawer
    final handler = widget.onSelectTab;
    if (handler != null) {
      handler(tab);
      return;
    }
    Navigator.of(context).pushReplacementNamed(tab.route);
  }

  /// Starts a fresh conversation, filing the current one under Recents first so
  /// nothing is thrown away by pressing "New chat".
  Future<void> _startNewChat({bool announce = true}) async {
    if (_sending) return;
    final hadContent = _session.hasContent;
    if (hadContent) await _store.save(_session);
    if (!mounted) return;
    setState(() {
      _session = AiChatSession.fresh();
      _input.clear();
    });
    if (announce && hadContent && mounted) {
      AppSnack.show(context, 'Saved to Recents. New chat started.',
          tone: AppSnackTone.success);
    }
  }

  /// Reopens a saved conversation, filing the current one first.
  Future<void> _openSession(AiChatSession session) async {
    if (session.id == _session.id) return;
    if (_session.hasContent) await _store.save(_session);
    if (!mounted) return;
    setState(() {
      _session = session;
      _input.clear();
    });
    _scrollToEnd();
  }

  Future<void> _deleteSession(AiChatSession session) async {
    await _store.delete(session.id);
    if (!mounted) return;
    // Deleting the conversation you are reading leaves you on a blank page,
    // not on a thread that no longer exists anywhere.
    if (session.id == _session.id) {
      setState(() => _session = AiChatSession.fresh());
    }
    if (mounted) AppSnack.show(context, 'Conversation deleted');
  }

  /// Sends the typed question into the thread.
  ///
  /// The conversational backend is not live yet, so the assistant answers with
  /// an honest note about that rather than a fabricated clinical reply — but
  /// the thread, the thinking indicator and the scroll behaviour are all real,
  /// which is what the interface has to get right before the model arrives.
  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) {
      _inputFocus.requestFocus();
      return;
    }
    final now = DateTime.now();
    setState(() {
      _sending = true;
      _messages.add(AiMessage(role: AiRole.user, text: text, at: now));
      _messages.add(
        AiMessage(role: AiRole.assistant, text: '', at: now, pending: true),
      );
    });
    _input.clear();
    _scrollToEnd();

    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() {
      _sending = false;
      _messages
        ..removeLast()
        ..add(
          AiMessage(
            role: AiRole.assistant,
            text:
                "I'm not connected to my clinical brain yet — MedGuard AI is "
                "still being built, so I can't answer that properly and I'd "
                'rather say so than guess.\n\nIn the meantime, the Interactions'
                ' tab will review your regimen, and Dose tracks what you have '
                'taken.',
            at: DateTime.now(),
          ),
        );
    });
    _scrollToEnd();
    // The thread is only history once the turn is complete.
    unawaited(_store.save(_session));
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_thread.hasClients) return;
      _thread.animateTo(
        _thread.position.maxScrollExtent,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _askSuggestion(String prompt) {
    _input.text = prompt;
    unawaited(_send());
  }

  /// The opening state: the orb, a greeting, and four real questions to start
  /// from. Optically centred between the bar and the input, and scrollable so a
  /// short phone with the keyboard up never clips it.
  Widget _buildOpening(
    MedGuardResponsive responsive,
    MedGuardColors colors,
    double orbSize,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          // Dragging closes the keyboard, so the field is dismissible without
          // hunting for a blank spot to tap.
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: responsive.pageX),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _GlowingOrb(size: orbSize),
                  SizedBox(height: responsive.s(28)),
                  Text(
                    'Hello, ${_firstName()}',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: colors.inkSoft,
                      fontSize: responsive.font(19),
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                      letterSpacing: -0.2,
                    ),
                  ),
                  SizedBox(height: responsive.s(10)),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 340),
                    child: Text(
                      _prompt,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: colors.ink,
                        fontSize: responsive.font(26),
                        fontWeight: FontWeight.w600,
                        height: 1.22,
                        letterSpacing: -0.6,
                      ),
                    ),
                  ),
                  SizedBox(height: responsive.s(26)),
                  // Openers. A blank prompt is the hardest thing to start
                  // from, so the page offers four real questions instead of
                  // waiting for one.
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: responsive.s(8),
                    runSpacing: responsive.s(8),
                    children: [
                      for (final (icon, prompt) in _suggestions)
                        _SuggestionChip(
                          icon: icon,
                          label: prompt,
                          onTap: () => _askSuggestion(prompt),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// The conversation.
  ///
  /// The thread opens with a date stamp so a reopened chat says when it
  /// happened, then runs turn by turn. Spacing is rhythmic rather than uniform:
  /// a wide beat where the speaker changes, a tighter one between consecutive
  /// turns from the same side. That difference is what lets the eye find the
  /// boundaries of an exchange without reading it.
  Widget _buildThread(MedGuardResponsive responsive) {
    return ListView.separated(
      controller: _thread,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(
        responsive.pageX,
        responsive.s(8),
        responsive.pageX,
        responsive.s(14),
      ),
      // One leading item for the date stamp, then the turns.
      itemCount: _messages.length + 1,
      separatorBuilder: (context, index) {
        if (index == 0) return SizedBox(height: responsive.s(20));
        final message = _messages[index - 1];
        final next = index < _messages.length ? _messages[index] : null;
        final changed = next != null && message.role != next.role;
        return SizedBox(
          height: responsive.s(changed ? 26 : 14).clamp(12.0, 32.0).toDouble(),
        );
      },
      itemBuilder: (context, index) {
        if (index == 0) return _ThreadDateStamp(at: _messages.first.at);
        return AiMessageBubble(message: _messages[index - 1]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    // The orb shrinks while the keyboard is up so the empty state still fits
    // above the field on a short phone instead of being scrolled out of view.
    final orbSize =
        (keyboardInset > 0
                ? responsive.s(92).clamp(76.0, 108.0)
                : responsive.s(128).clamp(104.0, 150.0))
            .toDouble();
    final hasThread = _messages.isNotEmpty;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: medGuardSystemUi(colors),
      child: Scaffold(
        backgroundColor: colors.scaffold,
        drawer: _AiDrawer(
          currentTab: widget.currentTab,
          sessions: _recents,
          activeSessionId: _session.id,
          onSelectTab: _goToTab,
          onNewChat: () {
            Navigator.of(context).pop();
            unawaited(_startNewChat());
          },
          onOpenSession: (session) {
            Navigator.of(context).pop();
            unawaited(_openSession(session));
          },
          onDeleteSession: (session) => unawaited(_deleteSession(session)),
          onOpenSearch: () {
            Navigator.of(context).pop();
            Navigator.of(context).pushNamed(SearchScreen.routeName);
          },
        ),
        body: Stack(
          children: [
            Positioned.fill(
              child: _AiBackground(base: colors.scaffold, isDark: colors.isDark),
            ),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.only(
                      top: MedGuardSpacing.screenTop(responsive),
                    ),
                    child: _AiTopBar(
                      name: _displayName(),
                      photoUrl: _photoUrl(),
                      onProfile: _openProfile,
                      // "New chat" belongs in reach of the thumb, not two taps
                      // deep in a drawer — it only appears once there is a
                      // conversation there is any point leaving.
                      onNewChat: hasThread
                          ? () => unawaited(_startNewChat())
                          : null,
                      title: hasThread ? _session.title : null,
                    ),
                  ),
                  Expanded(
                    child: hasThread
                        ? _buildThread(responsive)
                        : _buildOpening(responsive, colors, orbSize),
                  ),
                  // The input rides above the keyboard: viewInsets is the
                  // keyboard's height, and the safe-area inset only applies
                  // when it is down (otherwise the field floats above a gap).
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      responsive.pageX,
                      responsive.s(10),
                      responsive.pageX,
                      keyboardInset > 0
                          ? keyboardInset + responsive.s(10)
                          : safeBottom + responsive.s(12),
                    ),
                    child: _AiInputBar(
                      controller: _input,
                      focusNode: _inputFocus,
                      hasText: _input.text.trim().isNotEmpty,
                      sending: _sending,
                      onSend: () => unawaited(_send()),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The day a conversation happened, centred above its first turn. Reads
/// "Today" / "Yesterday" for the recent ones, because that is how people
/// actually refer to them.
class _ThreadDateStamp extends StatelessWidget {
  const _ThreadDateStamp({required this.at});

  final DateTime at;

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _label() {
    final now = DateTime.now();
    final day = DateTime(at.year, at.month, at.day);
    final today = DateTime(now.year, now.month, now.day);
    final delta = today.difference(day).inDays;
    if (delta == 0) return 'Today';
    if (delta == 1) return 'Yesterday';
    return '${at.day} ${_months[at.month - 1]} ${at.year}';
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Center(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: responsive.s(12),
          vertical: responsive.s(6),
        ),
        decoration: BoxDecoration(
          color: colors.isDark
              ? MedGuardPalette.whiteAlpha(0.07)
              : colors.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: colors.ink.withValues(alpha: colors.isDark ? 0.10 : 0.05),
          ),
        ),
        child: Text(
          _label(),
          style: GoogleFonts.inter(
            color: colors.inkMute,
            fontSize: responsive.font(11),
            fontWeight: FontWeight.w700,
            height: 1.0,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

/// The top bar — the side-menu button on the left, the profile avatar (with its
/// live connection dot, at the app-standard header size) on the right, and,
/// once a conversation exists, the chat's own name between them with a
/// new-chat control beside the avatar.
class _AiTopBar extends StatelessWidget {
  const _AiTopBar({
    required this.name,
    required this.photoUrl,
    required this.onProfile,
    this.onNewChat,
    this.title,
  });

  final String? name;
  final String? photoUrl;
  final VoidCallback onProfile;

  /// Starts a fresh conversation. Null on the opening state, where the thread
  /// is already new and the control would be a no-op.
  final VoidCallback? onNewChat;

  /// The active conversation's name, shown only when there is one.
  final String? title;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final size = headerAvatarSize(responsive);
    final chatTitle = title;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: responsive.pageX),
      child: Row(
        children: [
          _CircleIconButton(
            icon: Icons.menu_rounded,
            size: size,
            semanticLabel: 'Open menu',
            onTap: () => Scaffold.of(context).openDrawer(),
          ),
          if (chatTitle == null)
            const Spacer()
          else
            // The thread's name identifies WHICH conversation is on screen —
            // essential the moment Recents can put you in a different one.
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: responsive.s(10)),
                child: Text(
                  chatTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: colors.ink,
                    fontSize: responsive.font(14),
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
          // The avatar sits in the app's shared glass capsule here too, so the
          // profile control is the same object at the same size on this page as
          // on every other.
          HeaderGlassActions(
            key: const ValueKey('ai-header-actions'),
            avatarSize: size,
            name: name,
            photoUrl: photoUrl,
            onAvatarTap: onProfile,
            avatarKey: const ValueKey('ai-header-avatar'),
            actions: [
              if (onNewChat != null)
                _CircleIconButton(
                  key: const ValueKey('ai-new-chat'),
                  icon: Icons.add_rounded,
                  size: size,
                  semanticLabel: 'New chat',
                  onTap: onNewChat!,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The app's standard round icon control — the same disc, size, fill and
/// hairline the notification bell and the Dose add button use, carrying a plain
/// rounded icon from the one icon family the rest of the app draws from.
class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    super.key,
    required this.icon,
    required this.size,
    required this.onTap,
    required this.semanticLabel,
  });

  final IconData icon;
  final double size;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = colors.isDark;

    return Pressable(
      onTap: onTap,
      pressScale: 0.9,
      semanticLabel: semanticLabel,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark
              ? MedGuardPalette.whiteAlpha(0.08)
              : colors.surface.withValues(alpha: 0.92),
          border: Border.all(
            color: isDark
                ? MedGuardPalette.whiteAlpha(0.10)
                : colors.ink.withValues(alpha: 0.06),
          ),
        ),
        child: Icon(icon, color: colors.ink, size: size * 0.48),
      ),
    );
  }
}

/// The orb with a soft teal glow halo behind it, so it reads as a light source
/// on the canvas in either theme.
class _GlowingOrb extends StatelessWidget {
  const _GlowingOrb({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 1.8,
      height: size * 1.8,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * 1.8,
            height: size * 1.8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  MedGuardPalette.tealLight.withValues(alpha: 0.34),
                  MedGuardPalette.teal.withValues(alpha: 0.10),
                  MedGuardPalette.teal.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 0.45, 1.0],
              ),
            ),
          ),
          SiriOrb(size: size, active: true, onTap: () {}),
        ],
      ),
    );
  }
}

/// The composer.
///
/// One pane of WHITE glass — the tint is white in both themes rather than the
/// theme's own surface, so the composer reads as a lit pane of glass laid over
/// the page instead of dissolving into a dark canvas. Nothing is layered on top
/// of it beyond its own rim: an earlier version stacked a gloss sheen and a
/// second inner catch-light inside the same pill, which at this size read as
/// two borders drawn a pixel apart rather than as one lit edge.
///
/// The layout is a single row on one centre line: the field, then the send
/// button inset by exactly half the space it has spare, so the pill reads
/// optically even end to end. The field grows to four lines as you type and
/// stops there — long questions stay readable without the composer eating the
/// conversation above it.
class _AiInputBar extends StatelessWidget {
  const _AiInputBar({
    required this.controller,
    required this.focusNode,
    required this.hasText,
    required this.onSend,
    required this.sending,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasText;
  final VoidCallback onSend;
  final bool sending;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);

    final minHeight = responsive.s(54).clamp(50.0, 60.0).toDouble();
    final sendSize = responsive.s(40).clamp(38.0, 46.0).toDouble();
    // The button's breathing room, mirrored on the left so the row is centred
    // inside the pill rather than merely padded.
    final inset = (minHeight - sendSize) / 2;
    final canSend = hasText && !sending;

    return GlassSurface(
      // A stadium at rest that squares up gently as the field grows, so a
      // multi-line composer does not end up with absurd 27pt corners.
      borderRadius: BorderRadius.circular(responsive.radius(26)),
      // White glass, both themes, carried HEAVY.
      //
      // This pane sits over the AI page's dark teal bloom, and at the previous
      // 0.38 tint the composer was barely lighter than the canvas behind it —
      // the field read as a faint smudge and the placeholder was the lowest
      // contrast text in the app. At 0.74 the pane is unambiguously a white
      // surface, which is what lets the dark ink below actually work. It is
      // still glass: the blur and the saturation lift still carry the page's
      // colour through it, just under a much brighter pane.
      tintColor: MedGuardPalette.pureWhite,
      tint: 0.74,
      blur: 26,
      shadow: true,
      padding: EdgeInsets.fromLTRB(responsive.s(18), inset, inset, inset),
      child: Row(
        // The button pins to the bottom of a grown field, where the thumb
        // expects it, rather than floating in the vertical middle.
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: sendSize),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !sending,
                  minLines: 1,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  // The pane is WHITE in both themes, so its contents take the
                  // light-theme inks in both themes too. Using `colors.ink`
                  // here is what put near-white text on a white pane in dark
                  // mode — theme-resolved ink is correct on a theme-resolved
                  // surface, and wrong on a fixed one.
                  cursorColor: MedGuardPalette.teal,
                  style: GoogleFonts.inter(
                    color: MedGuardPalette.ink,
                    fontSize: responsive.font(15),
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Ask anything',
                    hintStyle: GoogleFonts.inter(
                      // A full step darker than the old muted grey: the
                      // placeholder is the label for the whole control, so it
                      // has to be readable, not merely present.
                      color: MedGuardPalette.inkSoft,
                      fontSize: responsive.font(15),
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(width: responsive.s(10)),
          Pressable(
            onTap: canSend ? onSend : null,
            pressScale: 0.9,
            semanticLabel: 'Send',
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              width: sendSize,
              height: sendSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Also on the white pane, so also fixed to the brand teal
                // rather than the theme accent.
                color: canSend
                    ? MedGuardPalette.teal
                    : MedGuardPalette.tealAlpha(0.12),
                boxShadow: canSend
                    ? [
                        BoxShadow(
                          color: MedGuardPalette.teal.withValues(alpha: 0.34),
                          blurRadius: responsive.s(12),
                          offset: Offset(0, responsive.s(4)),
                        ),
                      ]
                    : null,
              ),
              child: sending
                  ? MorphLoader(
                      size: sendSize * 0.52,
                      color: MedGuardPalette.teal,
                      glow: false,
                    )
                  : Icon(
                      Icons.arrow_upward_rounded,
                      color: canSend
                          ? MedGuardPalette.pureWhite
                          : MedGuardPalette.teal,
                      size: sendSize * 0.48,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The theme-aware background: the scaffold colour with a teal glow blooming
/// behind the orb and rising from the bottom — the colour shift is radial and
/// asymmetric, never a flat band.
class _AiBackground extends StatelessWidget {
  const _AiBackground({required this.base, required this.isDark});

  final Color base;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _AiBackgroundPainter(base: base, isDark: isDark),
        size: Size.infinite,
      ),
    );
  }
}

class _AiBackgroundPainter extends CustomPainter {
  const _AiBackgroundPainter({required this.base, required this.isDark});

  final Color base;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;

    canvas.drawRect(rect, Paint()..color = base);

    // A dark canvas can carry a much stronger glow than a near-white one before
    // it stops reading as "the app's colour" — scale the intensity to the theme.
    final glow = isDark ? 0.46 : 0.20;
    final bottom = isDark ? 0.72 : 0.34;

    final glowCentre = Offset(w * 0.5, h * 0.48);
    canvas.drawCircle(
      glowCentre,
      h * 0.46,
      Paint()
        ..shader = RadialGradient(
          colors: [
            MedGuardPalette.tealLight.withValues(alpha: glow),
            MedGuardPalette.teal.withValues(alpha: glow * 0.4),
            MedGuardPalette.teal.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: glowCentre, radius: h * 0.46)),
    );

    final bottomCentre = Offset(w * 0.5, h * 1.0);
    canvas.drawCircle(
      bottomCentre,
      w * 1.05,
      Paint()
        ..shader = RadialGradient(
          colors: [
            MedGuardPalette.tealLight.withValues(alpha: bottom),
            MedGuardPalette.teal.withValues(alpha: bottom * 0.55),
            MedGuardPalette.teal.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.4, 1.0],
        ).createShader(
          Rect.fromCircle(center: bottomCentre, radius: w * 1.05),
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _AiBackgroundPainter oldDelegate) =>
      oldDelegate.base != base || oldDelegate.isDark != isDark;
}

/// The side menu — the app's primary navigation while the bottom nav is hidden
/// on the AI screen.
///
/// Three labelled groups: THIS CHAT (start a new one), GO TO (every destination
/// in the app, Search included), and RECENTS (the conversations kept on this
/// device). Search is a named row in the navigation list rather than a bare
/// field or a lone glyph, because a magnifier on its own tells the user nothing
/// about *what* it searches — here it plainly reads "Search medicines" and sits
/// beside the pages it belongs with.
///
/// There is no account block at the foot: the profile is reachable from the
/// avatar in the top bar of every screen, including this one, so repeating it
/// here was a second route to the same place taking up the menu's whole base.
class _AiDrawer extends StatelessWidget {
  const _AiDrawer({
    required this.currentTab,
    required this.sessions,
    required this.activeSessionId,
    required this.onSelectTab,
    required this.onNewChat,
    required this.onOpenSession,
    required this.onDeleteSession,
    required this.onOpenSearch,
  });

  final AppNavTab? currentTab;
  final List<AiChatSession> sessions;
  final String activeSessionId;
  final ValueChanged<AppNavTab> onSelectTab;
  final VoidCallback onNewChat;
  final ValueChanged<AiChatSession> onOpenSession;
  final ValueChanged<AiChatSession> onDeleteSession;
  final VoidCallback onOpenSearch;

  // The app's pages, in nav order, EXCLUDING the AI tab (we're already on it).
  static const List<AppNavTab> _pages = [
    AppNavTab.home,
    AppNavTab.interactions,
    AppNavTab.insights,
    AppNavTab.dose,
  ];

  String _label(AppNavTab tab) => switch (tab) {
    AppNavTab.home => 'Home',
    AppNavTab.interactions => 'Interactions',
    AppNavTab.ai => 'MedGuard AI',
    AppNavTab.insights => 'Insights',
    AppNavTab.dose => 'Dose Schedule',
  };

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Drawer(
      backgroundColor: colors.surface,
      elevation: 0,
      width: MediaQuery.sizeOf(context).width * 0.82,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(26)),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            responsive.s(14),
            MedGuardSpacing.stickyTop(responsive),
            responsive.s(14),
            responsive.s(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── "This chat" and the close control share one row: the
              // section label on the left, the way out on the right, on the
              // same baseline.
              Padding(
                padding: EdgeInsets.only(right: responsive.s(2)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Expanded(child: _DrawerSectionLabel('This chat')),
                    Pressable(
                      onTap: () => Navigator.of(context).pop(),
                      pressScale: 0.9,
                      semanticLabel: 'Close menu',
                      child: Container(
                        width: responsive.s(34).clamp(32.0, 40.0).toDouble(),
                        height: responsive.s(34).clamp(32.0, 40.0).toDouble(),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.surfaceAlt,
                          border: Border.all(color: colors.border),
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          color: colors.inkSoft,
                          size: responsive.icon(17),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: responsive.s(10)),
              _DrawerRow(
                key: const ValueKey('ai-drawer-new-chat'),
                icon: Icons.add_rounded,
                label: 'New chat',
                emphasized: true,
                onTap: onNewChat,
              ),
              // One consistent beat between groups, matching the rhythm the
              // rest of the app uses between sections.
              SizedBox(height: responsive.s(26)),
              const _DrawerSectionLabel('Go to'),
              SizedBox(height: responsive.s(10)),
              for (final tab in _pages)
                _DrawerRow(
                  icon: tab == currentTab ? tab.filledIcon : tab.outlineIcon,
                  label: _label(tab),
                  active: tab == currentTab,
                  onTap: () => onSelectTab(tab),
                ),
              // Search belongs to navigation, so it sits with the pages and
              // says what it searches.
              _DrawerRow(
                icon: Icons.search_rounded,
                label: 'Search medicines',
                onTap: onOpenSearch,
              ),
              SizedBox(height: responsive.s(26)),
              Padding(
                padding: EdgeInsets.only(right: responsive.s(12)),
                child: Row(
                  children: [
                    const Expanded(child: _DrawerSectionLabel('Recents')),
                    if (sessions.isNotEmpty)
                      Text(
                        '${sessions.length}',
                        style: GoogleFonts.inter(
                          color: colors.inkMute,
                          fontSize: responsive.font(10.5),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: responsive.s(10)),
              // The list takes whatever height is left and scrolls inside it,
              // so a long history never pushes navigation off the menu.
              Expanded(
                child: sessions.isEmpty
                    // Scrollable rather than stretched: the placeholder is a
                    // fixed block of prose in a slot whose height depends on
                    // the device, the text scale and how many nav rows sit
                    // above it, so on a short screen it has to be able to
                    // scroll instead of overflowing its box.
                    ? const SingleChildScrollView(
                        physics: BouncingScrollPhysics(),
                        child: _RecentsEmpty(),
                      )
                    : ListView.separated(
                        key: const ValueKey('ai-drawer-recents'),
                        padding: EdgeInsets.only(bottom: responsive.s(8)),
                        physics: const BouncingScrollPhysics(),
                        itemCount: sessions.length,
                        separatorBuilder: (_, _) =>
                            SizedBox(height: responsive.s(3)),
                        itemBuilder: (context, index) {
                          final session = sessions[index];
                          return _RecentChatRow(
                            session: session,
                            active: session.id == activeSessionId,
                            onTap: () => onOpenSession(session),
                            onDelete: () => onDeleteSession(session),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Recents placeholder — honest about *why* it is empty (nothing asked
/// yet), rather than blaming an unfinished backend for a list the app is
/// perfectly capable of filling.
class _RecentsEmpty extends StatelessWidget {
  const _RecentsEmpty();

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(responsive.s(14)),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(responsive.radius(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history_rounded,
            color: colors.inkMute,
            size: responsive.icon(18),
          ),
          SizedBox(height: responsive.s(9)),
          Text(
            'No conversations yet. Ask MedGuard AI something and it will be '
            'saved here on this device.',
            style: GoogleFonts.inter(
              color: colors.inkMute,
              fontSize: responsive.font(12.6),
              height: 1.5,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

/// One saved conversation: its opening question, when it last moved, and a
/// delete control that asks first — history is cheap to keep and annoying to
/// lose by mis-tap.
class _RecentChatRow extends StatelessWidget {
  const _RecentChatRow({
    required this.session,
    required this.active,
    required this.onTap,
    required this.onDelete,
  });

  final AiChatSession session;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  String _relative(DateTime at) {
    final delta = DateTime.now().difference(at);
    if (delta.inMinutes < 1) return 'Just now';
    if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
    if (delta.inHours < 24) return '${delta.inHours}h ago';
    if (delta.inDays == 1) return 'Yesterday';
    if (delta.inDays < 7) return '${delta.inDays}d ago';
    return '${at.day}/${at.month}/${at.year % 100}';
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showConfirmSheet(
      context: context,
      title: 'Delete conversation?',
      message:
          'This removes "${session.title}" from this device. It cannot be '
          'undone.',
      confirmLabel: 'Delete',
      cancelLabel: 'Keep',
      destructive: true,
      icon: Icons.delete_outline_rounded,
    );
    if (confirmed == true) onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final radius = BorderRadius.circular(responsive.radius(13));
    final turns = session.messages.where((m) => m.isUser).length;

    return Pressable(
      onTap: onTap,
      pressScale: 0.985,
      semanticLabel: session.title,
      selected: active,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          responsive.s(12),
          responsive.s(10),
          responsive.s(6),
          responsive.s(10),
        ),
        decoration: BoxDecoration(
          color: active ? colors.accentAlpha(0.10) : Colors.transparent,
          borderRadius: radius,
        ),
        child: Row(
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: responsive.icon(16),
              color: active ? colors.accent : colors.inkMute,
            ),
            SizedBox(width: responsive.s(11)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    session.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: active ? colors.accent : colors.ink,
                      fontSize: responsive.font(13.5),
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      height: 1.25,
                    ),
                  ),
                  SizedBox(height: responsive.s(3)),
                  Text(
                    '${_relative(session.updatedAt)} · $turns '
                    '${turns == 1 ? 'question' : 'questions'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      color: colors.inkMute,
                      fontSize: responsive.font(11),
                      fontWeight: FontWeight.w500,
                      height: 1.0,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(width: responsive.s(4)),
            Pressable(
              onTap: () => unawaited(_confirmDelete(context)),
              pressScale: 0.88,
              semanticLabel: 'Delete conversation',
              child: Padding(
                padding: EdgeInsets.all(responsive.s(6)),
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: responsive.icon(16),
                  color: colors.inkMute,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerSectionLabel extends StatelessWidget {
  const _DrawerSectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return Padding(
      padding: EdgeInsets.only(left: responsive.s(12)),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.inter(
          color: context.colors.inkMute,
          fontSize: responsive.font(10.5),
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
        ),
      ),
    );
  }
}

/// One menu row. The active page carries a tinted fill AND a short accent bar
/// at its leading edge, so which page you are on is legible at a glance rather
/// than only from a colour shift.
class _DrawerRow extends StatelessWidget {
  const _DrawerRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final tinted = active || emphasized;
    final radius = BorderRadius.circular(responsive.radius(13));

    return Pressable(
      onTap: onTap,
      pressScale: 0.985,
      semanticLabel: label,
      selected: active,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: responsive.s(1.5)),
        decoration: BoxDecoration(
          color: tinted ? colors.accentAlpha(0.10) : Colors.transparent,
          borderRadius: radius,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: active ? 3 : 0, color: colors.accent),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: responsive.s(12),
                      vertical: responsive.s(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          icon,
                          color: tinted ? colors.accent : colors.inkSoft,
                          size: responsive.icon(20),
                        ),
                        SizedBox(width: responsive.s(11)),
                        Text(
                          label,
                          style: GoogleFonts.inter(
                            color: tinted ? colors.accent : colors.ink,
                            fontSize: responsive.font(14.5),
                            fontWeight: tinted
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
