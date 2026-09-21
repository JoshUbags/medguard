import 'package:flutter/material.dart';

import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';
import '../../widgets/common/pressable.dart';
import '../../widgets/common/morph_loader.dart';

/// Shared social sign-in UI used by both the login and register screens.
/// Previously each screen carried its own copy of these three widgets and the
/// logo-asset constants; consolidating them keeps the providers looking and
/// behaving identically wherever they appear.

const String kGoogleLogoAsset = 'assets/logos/google.png';
const String kAppleLogoAsset = 'assets/logos/apple.png';

/// A circular, tappable provider button. [loading] swaps the [child] for a
/// spinner; [disabled] greys out and blocks taps.
class SocialCircleButton extends StatelessWidget {
  const SocialCircleButton({
    super.key,
    required this.semanticLabel,
    required this.onTap,
    required this.child,
    this.loading = false,
    this.disabled = false,
  });

  final String semanticLabel;
  final VoidCallback onTap;
  final Widget child;
  final bool loading;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Pressable(
        disabled: disabled,
        onTap: disabled ? null : onTap,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: context.colors.surface,
            border: Border.all(color: context.colors.border),
            boxShadow: [
              BoxShadow(
                color: MedGuardPalette.blackAlpha(0.045),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: loading
                ? MorphLoader(
                    size: 20,
                    color: context.colors.accent,
                    glow: false,
                  )
                : child,
          ),
        ),
      ),
    );
  }
}

/// Renders a bundled provider logo (Google/Apple), falling back to [fallback]
/// if the asset can't be decoded.
class SocialLogoMark extends StatelessWidget {
  const SocialLogoMark({
    super.key,
    required this.asset,
    required this.fallback,
    required this.size,
  });

  final String asset;
  final IconData fallback;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      asset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      cacheWidth: 96,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) =>
          Icon(fallback, color: context.colors.ink, size: size),
    );
  }
}

/// The four-square Microsoft brand mark, drawn so no extra asset is needed.
class MicrosoftMark extends StatelessWidget {
  const MicrosoftMark({super.key});

  @override
  Widget build(BuildContext context) {
    const colors = [
      Color(0xFFF25022),
      Color(0xFF7FBA00),
      Color(0xFF00A4EF),
      Color(0xFFFFB900),
    ];

    return SizedBox(
      width: 25,
      height: 25,
      child: Wrap(
        spacing: 3,
        runSpacing: 3,
        children: [
          for (final color in colors)
            Container(
              width: 11,
              height: 11,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
        ],
      ),
    );
  }
}
