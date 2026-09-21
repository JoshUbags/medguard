import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/app_lock_service.dart';
import '../../theme/medguard_responsive.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_snack.dart';
import '../../widgets/common/app_text_field.dart';
import '../../widgets/common/detail_page.dart';
import '../../widgets/common/modal_sheet.dart';
import '../../widgets/common/settings_row.dart';
import '../../widgets/common/surface_card.dart';

/// App Lock — enable it, set the PIN, opt into biometrics where the device
/// supports them, and pick how quickly it locks again.
///
/// Built from the same grouped rows as Settings, which is where it is opened
/// from. It used to stack four free-standing cards with round glyphs and a stock
/// Material PIN dialog, so the step from Settings into App Lock looked like a
/// step into a different app.
class AppLockSettingsScreen extends StatefulWidget {
  const AppLockSettingsScreen({super.key});

  static const String routeName = '/security/app-lock';

  @override
  State<AppLockSettingsScreen> createState() => _AppLockSettingsScreenState();
}

class _AppLockSettingsScreenState extends State<AppLockSettingsScreen> {
  AppLockService get _service => AppLockService.instance;
  bool _supportsBiometric = false;
  bool _hasPin = false;

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  Future<void> _hydrate() async {
    await _service.load();
    final supports = await _service.isBiometricSupported();
    final pin = await _service.hasPin();
    if (!mounted) return;
    setState(() {
      _supportsBiometric = supports;
      _hasPin = pin;
    });
  }

  Future<void> _setPinFlow() async {
    final pin = await _promptPin(
      title: _hasPin ? 'Choose a new PIN' : 'Choose a PIN',
      subtitle:
          'Six digits. It unlocks MedGuard whenever biometrics are not '
          'available.',
      confirmLabel: 'Continue',
    );
    if (pin == null || !mounted) return;
    final confirm = await _promptPin(
      title: 'Confirm your PIN',
      subtitle: 'Enter the same six digits again.',
      confirmLabel: 'Save PIN',
    );
    if (confirm == null || !mounted) return;
    if (pin != confirm) {
      AppSnack.error(context, 'Those PINs did not match. Try again.');
      return;
    }
    await _service.setPin(pin);
    if (!mounted) return;
    setState(() => _hasPin = true);
    AppSnack.success(context, 'PIN saved.');
  }

  Future<String?> _promptPin({
    required String title,
    required String subtitle,
    required String confirmLabel,
  }) async {
    final controller = TextEditingController();
    String? pin;

    final confirmed = await showModalSheet<bool>(
      context: context,
      title: title,
      subtitle: subtitle,
      icon: Icons.password_rounded,
      confirmLabel: confirmLabel,
      onConfirm: () {
        final text = controller.text.trim();
        if (!RegExp(r'^\d{6}$').hasMatch(text)) {
          AppSnack.warning(context, 'A PIN is exactly six digits.');
          return false;
        }
        pin = text;
        return true;
      },
      builder: (_) => AppTextField(
        controller: controller,
        label: '6-digit PIN',
        icon: Icons.lock_rounded,
        autofocus: true,
        obscure: true,
        keyboardType: TextInputType.number,
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      ),
    );
    return confirmed == true ? pin : null;
  }

  Future<void> _toggleEnabled(bool value) async {
    if (value && !_hasPin) {
      await _setPinFlow();
      if (!await _service.hasPin()) return; // user cancelled
    }
    await _service.setEnabled(value);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _toggleBiometric(bool value) async {
    if (value) {
      final ok = await _service.authenticateBiometric(
        'Confirm biometric unlock for MedGuard',
      );
      if (!ok) return;
    }
    await _service.setBiometricPreferred(value);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _pickAutoLock() async {
    final picked = await showOptionSheet<int>(
      context: context,
      title: 'Auto-lock delay',
      subtitle:
          'How long MedGuard stays open after you last touched it before it '
          'locks itself again.',
      selected: _service.autoLockWindow.inMinutes,
      options: const [
        SheetOption(
          value: 1,
          label: '1 minute',
          detail: 'Strictest — locks almost as soon as you look away',
          icon: Icons.bolt_rounded,
        ),
        SheetOption(value: 2, label: '2 minutes', icon: Icons.timer_rounded),
        SheetOption(
          value: 5,
          label: '5 minutes',
          detail: 'A good balance for most people',
          icon: Icons.timer_rounded,
        ),
        SheetOption(value: 10, label: '10 minutes', icon: Icons.timer_rounded),
        SheetOption(
          value: 30,
          label: '30 minutes',
          detail: 'Most convenient — least protection if the phone is lost',
          icon: Icons.hourglass_bottom_rounded,
        ),
      ],
    );
    if (picked != null) {
      await _service.setAutoLockMinutes(picked);
      if (!mounted) return;
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final responsive = MedGuardResponsive.of(context);
    final enabled = _service.enabled;
    final minutes = _service.autoLockWindow.inMinutes;
    final gap = SizedBox(height: sectionGap(responsive));

    return DetailPage(
      title: 'App lock',
      subtitle:
          'Keeps your medicines, allergies and dose history behind your '
          'fingerprint or PIN if the phone is left unattended.',
      slivers: [
        SliverToBoxAdapter(
          child: responsive.constrain(
            Padding(
              padding: EdgeInsets.symmetric(horizontal: responsive.pageX),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionBlock(
                    title: 'Lock',
                    subtitle: enabled
                        ? 'Your PIN or biometrics are needed to open MedGuard.'
                        : 'Off. Anyone holding this phone can open MedGuard.',
                    action: enabled ? 'On' : 'Off',
                    card: false,
                    child: SettingsGroup(
                      rows: [
                        SettingsSwitch(
                          icon: Icons.lock_rounded,
                          title: 'Require unlock',
                          subtitle: 'When MedGuard opens or after inactivity',
                          value: enabled,
                          onChanged: _toggleEnabled,
                        ),
                        if (enabled && _supportsBiometric)
                          SettingsSwitch(
                            icon: Icons.fingerprint_rounded,
                            title: 'Biometric unlock',
                            subtitle: 'Fingerprint or face, where available',
                            value: _service.biometricPreferred,
                            onChanged: _toggleBiometric,
                          ),
                      ],
                    ),
                  ),
                  // Everything below only exists while the lock is on. A PIN
                  // or delay row with no lock to configure is dead weight.
                  if (enabled) ...[
                    gap,
                    SectionBlock(
                      title: 'Options',
                      subtitle: 'How the lock behaves once it is on.',
                      card: false,
                      child: SettingsGroup(
                        rows: [
                          SettingsRow(
                            icon: Icons.password_rounded,
                            title: _hasPin ? 'Change PIN' : 'Set a PIN',
                            subtitle: 'Used when biometrics are not available',
                            value: _hasPin ? 'Set' : 'Not set',
                            onTap: _setPinFlow,
                          ),
                          SettingsRow(
                            icon: Icons.timer_rounded,
                            title: 'Auto-lock',
                            subtitle: 'After a period of inactivity',
                            value: '$minutes min',
                            onTap: _pickAutoLock,
                          ),
                        ],
                      ),
                    ),
                    gap,
                    AppButton(
                      label: 'Lock now',
                      icon: Icons.lock_clock_rounded,
                      variant: AppButtonVariant.secondary,
                      onTap: () {
                        _service.requireLock();
                        Navigator.of(context).maybePop();
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
