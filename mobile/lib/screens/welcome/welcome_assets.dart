import 'package:flutter/widgets.dart';

/// The Welcome hero — a bundled flat-lay; the Welcome screen brightens it with a
/// colour filter and fades it into a light scrim for legibility.
const String kWelcomeHeroAsset = 'assets/images/onboarding/15.jpg';

/// Decode widths, downsampled to ~2× their on-screen size: instant paint, no
/// memory bloat, no network.
const int kWelcomeHeroCacheWidth = 1080; // full-bleed Welcome hero
const int kOnboardingDepthCardCacheWidth =
    640; // interaction-review depth cards
const int kMedicationTileCacheWidth = 480; // medication-context collage tiles

/// The two blurred photographs behind the interaction-review glass case.
const List<String> kInteractionDepthAssets = [
  'assets/images/onboarding/04.jpg', // meal — "with food" context
  'assets/images/onboarding/06.jpg', // single capsule held in hand
];

/// Every photograph the "See Medication Context" collage draws from. Keep this
/// in sync with the tiles in MedicationContextScreen — it exists so the collage
/// is warmed during loading and paints instantly when reached.
const List<String> kMedicationContextAssets = [
  'assets/images/onboarding/03.jpg', // clinician with two pill types (focal)
  'assets/images/onboarding/02.jpg', // hand + three pills
  'assets/images/onboarding/01.jpg', // plate + thermometer
  'assets/images/onboarding/08.jpg', // citrus + blister pack
  'assets/images/onboarding/05.jpg', // pill on the tongue (wide)
];

/// Warms every onboarding photograph while the loading screen is visible, so the
/// Welcome hero and the onboarding screens paint without a flash or jank.
Future<void> precacheOnboardingMedia(BuildContext context) async {
  Future<void> warm(String asset, int width) =>
      precacheImage(ResizeImage(AssetImage(asset), width: width), context);

  await Future.wait([
    warm(kWelcomeHeroAsset, kWelcomeHeroCacheWidth),
    for (final asset in kInteractionDepthAssets)
      warm(asset, kOnboardingDepthCardCacheWidth),
    for (final asset in kMedicationContextAssets)
      warm(asset, kMedicationTileCacheWidth),
  ]);
}
