import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/screens/ai/ai_conversation.dart';
import 'package:mobile/screens/ai/ai_screen.dart';
import 'package:mobile/services/ai_chat_store.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The AI tab's conversation plumbing: New chat, Recents, and the persistence
/// that connects them.
///
/// These three used to be decoration — "New chat" showed a "coming soon" toast
/// and Recents was a permanently empty placeholder — so the tests here are
/// mostly about the controls doing what their labels say.
void main() {
  const statusBar = EdgeInsets.only(top: 47);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpAi(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const MediaQuery(
          data: MediaQueryData(
            size: Size(390, 844),
            padding: statusBar,
            viewPadding: statusBar,
          ),
          child: AiScreen(showNavigation: false),
        ),
      ),
    );
    await tester.pump();
  }

  /// Types [text] into the composer and lets the canned reply land.
  Future<void> ask(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Send'));
    await tester.pump();
    // The stubbed assistant answers after 900ms.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
  }

  group('AiChatStore', () {
    test('only sessions with a real question are kept', () async {
      final store = AiChatStore.instance;
      await store.clear();

      final blank = AiChatSession.fresh();
      await store.save(blank);
      expect(store.sessions, isEmpty, reason: 'an empty thread is not a chat');

      final real = AiChatSession.fresh()
        ..messages.add(
          AiMessage(
            role: AiRole.user,
            text: 'Do my medicines clash?',
            at: DateTime(2026, 7, 29, 9),
          ),
        );
      await store.save(real);
      expect(store.sessions, hasLength(1));
      // The title is the question, not a generated name.
      expect(store.sessions.first.title, 'Do my medicines clash?');
      await store.clear();
    });

    test('re-saving moves a session to the top, never duplicates it', () async {
      final store = AiChatStore.instance;
      await store.clear();

      AiChatSession seeded(String question) => AiChatSession.fresh()
        ..messages.add(
          AiMessage(role: AiRole.user, text: question, at: DateTime.now()),
        );

      final first = seeded('First question');
      await store.save(first);
      await store.save(seeded('Second question'));
      expect(store.sessions.first.title, 'Second question');

      await store.save(first);
      expect(store.sessions, hasLength(2), reason: 'updated, not duplicated');
      expect(store.sessions.first.title, 'First question');
      await store.clear();
    });

    test('a pending turn is never written to history', () {
      final session = AiChatSession.fresh()
        ..messages.addAll([
          AiMessage(role: AiRole.user, text: 'Hi', at: DateTime(2026)),
          AiMessage(
            role: AiRole.assistant,
            text: '',
            at: DateTime(2026),
            pending: true,
          ),
        ]);
      final messages = session.toJson()['messages'] as List<dynamic>;
      expect(messages, hasLength(1));
    });
  });

  group('AI chat screen', () {
    testWidgets('asking a question builds a thread with both turns labelled', (
      tester,
    ) async {
      await AiChatStore.instance.clear();
      await pumpAi(tester);

      await ask(tester, 'Can I take these together?');

      // Both sides of the exchange are named, so the thread scans as a
      // conversation rather than as two stacks of text.
      expect(find.text('You'), findsOneWidget);
      expect(find.text('MedGuard AI'), findsOneWidget);
      // Twice on purpose: once in the user's bubble, once as the thread's name
      // in the top bar — which is what tells you WHICH conversation you are in
      // once Recents can drop you into another one.
      expect(find.text('Can I take these together?'), findsNWidgets(2));
      // The thread is stamped with its day.
      expect(find.text('Today'), findsOneWidget);
      await AiChatStore.instance.clear();
    });

    testWidgets('New chat clears the thread and files it under Recents', (
      tester,
    ) async {
      await AiChatStore.instance.clear();
      await pumpAi(tester);
      await ask(tester, 'Is this one safe with food?');
      expect(find.text('Is this one safe with food?'), findsWidgets);

      // The header's new-chat control only appears once there is a
      // conversation worth leaving.
      await tester.tap(find.byKey(const ValueKey('ai-new-chat')));
      await tester.pumpAndSettle();

      // Back to the opening state…
      expect(find.text('Is this one safe with food?'), findsNothing);
      // …and the conversation is in Recents, not lost.
      expect(AiChatStore.instance.sessions, hasLength(1));
      expect(
        AiChatStore.instance.sessions.first.title,
        'Is this one safe with food?',
      );
      await AiChatStore.instance.clear();
    });

    testWidgets('the drawer lists real recents and reopens one', (
      tester,
    ) async {
      await AiChatStore.instance.clear();
      await pumpAi(tester);
      const question = 'How long should I stay on this?';
      await ask(tester, question);
      await tester.tap(find.byKey(const ValueKey('ai-new-chat')));
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('Open menu'));
      await tester.pumpAndSettle();

      // The saved conversation is listed by its opening question.
      final recents = find.byKey(const ValueKey('ai-drawer-recents'));
      expect(recents, findsOneWidget);
      final row = find.descendant(of: recents, matching: find.text(question));
      expect(row, findsOneWidget);

      // Tapping it reopens that thread.
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.text('You'), findsOneWidget);
      expect(find.text(question), findsWidgets);
      await AiChatStore.instance.clear();
    });

    testWidgets('with no history, Recents explains itself honestly', (
      tester,
    ) async {
      await AiChatStore.instance.clear();
      await pumpAi(tester);

      await tester.tap(find.bySemanticsLabel('Open menu'));
      await tester.pumpAndSettle();

      // Not "coming soon" — the feature works, there is simply nothing in it.
      expect(find.textContaining('No conversations yet'), findsOneWidget);
      expect(find.textContaining('coming soon'), findsNothing);
    });
  });
}
