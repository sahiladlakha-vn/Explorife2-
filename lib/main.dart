import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'models/gem.dart';
import 'providers/auth_provider.dart';
import 'providers/booking_provider.dart';
import 'providers/destination_provider.dart';
import 'providers/gem_provider.dart';
import 'providers/story_provider.dart';
import 'providers/hike_provider.dart';
import 'providers/splits_provider.dart';
import 'providers/trip_provider.dart';
import 'providers/trip_setup_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_ANON_KEY']!,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  runApp(const ExplorIfeApp());
}

class ExplorIfeApp extends StatefulWidget {
  const ExplorIfeApp({super.key});

  @override
  State<ExplorIfeApp> createState() => _ExplorIfeAppState();
}

class _ExplorIfeAppState extends State<ExplorIfeApp> {
  // Auth is the router's redirect source, so it must be the same instance the
  // router listens to via refreshListenable. Held here (not created inline in
  // the provider list) so both the provider tree and the router share it.
  final AuthProvider _auth = AuthProvider();
  late final GoRouter _router = AppRouter.create(_auth);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: _auth),
        ChangeNotifierProvider(create: (_) => DestinationProvider()),
        ChangeNotifierProvider(create: (_) => GemProvider()),
        ChangeNotifierProvider(create: (_) => StoryProvider()),
        ChangeNotifierProvider(create: (_) => HikeProvider()),
        ChangeNotifierProvider(create: (_) => SplitsProvider()),
        // Plain provider (no proxy): reads are scoped by trip_id and enforced by
        // RLS, so it needs no userId/AuthProvider. clear() is called at sign-out.
        ChangeNotifierProvider(
          create: (_) => BookingProvider(supabase: Supabase.instance.client),
        ),
        // Same shape as BookingProvider, same reasoning: trip_documents /
        // trip_packing_items RLS scopes reads by trip_id, no userId needed here.
        ChangeNotifierProvider(
          create: (_) => TripSetupProvider(supabase: Supabase.instance.client),
        ),
        // TripProvider depends on two others: the signed-in user's id (Auth) and
        // a gem-category lookup (Gem) for budget bucketing. A proxy provider
        // wires those in. Its category callback closes over the *live* GemProvider
        // so it always reads the current catalogue.
        ChangeNotifierProxyProvider2<AuthProvider, GemProvider, TripProvider>(
          create: (_) => TripProvider(
            supabase: Supabase.instance.client,
            userId: '',
            gemCategoryLookup: (_) => null,
          ),
          update: (_, auth, gems, previous) {
            final uid = auth.user?.id ?? '';
            // Reuse the existing instance only while the owner id is unchanged.
            // `create` seeds `previous` with userId '' (auth still loading), so a
            // plain `previous ??` would pin that empty-userId instance forever and
            // never pick up the resolved id — the query would fire `owner_id=eq.`
            // (empty) and 400. Rebuilding on change makes sign-in (and sign-out,
            // and account switching) reinitialise cleanly with the right owner.
            if (previous != null && previous.userId == uid) return previous;
            final provider = TripProvider(
              supabase: Supabase.instance.client,
              userId: uid,
              gemCategoryLookup: (id) => gems.allGems
                  .cast<Gem?>()
                  .firstWhere((g) => g?.id == id, orElse: () => null)
                  ?.category,
            );
            // Kick the load off right here, the moment a real uid appears —
            // don't rely on some downstream screen's one-shot mount hook to
            // catch it. ProfileScreen's own `trips.init()` call (guarded by
            // isEmpty/isLoading) becomes a no-op no-time-lost fallback rather
            // than the sole trigger, closing the race where auth resolves
            // after that screen's first frame has already fired its
            // now-too-early init() against the previous, empty-userId instance.
            if (uid.isNotEmpty) provider.init();
            return provider;
          },
        ),
      ],
      child: MaterialApp.router(
        title: 'ExplorIfe',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        routerConfig: _router,
      ),
    );
  }
}
