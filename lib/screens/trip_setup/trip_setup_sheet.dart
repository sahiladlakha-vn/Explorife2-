import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/trip_provider.dart';
import 'step_one_init.dart';
import 'step_who_is_coming.dart';
import 'step_two_template.dart';

/// Modal bottom sheet host for Trip Setup. Owns the [TripDraft] and the step
/// index; Steps 1 & 2 are presentational and receive the draft + callbacks.
/// Light colorway, matching Profile — this used to intentionally shift dark
/// ("entering planning mode"), reversed per product decision so trip
/// creation reads as a continuation of Profile instead of a mode jump.
///
/// Header/handle dims match the app's canonical sheet (drop_gem_sheet):
/// 28px top radius, centered 44×5 handle, boxed 44×44 close button.
class TripSetupSheet extends StatefulWidget {
  const TripSetupSheet({
    super.key,
    this.initialLocation,
    this.initialLat,
    this.initialLng,
  });

  /// Pre-fills Step 1's "Where to?" field — e.g. Destination Detail's own
  /// "+ Plan a trip" button carrying its city straight into trip creation.
  /// Implements the `/trips/new` route's own `?location=` param (see
  /// trip_routes.dart); null for every other, still-blank entry point.
  final String? initialLocation;
  final double? initialLat;
  final double? initialLng;

  @override
  State<TripSetupSheet> createState() => _TripSetupSheetState();
}

class _TripSetupSheetState extends State<TripSetupSheet> {
  late final TripDraft _draft = TripDraft()
    ..location = widget.initialLocation
    ..locationLat = widget.initialLat
    ..locationLng = widget.initialLng;
  int _step = 0; // 0 = init, 1 = who's coming, 2 = template
  bool _isCreating = false;

  void _onContinue() => setState(() => _step++);
  void _onBack() => setState(() => _step--);

  Future<void> _onComplete() async {
    final router = GoRouter.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context); // TODO(snackbar): sheet context may not reach app-level ScaffoldMessenger; thread scaffoldMessengerKey from MaterialApp if this still swallows errors
    setState(() => _isCreating = true);
    try {
      // createTrip seeds from the blueprint internally (see TripProvider) —
      // do NOT call seedFromBlueprint again here, that would double-insert.
      final trip = await context.read<TripProvider>().createTrip(_draft);
      if (!mounted) return;
      navigator.pop();
      router.push('/trips/${trip.id}/builder');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCreating = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Could not create trip: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<TripProvider>();
    final canAdvance = switch (_step) {
      0 => StepOneInit.isValid(_draft),
      1 => StepWhoIsComing.isValid(_draft),
      _ => StepTwoTemplate.isValid(_draft),
    };

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
            _header(context),
            const Divider(height: 1, color: AppTheme.lightBorder),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: switch (_step) {
                  0 => StepOneInit(
                      key: const ValueKey('step1'),
                      draft: _draft,
                      scrollController: scrollController,
                      onChanged: () => setState(() {}),
                    ),
                  1 => StepWhoIsComing(
                      key: const ValueKey('step2'),
                      draft: _draft,
                      scrollController: scrollController,
                      onChanged: () => setState(() {}),
                    ),
                  _ => StepTwoTemplate(
                      key: const ValueKey('step3'),
                      draft: _draft,
                      blueprints:
                          provider.blueprintsFor(_draft.location ?? ''),
                      isLoading: provider.isLoading,
                      scrollController: scrollController,
                      onChanged: () => setState(() {}),
                    ),
                },
              ),
            ),
            _Footer(
              step: _step,
              lastStep: 2,
              canAdvance: canAdvance,
              isCreating: _isCreating,
              onBack: _onBack,
              onContinue: _onContinue,
              onComplete: _onComplete,
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              'Step ${_step + 1} of 3',
              style: const TextStyle(
                color: AppTheme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
          GestureDetector(
            // Every entry point pushes this sheet (see trip_routes.dart), so
            // there's always a route to pop back to — canPop() is a defensive
            // fallback matching the house pattern (see placement_screen.dart)
            // in case a future call site reaches here via go() instead.
            onTap: () =>
                context.canPop() ? context.pop() : context.go('/profile'),
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
    );
  }
}

/// Sticky bottom bar: optional Back, progress dots, primary action.
class _Footer extends StatelessWidget {
  const _Footer({
    required this.step,
    required this.lastStep,
    required this.canAdvance,
    required this.isCreating,
    required this.onBack,
    required this.onContinue,
    required this.onComplete,
  });

  final int step;
  final int lastStep;
  final bool canAdvance;
  final bool isCreating;
  final VoidCallback onBack;
  final VoidCallback onContinue;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final isLast = step == lastStep;
    final onPrimary = isLast
        ? (canAdvance && !isCreating ? onComplete : null)
        : (canAdvance ? onContinue : null);

    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.lightBorder)),
      ),
      child: Row(
        children: [
          if (step > 0)
            TextButton(
              onPressed: isCreating ? null : onBack,
              child: const Text('Back', style: TextStyle(color: AppTheme.lightMute)),
            ),
          Expanded(
            child: Center(child: _Dots(active: step, count: lastStep + 1)),
          ),
          SizedBox(
            width: 150,
            child: ElevatedButton(
              onPressed: onPrimary,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                disabledBackgroundColor: AppTheme.lightBorder,
                foregroundColor: Colors.white,
              ),
              child: isCreating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(isLast ? 'Open builder' : 'Continue'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.active, required this.count});
  final int active;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final on = i == active;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: on ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: on ? AppTheme.primary : AppTheme.lightBorder,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
