# Sign-out crash: blank white screen, `element._lifecycleState` assertion

Status: **write-up only** — no fix attempted yet. Filed while live-testing the
Settings → Users admin panel on `feature/admin-user-management`; unrelated to
that feature, tracked separately here so it doesn't block that branch's
merge. Fix work belongs on a new branch, `fix/sign-out-crash`, after that
merge lands.

## Repro steps

1. Sign in with a real (non-guest) account. Reproduced specifically while
   signed in as `super_admin`, sitting on Settings → **Users** (the
   admin-only panel), but nothing below points at that panel being required
   — see "Likely cause".
2. Open the profile menu / Settings and trigger **Sign Out** (the shared
   `confirmSignOut` flow — Settings' "Sign Out" row and the desktop/tablet
   profile panel's signed-in state both call it).
3. Confirm the "Are you sure you want to sign out?" dialog by tapping
   **Sign Out**.

Observed: the app goes to a blank white screen instead of landing back on
the signed-out state. Reproduced twice in a row in the same session,
back-to-back, with identical symptoms both times — this is not a one-off
flake. Recovery required a hard navigation/reload (`page.goto()` to a fresh
route, or a full reload); simply waiting or retrying in-place did not
recover. A `localStorage`/`sessionStorage` inspection after the crash showed
the old Supabase session key was still present — `auth.signOut()` never
actually completed, so the app was left in a half-signed-out state (crashed
mid-transition, not merely a UI glitch after a clean sign-out).

## The assertion

A Flutter framework-internal invariant failure on an `Element`'s lifecycle
state (`element._lifecycleState`) — Flutter's own "used a `BuildContext`/
`Element` that's no longer in the state it's needed to be in" family of
errors (`package:flutter/src/widgets/framework.dart`), not an application
exception. No copy of the literal stack trace text was saved from that
session — Flutter web's error overlay was only captured as a screenshot at
the time, not as console text — so the exact line number and full trace
still need to be captured fresh (see "Before fixing" below). The
characterization above (which `Element` field, which invariant) is
reconstructed from what was visible on screen at the time, not from a saved
log.

## Likely cause (code-inspection hypothesis, not yet confirmed live)

Two things line up in the code and are the most likely combination:

1. **`confirmSignOut`** (`lib/widgets/profile/confirm_sign_out.dart`) pops
   the confirmation dialog and then, in the same synchronous callback,
   clears three providers and fires off `AuthProvider.signOut()` —
   un-awaited:

   ```dart
   onPressed: () {
     Navigator.pop(context);
     context.read<BookingProvider>().clear();
     context.read<TripSetupProvider>().clear();
     context.read<SplitsProvider>().clear();
     context.read<AuthProvider>().signOut();
   },
   ```

2. **`AuthProvider.signOut()`** (`lib/providers/auth_provider.dart:290`)
   awaits `_supabase.auth.signOut()`, then sets `_user = null` and calls
   `notifyListeners()`. The app's `GoRouter` is created with
   `refreshListenable: authRefresh` (`AppRouter.create`, wired from
   `main.dart`), so that `notifyListeners()` call — arriving some
   microtask(s) after the button press, not necessarily aligned with any
   particular widget's own build/dispose cycle — forces the router to
   re-evaluate and rebuild the current route tree while whatever screen the
   sign-out was triggered from (the admin Users panel, the profile panel,
   Settings generally) is still mid-transition from the dialog having just
   closed. If any widget in that subtree is still holding a `BuildContext`
   across that gap — an in-flight `Future` (e.g. the Users panel's
   `admin_list_users` fetch), a listener callback, or a `GlobalKey`-identified
   element being torn down and reinserted in the same auth-driven rebuild —
   that's the shape of bug that produces exactly this class of assertion.

   Nothing here is `mounted`-guarded except the two `catch` blocks in
   `_NewUserDialogState._submit` (unrelated call path); `confirmSignOut`
   itself has no `context.mounted` checks between the dialog pop and the
   three provider reads plus `signOut()` call.

This is a plausible, code-grounded mechanism, not a confirmed root cause —
nothing here was verified with a debugger attached or a captured stack
trace pointing at a specific line.

## Proposed fix (not yet implemented)

- Before changing anything: reproduce with `flutter run -d chrome` (or
  attach DevTools to the deployed build) and capture the actual assertion
  text and full stack trace to text, to confirm or replace the hypothesis
  above with the real failing line.
- Await `AuthProvider.signOut()` in `confirmSignOut` instead of firing it
  and forgetting it, and check `context.mounted` before doing anything with
  `context` afterward.
- Capture the three providers (`BookingProvider`, `TripSetupProvider`,
  `SplitsProvider`) via `context.read<...>()` *before* `Navigator.pop`,
  rather than reading from `context` after the dialog closes and the
  underlying route may already be reacting to the auth-state change.
  `context.read` itself doesn't need a mounted context, but this removes
  any ordering ambiguity between the pop and the provider reads.
  Read the `AuthProvider` instance the same way and call `signOut()` on it
  directly, rather than chaining `context.read<AuthProvider>()` after the
  other three reads.
- Audit any admin-only or auth-conditional panel (the Users panel is the
  one that was open during the actual repro) for in-flight async work
  (fetches, subscriptions) that calls `setState` or touches `context`
  without an `if (!mounted) return;` guard — since a `refreshListenable`
  auth-driven rebuild can tear such a panel out of the tree at any time,
  not just on an explicit user navigation.
- Once the real assertion/stack trace is captured, re-evaluate whether the
  fix belongs in `confirmSignOut`, in `AuthProvider.signOut()`, in the
  affected panel(s), or in more than one of those places.
