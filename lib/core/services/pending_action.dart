import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// A gated write action deferred until the user has a real (non-guest)
/// account, persisted to disk rather than just held in memory — completing
/// sign-in on web is a full-page OAuth redirect that tears down the running
/// app, so any in-memory "resume this after sign-in" closure would be lost.
/// [type] + [payload] together carry just enough to re-run the equivalent
/// action once the app reloads signed in; see `resolvePendingAction` in
/// sign_in_gate.dart for where each [type] maps to a real repository call.
class PendingAction {
  final String type;
  final Map<String, dynamic> payload;
  const PendingAction({required this.type, this.payload = const {}});

  Map<String, dynamic> toJson() => {'type': type, 'payload': payload};

  factory PendingAction.fromJson(Map<String, dynamic> json) => PendingAction(
        type: json['type'] as String,
        payload:
            (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  static const _key = 'explorife.pending_action';

  static Future<void> save(PendingAction action) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(action.toJson()));
  }

  /// Reads back and clears whatever's stored — one-shot by design, so a
  /// stale action from an abandoned sign-in attempt never resurfaces on a
  /// later, unrelated sign-in.
  static Future<PendingAction?> takeAndClear() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    await prefs.remove(_key);
    try {
      return PendingAction.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
