import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/gem_provider.dart';
import 'pending_action.dart';

/// Maps a [PendingAction.type] to the real work that got deferred by
/// [requireAccount] (sign_in_sheet.dart), then returns where to land the
/// user afterward. Called once, right after sign-in actually completes
/// (`_AuthCallbackScreen` in app_router.dart).
///
/// Only 'save_gem' re-runs the ORIGINAL write automatically — it's a single
/// id-keyed call with nothing else to reconstruct. The form-based actions
/// (drop a gem, create a trip, submit a story, ...) carry enough in-progress
/// field state that fully resuming them would mean persisting a whole draft
/// across the OAuth redirect, not just an id — out of scope for this pass.
/// Those land the user back on the screen where they can hit the same
/// button again, now signed in, rather than being silently dropped or stuck.
Future<String> resolvePendingAction(
    BuildContext context, PendingAction action) async {
  switch (action.type) {
    case 'save_gem':
      final gemId = action.payload['gemId'] as String?;
      if (gemId == null) return '/home';
      final gemProv = context.read<GemProvider>();
      final gem = await gemProv.fetchById(gemId);
      if (gem != null && !gemProv.isSaved(gem.id)) {
        await gemProv.toggleSave(gem);
      }
      return '/gems/$gemId';
    case 'drop_gem':
      return '/drop-gem';
    case 'create_trip':
      return '/trips/new';
    case 'submit_story':
      return '/submit-story';
    case 'add_traveler':
    case 'edit_profile':
      return '/profile';
    case 'log_hike':
      return '/log-hike';
    default:
      return '/home';
  }
}
