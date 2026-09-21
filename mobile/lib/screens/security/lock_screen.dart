import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/app_lock_service.dart';
import '../../theme/medguard_colors.dart';
import '../../theme/medguard_responsive.dart';
import '../../widgets/common/page_background.dart';
import '../../widgets/common/page_header.dart';
import '../../widgets/common/pressable.dart';

/// Full-screen lock displayed when the app is locked. Surfaces biometric
/// unlock when supported + preferred, falls back to a 6-digit PIN keypad.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.onUnlock, this.service});

  final VoidCallback onUnlock;
  final AppLockService? service;

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _pin = '';
  String? _error;
  bool _busy = false;

  AppLockService get _service => widget.service ?? AppLockService.instance;

  @override
  void initState() {
    super.initState();
    // Try biometric immediately when the screen opens.
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
  }

  Future<void> _tryBiometric() async {
    if (!_service.biometricPreferred) return;
    if (!await _service.isBiometricSupported()) return;
    final ok = await _service.authenticateBiometric('Unlock MedGuard');
    if (!mounted) return;
    if (ok) _success();
  }

  void _success() {
    HapticFeedback.mediumImpact();
    _service.markUnlocked();
    widget.onUnlock();
  }

  Future<void> _enterDigit(String digit) async {
    if (_busy) return;
    if (_pin.length >= 6) return;
    setState(() {
      _pin = _pin + digit;
      _error = null;
    });
    if (_pin.length == 6) {
      setState(() => _busy = true);
      final ok = await _service.verifyPin(_pin);
      if (!mounted) return;
      if (ok) {
        _success();
      } else {
        HapticFeedback.vibrate();
        setState(() {
          _pin = '';
          _busy = false;
          _error = 'Incorrect PIN — try again.';
        });
      }
    }
  }

  void _backspace() {
    if (_pin.isEmpty || _busy) return;
    setState(() {
      _pin = _pin.substring(0, _pin.length - 1);
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return Scaffold(
      backgroundColor: context.colors.scaffold,
      // The app's own ambient canvas, so the lock reads as MedGuard's front
      // door rather than a flat system sheet.
      body: PageBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: responsive.pageX),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: responsive.s(64),
                      height: responsive.s(64),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: context.colors.accentAlpha(0.10),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.lock_rounded,
                        color: context.colors.accent,
                        size: responsive.icon(28),
                      ),
                    ),
                    SizedBox(height: responsive.s(16)),
                    Text(
                      'MedGuard is locked',
                      textAlign: TextAlign.center,
                      style: pageTitleStyle(responsive, context.colors.ink),
                    ),
                    SizedBox(height: responsive.s(6)),
                    Text(
                      _service.biometricPreferred
                          ? 'Use your biometric or enter your 6-digit PIN.'
                          : 'Enter your 6-digit PIN to continue.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: context.colors.inkSoft,
                        fontSize: responsive.font(12.6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: responsive.s(28)),
                    _PinDots(length: _pin.length, error: _error != null),
                    if (_error != null) ...[
                      SizedBox(height: responsive.s(12)),
                      Text(
                        _error!,
                        style: GoogleFonts.inter(
                          color: context.colors.danger,
                          fontSize: responsive.font(12),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    SizedBox(height: responsive.s(28)),
                    _Keypad(
                      onDigit: _enterDigit,
                      onBackspace: _backspace,
                      onBiometric: _service.biometricPreferred
                          ? _tryBiometric
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({required this.length, required this.error});

  final int length;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < 6; i++) ...[
          Container(
            width: responsive.s(14),
            height: responsive.s(14),
            decoration: BoxDecoration(
              color: i < length
                  ? (error ? context.colors.danger : context.colors.accent)
                  : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(
                color: error
                    ? context.colors.danger
                    : context.colors.inkMute.withValues(alpha: 0.5),
                width: 1.6,
              ),
            ),
          ),
          if (i < 5) SizedBox(width: responsive.s(12)),
        ],
      ],
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onDigit,
    required this.onBackspace,
    required this.onBiometric,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    Widget digit(String d) => _KeypadKey(label: d, onTap: () => onDigit(d));
    final spacer = SizedBox.square(dimension: _KeypadKey.extentOf(responsive));

    // An explicit three-column phone keypad. It used to be a Wrap, which laid
    // the keys out four to a row (1-4, 5-8, 9 · 0 ⌫) on any screen wide enough
    // for four — a layout no one has ever typed a PIN on.
    final rows = <List<Widget>>[
      [digit('1'), digit('2'), digit('3')],
      [digit('4'), digit('5'), digit('6')],
      [digit('7'), digit('8'), digit('9')],
      [
        if (onBiometric != null)
          _KeypadKey(icon: Icons.fingerprint_rounded, onTap: onBiometric!)
        else
          spacer,
        digit('0'),
        _KeypadKey(icon: Icons.backspace_rounded, onTap: onBackspace),
      ],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var r = 0; r < rows.length; r++) ...[
          if (r > 0) SizedBox(height: responsive.s(14)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var k = 0; k < rows[r].length; k++) ...[
                if (k > 0) SizedBox(width: responsive.s(24)),
                rows[r][k],
              ],
            ],
          ),
        ],
      ],
    );
  }
}

class _KeypadKey extends StatelessWidget {
  const _KeypadKey({this.label, this.icon, required this.onTap})
    : assert(label != null || icon != null);

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  static double extentOf(MedGuardResponsive responsive) =>
      responsive.s(66).clamp(58.0, 74.0).toDouble();

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final size = extentOf(responsive);
    return Pressable(
      onTap: onTap,
      pressScale: 0.92,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.colors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: context.colors.border),
        ),
        child: icon != null
            ? Icon(
                icon,
                color: context.colors.inkSoft,
                size: responsive.icon(22),
              )
            : Text(
                label!,
                style: GoogleFonts.inter(
                  color: context.colors.ink,
                  fontSize: responsive.font(24),
                  fontWeight: FontWeight.w500,
                ),
              ),
      ),
    );
  }
}
