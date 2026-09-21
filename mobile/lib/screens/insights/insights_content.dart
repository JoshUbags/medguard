import 'package:flutter/material.dart';

/// The editorial content behind the Insights feed.
///
/// Everything here is drawn from published guidance from the FDA, the WHO, the
/// NHS and peer-reviewed literature, and each piece carries the source it came
/// from so a reader can check it. Health copy that cannot be traced back to
/// something is worse than no copy at all, so nothing in this file is invented
/// and nothing states a figure the linked source does not.
///
/// The feed is deliberately short and fixed. It is a curated primer on
/// medication safety, not a live news wire — seven pieces the user can actually
/// finish, refreshed by editing this file, with no network dependency.
@immutable
class InsightArticle {
  const InsightArticle({
    required this.id,
    required this.category,
    required this.title,
    required this.dek,
    required this.readMinutes,
    required this.image,
    required this.accent,
    required this.body,
    required this.sourceName,
    required this.sourceUrl,
  });

  final String id;
  final String category;
  final String title;

  /// The standfirst — one sentence that says why the piece matters.
  final String dek;

  final int readMinutes;

  /// A bundled asset. The feed never fetches images, so it renders instantly
  /// and works offline.
  final String image;

  /// The category's colour, used for its chip and the card's accents.
  final Color accent;

  /// The article body, one entry per paragraph.
  final List<String> body;

  final String sourceName;
  final String sourceUrl;
}

const Color _food = Color(0xFFD98324);
const Color _adherence = Color(0xFF0E9F8C);
const Color _antibiotics = Color(0xFF3E8EF0);
const Color _everyday = Color(0xFF7A6FF0);
const Color _interactions = Color(0xFFCE6BA8);
const Color _storage = Color(0xFF3FAE6A);

const List<InsightArticle> kInsightArticles = [
  InsightArticle(
    id: 'grapefruit',
    category: 'Food & medicine',
    title: 'Grapefruit is not a neutral breakfast',
    dek:
        'It blocks the enzyme several common medicines rely on to break down — '
        'and the FDA now requires warnings on the labels because of it.',
    readMinutes: 3,
    image: 'assets/images/onboarding/01.jpg',
    accent: _food,
    body: [
      'Grapefruit juice interferes with enzymes in the gut that many medicines '
          'depend on to be broken down. Block those enzymes and more of the '
          'drug reaches the bloodstream than the dose intended — which is the '
          'same thing as accidentally taking too much.',
      'The clearest example is cholesterol medicine. The FDA singles out '
          'simvastatin and atorvastatin: grapefruit juice blocks the enzymes '
          'that clear them, raising the amount in the body and with it the risk '
          'of side effects.',
      'Statins are not alone. The FDA also lists medicines for high blood '
          'pressure, drugs that prevent organ-transplant rejection, some '
          'anti-anxiety medicines, and corticosteroids used for Crohn’s '
          'disease and ulcerative colitis.',
      'The practical rule is simple, and it is the one the FDA gives: ask a '
          'doctor or pharmacist whether grapefruit affects what you take. '
          'Switching the juice for something else is usually the entire fix.',
    ],
    sourceName: 'U.S. Food & Drug Administration',
    sourceUrl:
        'https://www.fda.gov/consumers/consumer-updates/grapefruit-juice-and-some-drugs-dont-mix',
  ),
  InsightArticle(
    id: 'adherence',
    category: 'Adherence',
    title: 'Half of us do not take our medicine properly',
    dek:
        'The WHO puts adherence to long-term treatment at around 50% in '
        'developed countries. It is not a fringe problem.',
    readMinutes: 3,
    image: 'assets/images/onboarding/03.jpg',
    accent: _adherence,
    body: [
      'The World Health Organization reports that among patients with chronic '
          'illness, adherence to treatment averages only about 50% in developed '
          'countries — and it is assumed to be lower where access to health '
          'care and medicines is more limited.',
      'That number is easy to misread as carelessness. It rarely is. Missed '
          'doses cluster around complicated schedules, side effects nobody '
          'warned the patient about, medicines that cost too much, and regimens '
          'that changed without anyone explaining why.',
      'The fix that works best is also the least dramatic: fewer moving parts. '
          'Doses grouped into as few times of day as the prescription allows, a '
          'reminder that actually fires, and a way to see at a glance what has '
          'already been taken.',
    ],
    sourceName: 'World Health Organization',
    sourceUrl:
        'https://www.who.int/news/item/01-07-2003-failure-to-take-prescribed-medicine-for-chronic-diseases-is-a-massive-world-wide-problem',
  ),
  InsightArticle(
    id: 'antibiotics',
    category: 'Antibiotics',
    title: 'Stopping when you feel better is the problem',
    dek:
        'Between 30% and 50% of antibiotic courses are never finished — and '
        'unfinished courses are one of the routes to resistant bacteria.',
    readMinutes: 3,
    image: 'assets/images/onboarding/05.jpg',
    accent: _antibiotics,
    body: [
      'Feeling better is not the same as being clear of an infection. '
          'Estimates put the share of antibiotic treatments that are never '
          'completed at between 30% and 50%, which both compromises the '
          'treatment and helps resistant strains emerge and spread.',
      'The WHO treats patient education as a central part of improving '
          'adherence to antibiotics, precisely because poor adherence is one of '
          'the factors driving resistance.',
      'Two habits carry most of the benefit. Take the course exactly as it was '
          'prescribed, to the end. And if side effects are making that hard, '
          'say so rather than quietly stopping — a different antibiotic is '
          'almost always available.',
    ],
    sourceName: 'WHO / peer-reviewed literature',
    sourceUrl: 'https://pmc.ncbi.nlm.nih.gov/articles/PMC12801711/',
  ),
  InsightArticle(
    id: 'paracetamol',
    category: 'Everyday medicine',
    title: 'Paracetamol has a lower ceiling than most people think',
    dek:
        'The familiar 4,000 mg limit is a maximum, not a target — and in 2012 '
        'the FDA suggested adults stay under 3 grams a day.',
    readMinutes: 4,
    image: 'assets/images/onboarding/08.jpg',
    accent: _everyday,
    body: [
      'Paracetamol — acetaminophen — is the most casually taken medicine there '
          'is, and the one with the least forgiving margin. Even the '
          'traditional maximum adult dose of 4,000 mg a day can result in '
          'severe liver damage, and in 2012 the FDA suggested a lower maximum '
          'of 3 grams, not exceeding 650 mg every six hours.',
      'The danger is rarely a deliberate overdose. It is arithmetic. '
          'Paracetamol is hidden inside combination cold and flu remedies, '
          'sleep aids and prescription painkillers, so someone treating a bad '
          'cold can pass the limit without ever taking more than a label said.',
      'Risk rises further with alcohol. Product warnings single out having '
          'three or more alcoholic drinks a day while taking it, along with '
          'exceeding the daily dose and taking more than one product containing '
          'paracetamol at the same time.',
      'Before adding an over-the-counter remedy to a prescription, read both '
          'labels for the same ingredient under a different name. That single '
          'check prevents most accidental overdoses.',
    ],
    sourceName: 'U.S. Food & Drug Administration',
    sourceUrl:
        'https://www.fda.gov/files/drugs/published/Organ-Specific-Warnings--Internal-Analgesic--Antipyretic--and-Antirheumatic-Drug-Products-for-Over-the-Counter-Human-Use-%E2%80%94.pdf',
  ),
  InsightArticle(
    id: 'nsaid-anticoagulant',
    category: 'Interactions',
    title: 'Painkillers and blood thinners are a genuinely risky pair',
    dek:
        'Taken with warfarin, an ordinary anti-inflammatory roughly doubles the '
        'odds of a serious gastrointestinal bleed.',
    readMinutes: 4,
    image: 'assets/images/onboarding/04.jpg',
    accent: _interactions,
    body: [
      'Anti-inflammatory painkillers — ibuprofen, naproxen, diclofenac — and '
          'anticoagulants such as warfarin act on bleeding through different '
          'mechanisms, and together the effect is worse than either alone. A '
          'meta-analysis put the odds ratio for gastrointestinal bleeding on '
          'both at 1.98 against warfarin alone.',
      'Not all of them carry the same weight. Among the anti-inflammatories '
          'studied, ibuprofen had the lowest adjusted hazard ratio at 1.79, '
          'against 3.30 for diclofenac and 4.10 for naproxen.',
      'Ibuprofen product labelling itself warns that bleeding has been reported '
          'when it is given to patients on coumarin-type anticoagulants, and '
          'tells prescribers to be cautious.',
      'None of this means pain has to go untreated. It means the choice of '
          'painkiller, the dose and the duration are a clinical decision rather '
          'than a supermarket one — and paracetamol is often the safer first '
          'option for someone on an anticoagulant.',
    ],
    sourceName: 'Systematic review, PubMed 32455439',
    sourceUrl: 'https://pubmed.ncbi.nlm.nih.gov/32455439/',
  ),
  InsightArticle(
    id: 'duplication',
    category: 'Interactions',
    title: 'Two boxes, one drug: the duplication trap',
    dek:
        'Therapeutic duplication is taking two medicines that do the same job '
        'without realising it. Combination remedies are where it usually hides.',
    readMinutes: 3,
    image: 'assets/images/onboarding/06.jpg',
    accent: _interactions,
    body: [
      'Duplication happens when two products contain the same active '
          'ingredient, or two different ingredients from the same class. The '
          'body receives a double dose while the person is convinced they took '
          'exactly what was on each label.',
      'Multi-symptom cold and flu remedies are the most common route in, '
          'because they bundle a painkiller, a decongestant and an '
          'antihistamine into one sachet. Add a separate painkiller and the '
          'total quietly doubles.',
      'The habit worth building is reading the active ingredients rather than '
          'the brand on the front. Two boxes that look nothing alike can be the '
          'same medicine wearing different names.',
      'Keeping every medicine — prescription and over-the-counter — in a single '
          'list is what makes duplication visible, because the check is a '
          'comparison and it cannot run on a list with gaps in it.',
    ],
    sourceName: 'NHS medicines guidance',
    sourceUrl: 'https://www.nhs.uk/medicines/',
  ),
  InsightArticle(
    id: 'storage',
    category: 'Storage',
    title: 'The bathroom cabinet is the wrong place',
    dek:
        'Heat and humidity degrade medicines, and the bathroom supplies both '
        'several times a day.',
    readMinutes: 2,
    image: 'assets/images/mainshell/02.jpg',
    accent: _storage,
    body: [
      'Most medicines are meant to be kept somewhere cool, dry and out of '
          'direct light. A bathroom is the one room in the house that is '
          'reliably warm and damp, which is an unfortunate thing to have named '
          'the medicine cabinet after.',
      'Degraded medicine does not usually look degraded. Tablets can lose '
          'potency without changing colour, so the failure shows up as a '
          'treatment that stopped working rather than as something visibly '
          'wrong in the packet.',
      'A bedroom drawer or a high kitchen cupboard away from the hob is a '
          'better default — dry, dark, stable in temperature, and still out of '
          'reach of children. Anything the label says to refrigerate should go '
          'in the fridge, not the freezer.',
      'It is worth checking expiry dates on the same day each year. Pick one '
          'you will remember.',
    ],
    sourceName: 'NHS medicines guidance',
    sourceUrl: 'https://www.nhs.uk/medicines/',
  ),

  InsightArticle(
    id: 'antibiotics-course',
    category: 'Antibiotics',
    title: 'Feeling better is not the same as being finished',
    dek:
        'Stopping an antibiotic early leaves behind the bacteria that were '
        'hardest to kill — the ones worth killing most.',
    readMinutes: 3,
    image: 'assets/images/onboarding/04.jpg',
    accent: _interactions,
    body: [
      'Symptoms usually ease well before an infection is cleared. The bacteria '
          'that die first are the ones least able to withstand the drug, so '
          'feeling better is a signal that the weakest have gone — not that '
          'the population has.',
      'What survives a partial course is, by definition, the fraction that '
          'coped best. Give those the run of the site and the next infection '
          'starts from a hardier population, which is the mechanism behind '
          'antimicrobial resistance at the level of a single person.',
      'The WHO is direct about this: take antibiotics exactly as prescribed, '
          'never share them, and never save leftovers for next time. A '
          'left-over half-course is the worst of both worlds — too little '
          'to treat, enough to select for resistance.',
      'If side effects are what is driving the urge to stop, that is a '
          'conversation with a pharmacist rather than a reason to abandon the '
          'course. Changing the drug is usually possible; stopping halfway '
          'rarely is.',
    ],
    sourceName: 'World Health Organization',
    sourceUrl:
        'https://www.who.int/news-room/fact-sheets/detail/antimicrobial-resistance',
  ),
  InsightArticle(
    id: 'double-dosing',
    category: 'Everyday risks',
    title: 'The same drug under two different names',
    dek:
        'Paracetamol hides inside dozens of cold and flu remedies, which is '
        'how an accidental overdose happens to careful people.',
    readMinutes: 3,
    image: 'assets/images/onboarding/05.jpg',
    accent: _everyday,
    body: [
      'Paracetamol is an ingredient, not only a product. It sits inside cold '
          'and flu sachets, night-time cough syrups, and combination '
          'painkillers sold under names that do not mention it on the front '
          'of the box.',
      'The danger is arithmetic rather than carelessness. Someone taking a '
          'paracetamol tablet for a headache and a flu sachet for a cold has '
          'taken two doses, from two products, that they thought of as two '
          'different medicines.',
      'The liver injury this causes is dose-dependent and can begin below the '
          'level most people assume is safe, especially alongside regular '
          'alcohol or a low body weight.',
      'The habit that prevents it is reading the active-ingredient line rather '
          'than the brand, on every box, every time. If two products list the '
          'same ingredient, they are the same medicine for the purpose of the '
          'daily maximum.',
    ],
    sourceName: 'NHS medicines guidance',
    sourceUrl: 'https://www.nhs.uk/medicines/paracetamol-for-adults/',
  ),
  InsightArticle(
    id: 'timing',
    category: 'Adherence',
    title: 'When you take it can matter as much as whether',
    dek:
        'Some medicines need an empty stomach, some need food, and a few need '
        'to be kept hours apart from each other.',
    readMinutes: 2,
    image: 'assets/images/onboarding/06.jpg',
    accent: _food,
    body: [
      'Absorption is not a constant. Food changes how fast a drug leaves the '
          'stomach, how much dissolves, and in some cases whether it is '
          'absorbed at all — which is why the label distinguishes "with '
          'food" from "on an empty stomach" rather than leaving it to '
          'preference.',
      'Some pairs interfere directly. Calcium — in a supplement, in milk, '
          'in an indigestion remedy — binds certain antibiotics in the gut '
          'and carries them straight through, so the dose is taken and never '
          'arrives. Spacing them by a couple of hours is usually enough.',
      'Thyroid medicine is the clearest case of timing as a clinical '
          'instruction: it is normally taken on an empty stomach, well before '
          'breakfast, because food measurably reduces how much is absorbed.',
      'None of this requires memorising pharmacology. It requires reading the '
          'timing line on the label once, and building the schedule around it '
          'rather than around the day.',
    ],
    sourceName: 'NHS medicines guidance',
    sourceUrl: 'https://www.nhs.uk/medicines/',
  ),
  InsightArticle(
    id: 'sharing',
    category: 'Everyday risks',
    title: 'A prescription is written for one person',
    dek:
        'Dose is calculated from weight, kidney function, and everything else '
        'that person already takes. None of that transfers.',
    readMinutes: 2,
    image: 'assets/images/onboarding/08.jpg',
    accent: _interactions,
    body: [
      'A prescription encodes more than a diagnosis. The dose reflects body '
          'weight, kidney and liver function, age, pregnancy status, and the '
          'other medicines already in the picture — a calculation '
          'performed for one person on one day.',
      'Handing a few tablets to someone with the same symptoms transfers the '
          'drug without any of that. The most common harm is not the wrong '
          'diagnosis but an interaction with something the other person takes '
          'and you do not.',
      'It also removes the record. Nothing about a shared medicine appears in '
          'the notes of the person who took it, so the next clinician to see '
          'them is reasoning from an incomplete list.',
      'The safe version of the same instinct is helping someone get seen — '
          'not shortening the queue with a handful of your own supply.',
    ],
    sourceName: 'World Health Organization',
    sourceUrl: 'https://www.who.int/health-topics/medicines',
  ),
];

/// One multiple-choice question for the feed's quiz.
@immutable
class InsightQuizQuestion {
  const InsightQuizQuestion({
    required this.question,
    required this.options,
    required this.answerIndex,
    required this.explanation,
  });

  final String question;
  final List<String> options;
  final int answerIndex;

  /// Shown after answering, right or wrong. A quiz that only says "correct"
  /// teaches nothing.
  final String explanation;
}

const List<InsightQuizQuestion> kInsightQuiz = [
  InsightQuizQuestion(
    question:
        'You are on simvastatin. Which breakfast drink is worth asking your '
        'pharmacist about?',
    options: ['Orange juice', 'Grapefruit juice', 'Black coffee'],
    answerIndex: 1,
    explanation:
        'Grapefruit juice blocks the enzymes that clear simvastatin, so more of '
        'the drug reaches the blood than the dose intended. The FDA lists it '
        'explicitly.',
  ),
  InsightQuizQuestion(
    question:
        'Roughly what share of people with a long-term condition take their '
        'medicine as prescribed?',
    options: ['About 50%', 'About 75%', 'About 95%'],
    answerIndex: 0,
    explanation:
        'The WHO puts adherence to long-term treatment at around 50% in '
        'developed countries, and likely lower elsewhere.',
  ),
  InsightQuizQuestion(
    question:
        'You feel completely better three days into a seven-day antibiotic '
        'course. What should you do?',
    options: [
      'Stop — the infection has cleared',
      'Finish the full course',
      'Halve the dose for the rest',
    ],
    answerIndex: 1,
    explanation:
        'Feeling better is not the same as being clear. Unfinished courses '
        'compromise the treatment and help resistant bacteria spread.',
  ),
  InsightQuizQuestion(
    question:
        'Which pairing carries a clearly raised risk of gastrointestinal '
        'bleeding?',
    options: [
      'Warfarin with ibuprofen',
      'Warfarin with paracetamol',
      'Ibuprofen with vitamin D',
    ],
    answerIndex: 0,
    explanation:
        'Anti-inflammatories and anticoagulants act on bleeding through '
        'different routes, and together roughly double the odds of a serious '
        'gastrointestinal bleed.',
  ),

  InsightQuizQuestion(
    question:
        'You take a paracetamol tablet for a headache, then a flu sachet that '
        'also contains paracetamol. What has happened?',
    options: [
      'Nothing — they are different medicines',
      'You have taken two doses of the same drug',
      'The sachet cancels out the tablet',
    ],
    answerIndex: 1,
    explanation:
        'Paracetamol is an ingredient, not only a product. Two products '
        'listing it are the same medicine for the purpose of the daily '
        'maximum, which is how accidental overdose happens to careful people.',
  ),
  InsightQuizQuestion(
    question: 'Where is the worst place to keep most medicines?',
    options: ['A bedroom drawer', 'The bathroom cabinet', 'A kitchen cupboard'],
    answerIndex: 1,
    explanation:
        'Medicines want cool, dry and dark. A bathroom is reliably warm and '
        'damp several times a day — an unfortunate thing to have named the '
        'medicine cabinet after.',
  ),
  InsightQuizQuestion(
    question:
        'You are prescribed an antibiotic and a calcium supplement. What is '
        'the sensible move?',
    options: [
      'Take them together to avoid forgetting',
      'Space them a couple of hours apart',
      'Stop the calcium entirely',
    ],
    answerIndex: 1,
    explanation:
        'Calcium binds certain antibiotics in the gut and carries them through '
        'unabsorbed — the dose is taken but never arrives. Spacing them is '
        'usually the whole fix.',
  ),
  InsightQuizQuestion(
    question:
        'A friend has the same symptoms you had last month and you still have '
        'tablets left. What is the risk you cannot see?',
    options: [
      'The tablets may have expired',
      'They may interact with something your friend takes',
      'There is no real risk',
    ],
    answerIndex: 1,
    explanation:
        'Dose is calculated from one person\'s weight, kidney function and '
        'existing medicines. The most common harm from sharing is an '
        'interaction with something the other person takes and you do not.',
  ),
];

/// One headline figure for the "By the numbers" strip.
@immutable
class InsightFigure {
  const InsightFigure({
    required this.value,
    required this.caption,
    required this.source,
    required this.accent,
  });

  /// The number itself, set large. Kept short — a figure that needs a second
  /// line has stopped being a figure.
  final String value;
  final String caption;
  final String source;
  final Color accent;
}

const List<InsightFigure> kInsightFigures = [
  InsightFigure(
    value: '50%',
    caption: 'of people with a long-term condition take their medicine as '
        'prescribed',
    source: 'WHO',
    accent: _adherence,
  ),
  InsightFigure(
    value: '1 in 3',
    caption: 'antibiotic courses is never finished, at the low end of the '
        'estimates',
    source: 'Peer-reviewed literature',
    accent: _antibiotics,
  ),
  InsightFigure(
    value: '3 g',
    caption: 'the daily paracetamol ceiling the FDA suggested in 2012, below '
        'the familiar 4 g',
    source: 'FDA',
    accent: _everyday,
  ),
];

/// Short, checkable facts for the feed's between-articles break.
const List<String> kInsightFacts = [
  'Paracetamol hides inside many cold, flu and sleep remedies — which is how '
      'people pass the daily limit without exceeding any single label.',
  'The FDA requires grapefruit warnings on some medicines taken by mouth, '
      'including certain statins, blood-pressure drugs and transplant medicines.',
  'Between 30% and 50% of antibiotic courses are never completed.',
  'Among anti-inflammatories studied with warfarin, naproxen carried more than '
      'twice the bleeding hazard of ibuprofen.',
  'Most medicines want somewhere cool, dry and dark — which is precisely what a '
      'bathroom is not.',
];
