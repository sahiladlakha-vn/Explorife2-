import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../models/trip.dart';
import '../../providers/trip_provider.dart';
import 'step_one_init.dart';

/// Modal bottom sheet for editing an existing trip's essentials (location,
/// dates, budget, vibe). Reuses [StepOneInit] as-is — it's purely presentational
/// over a [TripDraft], with no opinion on create vs. edit — seeded from the
/// trip being edited instead of blank, with a single "Save changes" action
/// calling [TripProvider.updateTrip] instead of the two-step create flow's
/// [TripProvider.createTrip]. No Step 2 here: template/blueprint choice only
/// ever applies at creation.
class EditTripSheet extends StatefulWidget {
  const EditTripSheet({super.key, required this.trip});

  final Trip trip;

  @override
  State<EditTripSheet> createState() => _EditTripSheetState();
}

class _EditTripSheetState extends State<EditTripSheet> {
  late final TripDraft _draft;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.trip;
    _draft = TripDraft()
      ..title = t.name
      ..description = t.description
      ..location = t.location
      ..locationLat = t.locationLat
      ..locationLng = t.locationLng
      ..dateStart = t.startDate
      ..dateEnd = t.endDate
      ..budgetVnd = t.budgetVnd
      ..currency = t.currency
      ..vibe = t.vibe
      ..coverImageUrl = t.coverImageUrl;
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _isSaving = true);
    try {
      await context.read<TripProvider>().updateTrip(
            widget.trip.id,
            title: _draft.title?.trim(),
            location: _draft.location!.trim(),
            locationLat: _draft.locationLat,
            locationLng: _draft.locationLng,
            description: _draft.description?.trim().isEmpty ?? true
                ? null
                : _draft.description!.trim(),
            startDate: _draft.dateStart!,
            endDate: _draft.dateEnd!,
            budgetVnd: _draft.budgetVnd,
            currency: _draft.currency,
            vibe: _draft.vibe,
            coverImageFile: _draft.coverImageFile,
            coverImageUrl: _draft.coverImageUrl,
          );
      if (!mounted) return;
      navigator.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save changes: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = StepOneInit.isValid(_draft);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.lightSurface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: AppTheme.lightMute,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Expanded(
                    child: Text(
                      'Edit trip',
                      style: TextStyle(
                        color: AppTheme.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.lightCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.lightBorder),
                      ),
                      child: const Icon(Icons.close, color: AppTheme.lightMute, size: 20),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTheme.lightBorder),
            Expanded(
              child: StepOneInit(
                draft: _draft,
                scrollController: scrollController,
                onChanged: () => setState(() {}),
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                  20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.lightBorder)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: canSave && !_isSaving ? _save : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    disabledBackgroundColor: AppTheme.lightBorder,
                    foregroundColor: Colors.white,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Save changes'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
