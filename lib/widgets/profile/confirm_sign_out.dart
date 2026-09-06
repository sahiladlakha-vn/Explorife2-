import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/booking_provider.dart';
import '../../providers/splits_provider.dart';
import '../../providers/trip_setup_provider.dart';

/// Confirm-then-sign-out — shared between Settings' "Sign Out" row and the
/// desktop/tablet profile panel's signed-in state, so there's one sign-out
/// flow (including which providers get cleared) rather than two. Clears
/// Booking/TripSetup/Splits provider state before calling
/// AuthProvider.signOut() — those three cache trip-scoped data by nothing
/// but RLS + the live session, so a stale cache would otherwise leak into
/// whatever account signs in next on the same device.
void confirmSignOut(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: Colors.white,
      title: Text('Sign Out',
          style: GoogleFonts.bebasNeue(fontSize: 22, color: AppTheme.lightInk)),
      content: Text('Are you sure you want to sign out?',
          style: GoogleFonts.fredoka(color: AppTheme.lightMute)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            context.read<BookingProvider>().clear();
            context.read<TripSetupProvider>().clear();
            context.read<SplitsProvider>().clear();
            context.read<AuthProvider>().signOut();
          },
          child: const Text('Sign Out', style: TextStyle(color: Colors.red)),
        ),
      ],
    ),
  );
}
