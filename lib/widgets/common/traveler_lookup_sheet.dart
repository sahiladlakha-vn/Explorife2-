import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../app_network_image.dart';

/// Search-by-email-or-username sheet for adding a traveler to a trip. Used by
/// both the trip-setup wizard's "Who's coming?" step (trip doesn't exist yet
/// — the result is held locally) and the Trip tab's "+ Add Traveler" button
/// (persists immediately via TripSetupProvider.addTraveler). This widget only
/// resolves an identifier to a real account and hands it back via [onSelect]
/// — it has no opinion on what the caller does with the result, so the same
/// search UI serves a not-yet-persisted pending list and a live database
/// write equally well.
///
/// Visual/interaction pattern mirrors AddStopSheet (trip_builder/widgets):
/// debounced search field, a single result row, a persistent footer whose
/// primary action is disabled until there's something valid to add.
class TravelerLookupSheet extends StatefulWidget {
  const TravelerLookupSheet({
    super.key,
    required this.excludeUserIds,
    required this.onSelect,
  });

  /// User ids already on the trip (organizer + already-added travelers) —
  /// resolving to one of these shows "already added" instead of letting a
  /// duplicate through.
  final Set<String> excludeUserIds;
  final ValueChanged<PublicProfile> onSelect;

  @override
  State<TravelerLookupSheet> createState() => _TravelerLookupSheetState();
}

enum _LookupState { idle, searching, found, notFound, alreadyAdded, isSelf }

class _TravelerLookupSheetState extends State<TravelerLookupSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  _LookupState _state = _LookupState.idle;
  PublicProfile? _result;
  int _requestSeq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _state = _LookupState.idle;
        _result = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(query));
  }

  Future<void> _search(String query) async {
    final seq = ++_requestSeq;
    setState(() => _state = _LookupState.searching);
    PublicProfile? found;
    try {
      found = await context.read<AuthProvider>().findUserByIdentifier(query);
    } catch (_) {
      found = null;
    }
    // A newer keystroke's search may have already landed — drop this stale
    // response rather than let it clobber a fresher result.
    if (!mounted || seq != _requestSeq) return;

    final me = context.read<AuthProvider>().user?.id;
    setState(() {
      _result = found;
      if (found == null) {
        _state = _LookupState.notFound;
      } else if (found.id == me) {
        _state = _LookupState.isSelf;
      } else if (widget.excludeUserIds.contains(found.id)) {
        _state = _LookupState.alreadyAdded;
      } else {
        _state = _LookupState.found;
      }
    });
  }

  void _confirm() {
    if (_state != _LookupState.found || _result == null) return;
    HapticFeedback.mediumImpact();
    widget.onSelect(_result!);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.lightSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                  color: AppTheme.lightBorder,
                  borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  const Text('Add a traveler',
                      style: TextStyle(
                          color: AppTheme.lightInk,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text('Search by email or username.',
                      style:
                          TextStyle(color: AppTheme.lightMute, fontSize: 12.5)),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _searchCtrl,
                    autofocus: true,
                    onChanged: _onChanged,
                    style:
                        const TextStyle(color: AppTheme.lightInk, fontSize: 14),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: 'Email or username',
                      hintStyle: const TextStyle(
                          color: AppTheme.lightMute, fontSize: 14),
                      prefixIcon: const Icon(Icons.search,
                          color: AppTheme.lightMute, size: 20),
                      filled: true,
                      fillColor: AppTheme.lightCard,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: AppTheme.lightBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            const BorderSide(color: AppTheme.primary, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _ResultArea(state: _state, result: _result, onTap: _confirm),
                ],
              ),
            ),
            _Footer(state: _state, onAdd: _confirm),
          ],
        ),
      ),
    );
  }
}

class _ResultArea extends StatelessWidget {
  const _ResultArea(
      {required this.state, required this.result, required this.onTap});
  final _LookupState state;
  final PublicProfile? result;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case _LookupState.idle:
        return const SizedBox.shrink();
      case _LookupState.searching:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppTheme.primary),
            ),
          ),
        );
      case _LookupState.notFound:
        return const _InfoMessage(
            icon: Icons.person_search_outlined,
            text: 'No Explorife account found for that email or username.');
      case _LookupState.isSelf:
        return const _InfoMessage(
            icon: Icons.info_outline,
            text: "That's you — you're already on this trip as the organizer.");
      case _LookupState.alreadyAdded:
        return const _InfoMessage(
            icon: Icons.check_circle_outline,
            text: 'Already added to this trip.');
      case _LookupState.found:
        return _TravelerResultRow(profile: result!, onTap: onTap);
    }
  }
}

class _InfoMessage extends StatelessWidget {
  const _InfoMessage({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.lightCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.lightBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.lightMute, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppTheme.lightMute, fontSize: 12.5, height: 1.3)),
          ),
        ],
      ),
    );
  }
}

class _TravelerResultRow extends StatelessWidget {
  const _TravelerResultRow({required this.profile, required this.onTap});
  final PublicProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = profile.displayName;
    final initials = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    final avatarUrl = profile.avatarUrl;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.primarySoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.primary, width: 1.5),
        ),
        child: Row(
          children: [
            ClipOval(
              child: (avatarUrl != null && avatarUrl.isNotEmpty)
                  ? AppNetworkImage(url: avatarUrl, width: 40, height: 40)
                  : Container(
                      width: 40,
                      height: 40,
                      alignment: Alignment.center,
                      color: AppTheme.primary.withValues(alpha: 0.12),
                      child: Text(initials,
                          style: const TextStyle(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w700)),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppTheme.lightInk,
                          fontSize: 14,
                          fontWeight: FontWeight.w700)),
                  if (profile.username != null) ...[
                    const SizedBox(height: 2),
                    Text('@${profile.username}',
                        style: const TextStyle(
                            color: AppTheme.lightMute, fontSize: 12)),
                  ],
                ],
              ),
            ),
            const Icon(Icons.check_circle, color: AppTheme.primary, size: 20),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.state, required this.onAdd});
  final _LookupState state;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final canAdd = state == _LookupState.found;
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: AppTheme.lightSurface,
        border: Border(top: BorderSide(color: AppTheme.lightBorder)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
                canAdd
                    ? 'Ready to add.'
                    : 'Search for an email or username above.',
                style: const TextStyle(
                    color: AppTheme.lightMute,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: canAdd ? onAdd : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              disabledBackgroundColor: AppTheme.lightCard,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Add',
                style: TextStyle(
                    color: canAdd ? Colors.white : AppTheme.lightMute,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
