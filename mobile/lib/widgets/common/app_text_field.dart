import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../theme/medguard_colors.dart';
import '../../theme/medguard_palette.dart';

/// The app's single, shared text field — a modern inset field in the iOS
/// idiom: a softly tinted fill with NO outline at rest, a hairline accent
/// ring and brighter fill on focus, an optional thin leading icon, and a
/// floating label.
///
/// Every form in the app renders through this widget — the auth screens AND
/// every text entry inside a modal sheet (emergency contact, display name, care
/// profiles, the PIN, problem reports). Sheets used to build stock Material
/// outlined fields with a notched label, which made the one moment a user types
/// something look like a different app.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.keyboardType,
    this.obscure = false,
    this.suffix,
    this.autofillHints,
    this.textInputAction,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
    this.minLines,
    this.maxLength,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String label;

  /// Placeholder shown once the label has floated — an example of the answer.
  final String? hint;

  /// Optional thin leading icon (Cupertino/SF style). Tints to the accent
  /// while the field has focus.
  final IconData? icon;
  final TextInputType? keyboardType;
  final bool obscure;
  final Widget? suffix;
  final Iterable<String>? autofillHints;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final TextCapitalization textCapitalization;

  /// Lines of text. Anything above one makes a multi-line field whose label
  /// sits at the top rather than floating in the vertical middle.
  final int maxLines;
  final int? minLines;

  /// Caps the input. The Material character counter is suppressed — the limit
  /// is enforced, not narrated.
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focused != _focusNode.hasFocus) {
        setState(() => _focused = _focusNode.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final borderRadius = BorderRadius.circular(16);
    final multiline = !widget.obscure && widget.maxLines > 1;

    // Resting: a quiet tinted inset with no stroke. Focused: the fill lifts
    // to the raised surface and a hairline accent ring draws around it.
    final restingBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide.none,
    );
    final focusedBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: colors.accent, width: 1.4),
    );
    final errorBorder = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: colors.danger, width: 1.3),
    );

    return TextFormField(
      controller: widget.controller,
      focusNode: _focusNode,
      keyboardType: multiline ? TextInputType.multiline : widget.keyboardType,
      obscureText: widget.obscure,
      autofillHints: widget.autofillHints,
      textInputAction: widget.textInputAction,
      validator: widget.validator,
      onChanged: widget.onChanged,
      onFieldSubmitted: widget.onSubmitted,
      autofocus: widget.autofocus,
      textCapitalization: widget.textCapitalization,
      maxLines: widget.obscure ? 1 : widget.maxLines,
      minLines: widget.obscure ? null : widget.minLines,
      maxLength: widget.maxLength,
      inputFormatters: widget.inputFormatters,
      cursorColor: colors.accent,
      style: GoogleFonts.inter(
        color: colors.ink,
        fontSize: 14.5,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
        height: multiline ? 1.4 : null,
      ),
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hint,
        alignLabelWithHint: multiline,
        counterText: widget.maxLength == null ? null : '',
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        floatingLabelStyle: GoogleFonts.inter(
          color: _focused ? colors.accent : colors.inkMute,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
        labelStyle: GoogleFonts.inter(
          color: colors.inkMute.withValues(alpha: 0.75),
          fontSize: 13.8,
          fontWeight: FontWeight.w400,
        ),
        hintStyle: GoogleFonts.inter(
          color: colors.inkMute.withValues(alpha: 0.7),
          fontSize: 13.8,
          fontWeight: FontWeight.w400,
        ),
        filled: true,
        fillColor: _focused ? colors.surface : colors.surfaceAlt,
        prefixIcon: widget.icon == null
            ? null
            : Icon(
                widget.icon,
                size: 19,
                color: _focused ? colors.accent : colors.inkMute,
              ),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 46,
          minHeight: 46,
        ),
        suffixIcon: widget.suffix,
        border: restingBorder,
        enabledBorder: restingBorder,
        focusedBorder: focusedBorder,
        errorBorder: errorBorder,
        focusedErrorBorder: errorBorder.copyWith(
          borderSide: BorderSide(color: colors.danger, width: 1.5),
        ),
        errorStyle: GoogleFonts.inter(
          color: MedGuardPalette.rubyDeep,
          fontSize: 11.5,
          fontWeight: FontWeight.w500,
          height: 1.2,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
      ),
    );
  }
}
