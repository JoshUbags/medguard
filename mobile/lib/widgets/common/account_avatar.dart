import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/connectivity_service.dart';
import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';
import '../../theme/medguard_responsive.dart';
import 'pressable.dart';
import 'morph_loader.dart';

const _avatarOnline = Color(0xFF22C55E);
const _avatarOffline = Color(0xFFFF6B6B);

bool _runningUnderFlutterTest() {
  try {
    return WidgetsBinding.instance.runtimeType.toString().contains(
      'AutomatedTest',
    );
  } catch (_) {
    return false;
  }
}

/// The shared account avatar — the user's photo, or their initials, or a person
/// icon — in a framed circle with a live connection dot. Used by the home header
/// and the interactions header so the profile picture is identical across the
/// app. Tap opens the profile.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({
    super.key,
    required this.photoUrl,
    required this.size,
    this.name,
    this.onTap,
    this.connectivityService,
    this.avatarKey,
    this.statusDotKey,
  });

  final String? photoUrl;
  final double size;
  final String? name;
  final VoidCallback? onTap;
  final ConnectivityService? connectivityService;
  final Key? avatarKey;
  final Key? statusDotKey;

  /// The user's initials (first + last) when a name is known — the fallback fill
  /// when there is no profile photo. Null when there is no usable name.
  String? _initials() {
    final trimmed = name?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    final parts = trimmed
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;
    String head(String s) => s.characters.first.toUpperCase();
    if (parts.length == 1) return head(parts.first);
    return head(parts.first) + head(parts.last);
  }

  Widget _fallback(MedGuardColors colors) {
    final initials = _initials();
    if (initials == null) {
      return ColoredBox(
        color: colors.accentAlpha(0.10),
        child: Icon(
          Icons.person_rounded,
          color: colors.accent,
          size: size * 0.58,
        ),
      );
    }
    return Container(
      color: colors.accentAlpha(0.12),
      alignment: Alignment.center,
      child: Text(
        initials,
        textAlign: TextAlign.center,
        style: GoogleFonts.inter(
          color: colors.accent,
          fontSize: size * (initials.length > 1 ? 0.38 : 0.46),
          fontWeight: FontWeight.w700,
          height: 1.0,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final colors = context.colors;
    final imageUrl = photoUrl;
    final dotSize = (size * 0.33).clamp(12.0, 18.0).toDouble();

    final avatar = Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          key: avatarKey,
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colors.surface, width: 1.4),
            boxShadow: [
              BoxShadow(
                color: MedGuardPalette.inkAlpha(0.08),
                blurRadius: responsive.s(10),
                offset: Offset(0, responsive.s(4)),
              ),
            ],
          ),
          child: ClipOval(
            child: imageUrl == null
                ? _fallback(colors)
                : Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return ColoredBox(
                        color: colors.accentAlpha(0.10),
                        child: Center(
                          child: MorphLoader(
                            size: size * 0.4,
                            color: colors.accent,
                            glow: false,
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) =>
                        _fallback(colors),
                  ),
          ),
        ),
        Positioned(
          right: responsive.s(0),
          bottom: responsive.s(1),
          child: _AccountConnectionDot(
            service: connectivityService,
            size: dotSize,
            dotKey: statusDotKey,
          ),
        ),
      ],
    );

    if (onTap == null) return avatar;
    return Tooltip(
      message: 'Open profile',
      child: Pressable(onTap: onTap, pressScale: 0.94, child: avatar),
    );
  }
}

class _AccountConnectionDot extends StatelessWidget {
  const _AccountConnectionDot({required this.size, this.service, this.dotKey});

  final double size;
  final ConnectivityService? service;
  final Key? dotKey;

  @override
  Widget build(BuildContext context) {
    if (_runningUnderFlutterTest() && service == null) {
      return _buildDot(context, online: true);
    }
    final source = service ?? ConnectivityService.instance;
    return StreamBuilder<bool>(
      stream: source.watch(),
      initialData: true,
      builder: (context, snapshot) {
        final online = snapshot.data ?? true;
        return _buildDot(context, online: online);
      },
    );
  }

  Widget _buildDot(BuildContext context, {required bool online}) {
    return Container(
      key: dotKey,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: online ? _avatarOnline : _avatarOffline,
        shape: BoxShape.circle,
        // Ring matches the page behind it so the dot reads as punched out.
        border: Border.all(color: context.colors.scaffold, width: 2.2),
      ),
    );
  }
}
