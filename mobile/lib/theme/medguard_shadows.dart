import 'package:flutter/material.dart';

import 'medguard_palette.dart';

/// Shared elevation tokens.
///
/// Popups, bottom sheets, and dialogs use [modal] — a soft, wide, low-opacity
/// shadow built from two stacked layers with negative spread, so the surface
/// reads as gently lifted (premium iOS / fintech) rather than a hard floating
/// black rectangle. The wide ambient layer carries the depth; the tighter
/// contact layer grounds the surface. Both fade smoothly with no hard edge.
class MedGuardShadows {
  const MedGuardShadows._();

  /// THE standard card elevation used across the app — a single, soft,
  /// low-opacity ambient shadow with negative spread so its edges dissolve
  /// (never a hard grey rectangle). Reads as a gentle lift on the near-white
  /// canvas; effectively invisible on dark surfaces, which separate by border
  /// instead. Use this for every raised card so elevation is consistent.
  static List<BoxShadow> get card => [
    BoxShadow(
      color: MedGuardPalette.inkAlpha(0.05),
      blurRadius: 24,
      spreadRadius: -10,
      offset: const Offset(0, 10),
    ),
  ];

  /// A lighter version of [card] for small chips, tiles, and pills, so tiny
  /// surfaces don't carry a disproportionately large shadow.
  static List<BoxShadow> get soft => [
    BoxShadow(
      color: MedGuardPalette.inkAlpha(0.04),
      blurRadius: 14,
      spreadRadius: -6,
      offset: const Offset(0, 6),
    ),
  ];

  /// Soft elevation for popups and modal surfaces.
  static List<BoxShadow> get modal => [
    // Wide ambient halo — big blur, very low opacity, pulled in with negative
    // spread so the edges dissolve instead of banding into a dark rectangle.
    BoxShadow(
      color: MedGuardPalette.blackAlpha(0.07),
      blurRadius: 52,
      spreadRadius: -16,
      offset: const Offset(0, 28),
    ),
    // Tighter contact shadow that quietly grounds the surface.
    BoxShadow(
      color: MedGuardPalette.blackAlpha(0.05),
      blurRadius: 18,
      spreadRadius: -10,
      offset: const Offset(0, 8),
    ),
  ];
}
