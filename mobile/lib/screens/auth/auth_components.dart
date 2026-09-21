import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../widgets/common/app_notice.dart';

/// Shared notice helper for the auth screens.
void showAuthSnackBar(
  BuildContext context,
  String message, {
  bool isError = true,
}) {
  showAppNotice(
    context,
    message,
    type: isError ? AppNoticeType.error : AppNoticeType.success,
  );
}

String authErrorMessage(Object error) {
  if (error is GoogleSignInException) {
    // The user dismissing the native Google sheet is a normal, non-error
    // outcome — report it gently; everything else is a real failure.
    return switch (error.code) {
      GoogleSignInExceptionCode.canceled ||
      GoogleSignInExceptionCode.interrupted => 'Sign-in was cancelled.',
      _ =>
        error.description?.trim().isNotEmpty == true
            ? error.description!.trim()
            : 'Google sign-in failed. Please try again.',
    };
  }

  if (error is FirebaseAuthException) {
    return switch (error.code) {
      'invalid-email' => 'Enter a valid email address.',
      'invalid-credential' ||
      'wrong-password' ||
      'user-not-found' => 'Email or password is incorrect.',
      'user-disabled' => 'This account has been disabled.',
      'email-already-in-use' => 'An account already exists for this email.',
      'weak-password' => 'Choose a stronger password.',
      'operation-not-allowed' =>
        'This sign-in method is not enabled for MedGuard yet.',
      'network-request-failed' =>
        'Network error. Check your connection and try again.',
      'too-many-requests' =>
        'Too many attempts. Please wait a moment and try again.',
      'account-exists-with-different-credential' =>
        'This email is already linked to another sign-in method.',
      'popup-closed-by-user' ||
      'web-context-canceled' ||
      'canceled' => 'Sign-in was cancelled.',
      _ => error.message ?? 'Authentication failed. Please try again.',
    };
  }

  return 'Authentication failed. Please try again.';
}

String? validateRequired(String? value, String label) {
  if (value == null || value.trim().isEmpty) {
    return '$label is required.';
  }
  return null;
}

// Stricter than the classic "something@something.tld" check: requires a real
// label structure on both sides and a 2+ letter TLD, so values like
// "a@b.c" or "user@localhost" are rejected before they ever reach Firebase.
final _emailRegExp = RegExp(
  r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$',
);

/// Common disposable / temporary mailbox providers. Accounts created with
/// these can't receive the verification link and are routinely abused, so we
/// block them at the form before sign-up. Lower-cased, domain-only.
const Set<String> kDisposableEmailDomains = {
  '10minutemail.com',
  '10minutemail.net',
  '20minutemail.com',
  'guerrillamail.com',
  'guerrillamail.net',
  'guerrillamail.org',
  'guerrillamail.biz',
  'guerrillamail.de',
  'grr.la',
  'sharklasers.com',
  'mailinator.com',
  'mailinator.net',
  'mailinator2.com',
  'maildrop.cc',
  'tempmail.com',
  'temp-mail.org',
  'temp-mail.io',
  'tempmail.net',
  'tempmailo.com',
  'tempr.email',
  'tmpmail.org',
  'tmpmail.net',
  'throwawaymail.com',
  'throwaway.email',
  'getnada.com',
  'nada.email',
  'trashmail.com',
  'trashmail.de',
  'trash-mail.com',
  'wegwerfmail.de',
  'yopmail.com',
  'yopmail.net',
  'yopmail.fr',
  'cool.fr.nf',
  'jetable.org',
  'dispostable.com',
  'mailnesia.com',
  'mailcatch.com',
  'mintemail.com',
  'mohmal.com',
  'fakeinbox.com',
  'fakemailgenerator.com',
  'spambog.com',
  'mailnull.com',
  'spam4.me',
  'mvrht.net',
  'inboxbear.com',
  'emailondeck.com',
  'mailtemp.net',
  'moakt.com',
  'tempinbox.com',
  'discard.email',
  'spamgourmet.com',
  'mytemp.email',
  'burnermail.io',
  'luxusmail.org',
  'dropmail.me',
  'harakirimail.com',
  '33mail.com',
  'anonbox.net',
  'mailsac.com',
  'tempemail.net',
  'fakemail.net',
  'instant-mail.de',
};

bool isDisposableEmailDomain(String email) {
  final at = email.lastIndexOf('@');
  if (at < 0) return false;
  final domain = email.substring(at + 1).trim().toLowerCase();
  return kDisposableEmailDomains.contains(domain);
}

String? validateEmail(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return 'Email is required.';
  if (!_emailRegExp.hasMatch(text)) return 'Enter a valid email address.';
  if (isDisposableEmailDomain(text)) {
    return 'Temporary email addresses are not allowed.';
  }
  return null;
}
