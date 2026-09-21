import 'package:flutter/widgets.dart';

/// Drops whatever currently holds focus and closes the soft keyboard with it.
///
/// The app installs this once, at the root of `MaterialApp.builder`, on a
/// translucent [GestureDetector]: tapping anywhere that is not itself an
/// interactive target ends text entry. Without it a field stayed active — and
/// the keyboard stayed up — after the user had moved on to something else.
///
/// [FocusManager] is used rather than `FocusScope.of(context)` so the call
/// works from any context, including the builder's (which sits above every
/// route's own focus scope).
void dismissTextInput() {
  FocusManager.instance.primaryFocus?.unfocus();
}

/// The app-wide convention for scrollables that sit alongside a text field:
/// starting a drag also ends text entry, matching platform behaviour.
const ScrollViewKeyboardDismissBehavior kDismissKeyboardOnDrag =
    ScrollViewKeyboardDismissBehavior.onDrag;
