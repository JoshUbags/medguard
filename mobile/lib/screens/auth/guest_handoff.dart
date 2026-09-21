import 'package:flutter/material.dart';

import '../../services/guest_data_migration.dart';
import '../../widgets/common/app_notice.dart';
import '../../widgets/common/modal_sheet.dart';

/// The moment a guest becomes an account holder, and what happens to the record
/// they built before they had one.
///
/// It is asked, never assumed. On a shared phone the medicines sitting under
/// the local fixture may belong to somebody else entirely, so silently folding
/// them into whichever account just signed in would attach one person's
/// medication list to another person's name — in a safety app, the worst thing
/// this hand-over could do.
///
/// Declining is equally non-destructive: "Not now" leaves every row exactly
/// where it is, and the offer comes back on the Profile screen, so nobody can
/// lose a record by tapping the quiet button.
Future<void> offerGuestRecordHandoff(
  BuildContext context, {
  required String userId,
}) async {
  final summary = await GuestDataMigration.instance.summarise();
  if (summary.isEmpty || !context.mounted) return;

  final confirmed = await showConfirmSheet(
    context: context,
    title: 'Bring your record with you?',
    message:
        'This phone already holds ${summary.describe()} from before you '
        'signed in. Adding them to this account keeps your safety checks '
        'accurate — leave them out and this account starts empty.',
    confirmLabel: 'Bring it over',
    cancelLabel: 'Not now',
    icon: Icons.move_up_rounded,
  );
  if (confirmed != true) {
    if (context.mounted) {
      showAppNotice(
        context,
        'Left on this device. You can bring it over from Profile.',
      );
    }
    return;
  }

  final moved = await GuestDataMigration.instance.adopt(userId);
  if (!context.mounted) return;
  showAppNotice(
    context,
    moved > 0
        ? 'Your record is now part of this account.'
        : 'Everything was already on this account.',
    type: AppNoticeType.success,
  );
}

/// Permanently deletes the record left behind by a declined hand-over.
///
/// Offered only from Profile, only when such a record exists, and only behind
/// its own destructive confirmation — this is the one path in the flow that
/// removes clinical data, so it is never reachable by dismissing something.
Future<bool> confirmDiscardGuestRecord(BuildContext context) async {
  final summary = await GuestDataMigration.instance.summarise();
  if (summary.isEmpty || !context.mounted) return false;

  final confirmed = await showConfirmSheet(
    context: context,
    title: 'Delete the local record?',
    message:
        'Permanently removes ${summary.describe()} saved on this device '
        'before you signed in. Your account keeps everything it already has. '
        'MedGuard holds no copy to restore from.',
    confirmLabel: 'Delete it',
    destructive: true,
    icon: Icons.delete_forever_rounded,
  );
  if (confirmed != true) return false;

  await GuestDataMigration.instance.discard();
  if (context.mounted) {
    showAppNotice(context, 'Local record deleted.', type: AppNoticeType.success);
  }
  return true;
}
