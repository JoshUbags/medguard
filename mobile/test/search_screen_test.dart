import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/drug.dart';
import 'package:mobile/screens/search/search_screen.dart';
import 'package:mobile/services/allergy_checker.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/theme/medguard_palette.dart';
import 'package:mobile/widgets/common/detail_page.dart';
import 'package:mobile/widgets/common/page_header.dart';
import 'package:mobile/widgets/common/section_header.dart';

void main() {
  const aspirin = Drug(
    id: 1,
    drugbankId: 'DB00945',
    name: 'Aspirin',
    description: 'A salicylate used for pain, fever, and antiplatelet therapy.',
    indication: 'Used for pain, inflammation, and cardiovascular protection.',
    atcCode: 'B01AC06',
    rxcui: '1191',
  );

  const acetylAspirin = Drug(
    id: 2,
    drugbankId: 'DB00945-A',
    name: 'Acetylsalicylic Acid Aspirin',
    description: 'A detailed analgesic and antiplatelet medication record.',
    indication: 'Used for pain and platelet aggregation risk review.',
    atcCode: 'B01AC06',
    rxcui: '1191',
  );

  const amoxicillin = Drug(
    id: 8,
    drugbankId: 'DB01060',
    name: 'Amoxicillin',
    description: 'A penicillin antibiotic used for susceptible infections.',
    indication: 'Used for selected bacterial infections.',
    atcCode: 'J01CA04',
  );

  Future<void> pumpSearchScreen(
    WidgetTester tester, {
    SearchDrugs? searchDrugs,
    AddDrug? addDrug,
    LoadAddedDrugIds? loadAddedDrugIds,
    CheckAllergies? checkAllergies,
    VoidCallback? onOpenMedications,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: SearchScreen(
          searchDrugs: searchDrugs ?? (_, {limit = 25}) async => const [],
          addDrug: addDrug ?? (_) async {},
          loadAddedDrugIds: loadAddedDrugIds ?? () async => const <int>{},
          // Stubbed by default. The real checker opens the bundled clinical
          // database; these tests used to reach it and only got away with it
          // because FirebaseAuth threw first and the throw was swallowed.
          checkAllergies: checkAllergies ?? (_) async => const <AllergyHit>[],
          onOpenMedications: onOpenMedications,
        ),
      ),
    );
  }

  testWidgets('wears the shared routed-screen chrome', (tester) async {
    await pumpSearchScreen(tester);

    // Search is reached by pushNamed from six places, so it gets the SAME back
    // control, title scale and action pill as Profile, Settings and Allergies.
    // Its hand-rolled header carried a 30pt title and no back control at all.
    expect(find.byType(DetailPage), findsOneWidget);
    expect(find.byKey(const ValueKey('detail-back')), findsOneWidget);

    // The title is the shared page-title style, identified by its tracking and
    // leading — the hand-rolled one was 30pt, untracked, at height 1.04. The
    // size itself is whatever the responsive scaler makes of kPageTitleSize at
    // the current viewport, so it is not asserted as a raw number.
    final title = tester.widget<Text>(find.text('Search'));
    expect(title.style?.fontWeight, kPageTitleWeight);
    expect(title.style?.letterSpacing, kPageTitleTracking);
    expect(title.style?.height, 1.1);

    // The old hand-rolled header's strings are gone with it.
    expect(find.text('Medication lookup'), findsNothing);
    expect(
      find.text('Find medicines before adding them to your list.'),
      findsNothing,
    );
    expect(find.text('Search database'), findsNothing);
    expect(find.text('Tap a card for details'), findsNothing);
  });

  testWidgets('shows the empty medication search prompt', (tester) async {
    await pumpSearchScreen(tester);

    // No hard-coded record count. "4,955 medications" matched the bundled
    // database when it was typed, but nothing tied the two together, so the
    // next pipeline rebuild that moves the row count would silently falsify it.
    expect(find.textContaining('4,955'), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Popular searches'), findsOneWidget);
    expect(find.text('Browse by category'), findsNothing);
    expect(find.text('How MedGuard checks safety'), findsNothing);

    // The block's own 21pt heading is gone: the page already has a title four
    // lines above it, and a second one read as two pages stacked.
    expect(find.text('Search the medicine database'), findsNothing);
    // "See all" is gone with it — it ran the first suggestion, which is what
    // tapping that suggestion already did.
    expect(find.text('See all'), findsNothing);

    // The heading is the shared SectionHeader, not a search-local lookalike.
    expect(
      find.descendant(
        of: find.byType(SectionHeader),
        matching: find.text('Popular searches'),
      ),
      findsOneWidget,
    );

    // The tips panel is accent-tinted. It used to be ruby — the colour this app
    // reserves for "this medicine may hurt you" — on its most benign block.
    expect(find.byKey(const ValueKey('search-guidance-panel')), findsOneWidget);
    final tipPanel = tester.widget<Container>(
      find.byKey(const ValueKey('search-guidance-panel')),
    );
    final tipDecoration = tipPanel.decoration! as BoxDecoration;
    expect(
      tipDecoration.color,
      isNot(MedGuardPalette.ruby.withValues(alpha: 0.06)),
    );
    final tipIcon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('search-guidance-panel')),
        matching: find.byIcon(Icons.lightbulb_rounded),
      ),
    );
    expect(tipIcon.color, isNot(MedGuardPalette.ruby));
    expect(find.text('Search tips'), findsOneWidget);
    expect(find.text('Use generic names first.'), findsOneWidget);
    expect(
      tester
              .getTopLeft(find.byKey(const ValueKey('search-guidance-panel')))
              .dy >
          tester.getTopLeft(find.text('Amoxicillin')).dy,
      isTrue,
    );
  });

  testWidgets('the scope pills are the only filter control', (tester) async {
    await pumpSearchScreen(tester);

    // The filter sheet is gone. Its two axes — "Match source" and "Clinical
    // detail level" — re-offered scopes the pill row already carried, through
    // separate state, from behind a modal.
    expect(find.byTooltip('Open filters'), findsNothing);
    expect(find.byIcon(Icons.tune_rounded), findsNothing);

    // Everything it offered survives as a pill, including the finer two.
    for (final label in const [
      'All',
      'Saved',
      'Classified',
      'Has description',
      'Has use notes',
      'Food notes',
    ]) {
      expect(find.text(label), findsOneWidget, reason: 'missing scope: $label');
    }
  });

  testWidgets('opens the medications list from the search header', (
    tester,
  ) async {
    var opened = false;

    await pumpSearchScreen(tester, onOpenMedications: () => opened = true);

    await tester.tap(find.byKey(const ValueKey('search-header-action')));
    await tester.pump();

    expect(opened, isTrue);
  });

  testWidgets('debounces search input and renders result cards', (
    tester,
  ) async {
    final queries = <String>[];

    await pumpSearchScreen(
      tester,
      searchDrugs: (query, {limit = 25}) async {
        queries.add(query);
        return const [aspirin];
      },
    );

    await tester.enterText(find.byType(TextField), 'asp');
    await tester.pump(const Duration(milliseconds: 299));
    expect(queries, isEmpty);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(queries, ['asp']);
    // The list is a standard section: heading, one line of state, sort in the
    // trailing slot. The tinted "N shown / N saved / N classified" panel that
    // used to sit under it restated the count and offered two tallies the scope
    // pills already provide as filters.
    expect(find.byKey(const ValueKey('search-summary-panel')), findsNothing);
    expect(find.text('1 shown'), findsNothing);
    expect(find.text('1 classified'), findsNothing);
    expect(find.text('Results'), findsOneWidget);
    expect(find.text('1 medicine matches "asp".'), findsOneWidget);
    expect(find.byKey(const ValueKey('drug-card-surface-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('drug-title-1')), findsOneWidget);
    // Raw identifiers stay out of the list; they belong in the detail sheet.
    expect(find.textContaining('B01AC06'), findsNothing);
    expect(find.text('RxCUI: 1191'), findsNothing);
    expect(find.text('DrugBank: DB00945'), findsNothing);
    // Both actions are NAMED. The card used to carry two bare glyphs, and you
    // could not tell which one added the medicine without pressing one.
    expect(find.text('Details'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
    expect(find.text('Blood medicine'), findsOneWidget);
    // The decorative per-row "Safety focus" tag is gone — it said the same
    // thing on every result, so it said nothing.
    expect(find.text('Safety focus'), findsNothing);
  });

  testWidgets('nothing on a result card is cut off with an ellipsis', (
    tester,
  ) async {
    await pumpSearchScreen(
      tester,
      searchDrugs: (_, {limit = 25}) async => const [aspirin],
    );

    await tester.enterText(find.byType(TextField), 'asp');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    // The card's own text — the class line, the purpose sentence, the two
    // action labels — must all be complete. A medicine name or a clinical
    // purpose that stops mid-word is worse than not showing it at all, because
    // the reader cannot tell what was removed.
    final card = find.byKey(const ValueKey('drug-card-surface-1'));
    final texts = tester.widgetList<Text>(
      find.descendant(of: card, matching: find.byType(Text)),
    );
    expect(texts, isNotEmpty);
    for (final text in texts) {
      expect(
        text.overflow,
        isNot(TextOverflow.ellipsis),
        reason: 'Ellipsised on the card: "${text.data}"',
      );
    }
    expect(find.text('Blood medicine'), findsOneWidget);
    expect(find.text('Tap for details'), findsNothing);
  });

  testWidgets('plain language result filters narrow the list', (tester) async {
    const localReference = Drug(
      id: 3,
      drugbankId: 'DBLOCAL',
      name: 'Aspirin local reference',
      atcCode: 'B01AC06',
    );

    await pumpSearchScreen(
      tester,
      searchDrugs: (_, {limit = 25}) async => const [aspirin, localReference],
    );

    await tester.enterText(find.byType(TextField), 'asp');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.byKey(const ValueKey('drug-title-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('drug-title-3')), findsOneWidget);

    // The quick filter, not either result card's Details button.
    await tester.ensureVisible(find.text('Has description'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Has description'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('drug-title-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('drug-title-3')), findsNothing);
  });

  testWidgets('highlights matching title fragments with red blocks', (
    tester,
  ) async {
    await pumpSearchScreen(
      tester,
      searchDrugs: (_, {limit = 25}) async => const [acetylAspirin],
    );

    await tester.enterText(find.byType(TextField), 'asp');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.byKey(const ValueKey('drug-title-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('query-highlight-2-0')), findsOneWidget);
  });

  testWidgets('result cards use drug-specific medicine visuals', (
    tester,
  ) async {
    await pumpSearchScreen(
      tester,
      searchDrugs: (_, {limit = 25}) async => const [aspirin, amoxicillin],
    );

    await tester.enterText(find.byType(TextField), 'a');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    final aspirinVisual = find.byKey(const ValueKey('drug-visual-1'));
    final amoxicillinVisual = find.byKey(const ValueKey('drug-visual-8'));

    expect(aspirinVisual, findsOneWidget);
    expect(amoxicillinVisual, findsOneWidget);
    expect(tester.getSize(aspirinVisual), const Size(50, 50));
    expect(
      find.descendant(of: aspirinVisual, matching: find.byType(CustomPaint)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: amoxicillinVisual,
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );

    final aspirinIcon = tester
        .widget<Icon>(
          find.descendant(of: aspirinVisual, matching: find.byType(Icon)),
        )
        .icon;
    final amoxicillinIcon = tester
        .widget<Icon>(
          find.descendant(of: amoxicillinVisual, matching: find.byType(Icon)),
        )
        .icon;
    expect(aspirinIcon, isNot(amoxicillinIcon));
  });

  testWidgets('sorting is picked through the app\'s shared option sheet', (
    tester,
  ) async {
    const plain = Drug(id: 5, drugbankId: 'DBP', name: 'Aspirin plain');

    await pumpSearchScreen(
      tester,
      searchDrugs: (_, {limit = 25}) async => const [plain, aspirin],
    );

    await tester.enterText(find.byType(TextField), 'asp');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    // Relevance is the database's own order, so the sparse record stays first.
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('drug-title-5'))).dy <
          tester.getTopLeft(find.byKey(const ValueKey('drug-title-1'))).dy,
      isTrue,
    );

    // The sort control is the section's trailing action, and it opens a bottom
    // sheet — not the Material popup menu that used to be the only one in the
    // app.
    await tester.tap(find.text('Relevance'));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuButton<Object>), findsNothing);
    expect(find.text('Sort results'), findsOneWidget);
    expect(find.text('Most complete'), findsOneWidget);

    await tester.tap(find.text('Most complete'));
    await tester.pumpAndSettle();

    // The fuller record now leads.
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('drug-title-1'))).dy <
          tester.getTopLeft(find.byKey(const ValueKey('drug-title-5'))).dy,
      isTrue,
    );
  });

  testWidgets('every scope pill actually narrows the list', (tester) async {
    const noNotes = Drug(
      id: 3,
      drugbankId: 'DBLOCAL',
      name: 'Aspirin local reference',
      atcCode: 'B01AC06',
    );
    const noCode = Drug(
      id: 4,
      drugbankId: 'DBPLAIN',
      name: 'Aspirin plain record',
      description: 'Take with food to reduce stomach upset.',
    );

    await pumpSearchScreen(
      tester,
      searchDrugs: (_, {limit = 25}) async => const [aspirin, noNotes, noCode],
    );

    await tester.enterText(find.byType(TextField), 'asp');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    Future<void> pickScope(String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    // Classified: drops the record with no class code.
    await pickScope('Classified');
    expect(find.byKey(const ValueKey('drug-title-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('drug-title-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('drug-title-4')), findsNothing);

    // Food notes — inherited from the filter sheet's dead "Food guidance"
    // option — keeps only records whose own text mentions food.
    await pickScope('Food notes');
    expect(find.byKey(const ValueKey('drug-title-4')), findsOneWidget);
    expect(find.byKey(const ValueKey('drug-title-1')), findsNothing);
    expect(find.byKey(const ValueKey('drug-title-3')), findsNothing);

    // Saved only: nothing is saved in this fixture, so nothing survives.
    await pickScope('Saved');
    expect(find.byKey(const ValueKey('drug-title-1')), findsNothing);
    expect(find.byKey(const ValueKey('drug-title-3')), findsNothing);
    expect(find.byKey(const ValueKey('drug-title-4')), findsNothing);
  });

  testWidgets('the finer detail scopes survive the filter sheet\'s removal', (
    tester,
  ) async {
    // Description only, no use notes.
    const describedOnly = Drug(
      id: 3,
      drugbankId: 'DBLOCAL',
      name: 'Aspirin local reference',
      description: 'Local reference record without identifier coding.',
    );

    await pumpSearchScreen(
      tester,
      searchDrugs: (_, {limit = 25}) async => const [aspirin, describedOnly],
    );

    await tester.enterText(find.byType(TextField), 'asp');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.byKey(const ValueKey('drug-title-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('drug-title-3')), findsOneWidget);

    Future<void> pickScope(String label) async {
      await tester.ensureVisible(find.text(label));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    // "Has description" keeps both — the sheet's old quality level 1.
    await pickScope('Has description');
    expect(find.byKey(const ValueKey('drug-title-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('drug-title-3')), findsOneWidget);

    // "Has use notes" — the sheet's quality level 2 — drops the sparser one.
    await pickScope('Has use notes');
    expect(find.byKey(const ValueKey('drug-title-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('drug-title-3')), findsNothing);
  });

  testWidgets(
    'drug detail sheet separates identifiers from plain-language info',
    (tester) async {
      await pumpSearchScreen(
        tester,
        searchDrugs: (_, {limit = 25}) async => const [aspirin],
      );

      await tester.enterText(find.byType(TextField), 'asp');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      await tester.tap(find.byKey(const ValueKey('drug-title-1')));
      await tester.pumpAndSettle();

      // The name stands alone as the sheet's title.
      expect(find.text('Aspirin'), findsWidgets);
      expect(find.text('About Aspirin'), findsNothing);
      // Sections are named as the questions a person actually asks.
      expect(find.text('At a glance'), findsOneWidget);
      expect(find.text('What it is'), findsOneWidget);
      expect(find.text('What it is used for'), findsOneWidget);
      expect(find.text('How it is taken'), findsOneWidget);
      expect(find.text('What to watch for'), findsOneWidget);
      expect(find.text('Classification'), findsNothing);
      expect(find.text('CLASSIFICATION CODE'), findsOneWidget);
      expect(find.text('B01AC06'), findsWidgets);
      expect(find.text('Identifiers'), findsNothing);
      expect(find.text('What this means'), findsNothing);
      expect(find.textContaining('RxCUI'), findsNothing);
      expect(find.textContaining('DrugBank'), findsNothing);
    },
  );

  testWidgets('drug detail sheet sanitizes reference codes and adds context', (
    tester,
  ) async {
    const codedDrug = Drug(
      id: 24,
      drugbankId: 'DBREF',
      name: 'Reference Cleanser',
      description:
          'Reference Cleanser treats recurring symptoms [A39]. It supports daily symptom control [L33].',
      indication:
          'Used when directed for short-term relief [T116] and follow-up monitoring [L789].',
      atcCode: 'N02BE01',
      rxcui: '12345',
    );

    await pumpSearchScreen(
      tester,
      searchDrugs: (_, {limit = 25}) async => const [codedDrug],
    );

    await tester.enterText(find.byType(TextField), 'ref');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    await tester.tap(find.byKey(const ValueKey('drug-title-24')));
    await tester.pumpAndSettle();

    expect(find.textContaining('[A39]'), findsNothing);
    expect(find.textContaining('[L33]'), findsNothing);
    expect(find.textContaining('[T116]'), findsNothing);
    expect(find.textContaining('[L789]'), findsNothing);
    expect(
      find.textContaining('Reference Cleanser treats recurring symptoms.'),
      findsAtLeastNWidgets(1),
    );
    expect(find.text('What it is used for'), findsOneWidget);
    expect(find.text('What to watch for'), findsOneWidget);
    expect(find.text('At a glance'), findsOneWidget);
  });

  testWidgets('ignores stale search responses', (tester) async {
    final aspirinCompleter = Completer<List<Drug>>();
    final amoxicillinCompleter = Completer<List<Drug>>();

    await pumpSearchScreen(
      tester,
      searchDrugs: (query, {limit = 25}) {
        if (query == 'asp') return aspirinCompleter.future;
        return amoxicillinCompleter.future;
      },
    );

    await tester.enterText(find.byType(TextField), 'asp');
    await tester.pump(const Duration(milliseconds: 300));

    await tester.enterText(find.byType(TextField), 'amox');
    await tester.pump(const Duration(milliseconds: 300));

    amoxicillinCompleter.complete(const [
      Drug(
        id: 2,
        drugbankId: 'DB01060',
        name: 'Amoxicillin',
        atcCode: 'J01CA04',
      ),
    ]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    aspirinCompleter.complete(const [aspirin]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(find.byKey(const ValueKey('drug-title-2')), findsOneWidget);
    expect(find.text('Aspirin'), findsNothing);
  });

  testWidgets('adds a medication and marks it as added', (tester) async {
    final added = <Drug>[];

    await pumpSearchScreen(
      tester,
      searchDrugs: (_, {limit = 25}) async => const [aspirin],
      addDrug: (drug) async => added.add(drug),
    );

    await tester.enterText(find.byType(TextField), 'asp');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    // The intent rail sits between the field and the results, so the card's
    // action can land below the default 600px test fold.
    // The intent rail sits between the field and the results, so the card's
    // action can land below the default 600px test fold.
    await tester.ensureVisible(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    // Adding now asks what the medicine MEANS — something you take, or
    // something you react to — rather than assuming from a mode set elsewhere
    // on the screen.
    expect(find.text('I take this'), findsOneWidget);
    expect(find.text('I react to this'), findsOneWidget);
    await tester.tap(find.text('I take this'));
    await tester.pumpAndSettle();

    expect(added, [aspirin]);
    // The button becomes a non-interactive "Added" state rather than vanishing,
    // so the row still says what happened to it.
    expect(find.text('Added'), findsOneWidget);
    expect(find.text('Added Aspirin'), findsOneWidget);
  });

  testWidgets('an allergy conflict interrupts the add and can be declined', (
    tester,
  ) async {
    final added = <Drug>[];

    await pumpSearchScreen(
      tester,
      searchDrugs: (_, {limit = 25}) async => const [amoxicillin],
      addDrug: (drug) async => added.add(drug),
      checkAllergies: (drug) async => [
        AllergyHit(
          drugId: drug.id,
          drugName: drug.name,
          kind: AllergyHitKind.crossReactivity,
          allergyLabel: 'Penicillin',
          matchedCategory: 'beta-lactam',
        ),
      ],
    );

    await tester.enterText(find.byType(TextField), 'amox');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    await tester.ensureVisible(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I take this'));
    await tester.pumpAndSettle();

    // The conflict names the specific clash rather than warning in general.
    expect(find.text('Allergy conflict'), findsOneWidget);
    expect(find.textContaining('Penicillin'), findsWidgets);
    expect(find.text('Add anyway'), findsOneWidget);

    // Declining leaves the regimen untouched.
    await tester.tap(find.text('Don\'t add'));
    await tester.pumpAndSettle();
    expect(added, isEmpty);
  });

  testWidgets('shows no-results and search error states', (tester) async {
    await pumpSearchScreen(
      tester,
      searchDrugs: (_, {limit = 25}) async => const [],
    );

    await tester.enterText(find.byType(TextField), 'zzzz');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('No medicines found'), findsOneWidget);
    expect(find.textContaining('Try a brand name'), findsOneWidget);

    await pumpSearchScreen(
      tester,
      searchDrugs: (_, {limit = 25}) async => throw Exception('db missing'),
    );

    await tester.enterText(find.byType(TextField), 'asp');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(find.text('Search needs a retry'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    // "Report issue" is gone: it was wired to an empty callback, so the only
    // other control on the failure path did nothing when pressed.
    expect(find.text('Report issue'), findsNothing);
  });

  testWidgets('search layout avoids overflow on compact phones', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpSearchScreen(
      tester,
      searchDrugs: (_, {limit = 25}) async => const [
        Drug(
          id: 9,
          drugbankId: 'DBLONG',
          name: 'Very Long Medication Name With Aspirin Identifier',
          description: 'Long description for compact screen checks.',
          atcCode: 'A01BC99',
          rxcui: '123456',
        ),
      ],
    );

    await tester.enterText(find.byType(TextField), 'asp');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 260));

    expect(tester.takeException(), isNull);

    // The scope row scrolls rather than overflowing at 320dp.
    await tester.drag(
      find.byKey(const ValueKey('search-scope-row')),
      const Offset(-160, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
