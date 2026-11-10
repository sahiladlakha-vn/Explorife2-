import Link from "next/link";
import { redirect } from "next/navigation";
import { GitHubIcon, GoogleIcon } from "@/components/ui/icons";
import { OAuthProviderButton } from "./OAuthProviderButton";
import { getOptionalUser } from "@/lib/auth/permissions";
import { signOutAction } from "@/lib/auth/actions";
import { sanitizeRedirect } from "@/lib/auth/redirect";

/**
 * `searchParams`/`cookies()`-dependent part of `/auth/sign-out`, isolated
 * behind its own Server Component so `app/auth/sign-out/page.tsx` can stay a
 * static shell and wrap just this in `<Suspense>` — same reasoning as
 * `AuthPageBody`/`ProfileLayoutBody`.
 *
 * An anonymous/guest session has no account to come back to — signing out
 * permanently drops its data (see `signOutAction`'s own doc comment). This
 * component is the ONLY caller that's allowed to set `confirmed: true` on
 * that action, and only after showing the warning below; the plain "Cancel"
 * link and the "sign in to keep it" buttons are the two ways out that don't.
 *
 * `?redirect=` is where "Cancel" (and a real user's successful sign-in from
 * here, via the OAuth buttons) lands — NOT where sign-out itself redirects,
 * which `signOutAction` always hardcodes to `/`.
 */
export async function SignOutPageBody({
  searchParams,
}: {
  searchParams: Promise<{ redirect?: string }>;
}) {
  const { redirect: redirectParam } = await searchParams;
  const redirectTo = sanitizeRedirect(redirectParam);
  const user = await getOptionalUser();

  if (!user) {
    redirect(redirectTo);
  }

  if (user.is_anonymous) {
    return (
      <div className="w-full max-w-sm text-center">
        <h1 className="font-display text-ink text-4xl tracking-wide">
          Wait — you&apos;re a guest
        </h1>
        <p className="text-text-muted mt-3 text-sm">
          You&apos;re signed in as a guest. Signing out now will permanently delete your saved
          trips and gems — this can&apos;t be undone. Sign in to keep them instead.
        </p>

        <div className="mt-6 flex flex-col gap-3">
          <OAuthProviderButton
            provider="google"
            redirectTo={redirectTo}
            icon={<GoogleIcon className="h-5 w-5" />}
            label="Sign in with Google to keep it"
          />
          <OAuthProviderButton
            provider="github"
            redirectTo={redirectTo}
            icon={<GitHubIcon className="h-5 w-5" />}
            label="Sign in with GitHub to keep it"
          />
        </div>

        <form action={signOutAction} className="mt-6">
          <input type="hidden" name="confirmed" value="true" />
          <button type="submit" className="text-danger text-sm underline underline-offset-2">
            Sign out and permanently delete my data
          </button>
        </form>

        <Link
          href={redirectTo}
          className="text-text-muted mt-4 block text-sm underline underline-offset-2"
        >
          Cancel
        </Link>
      </div>
    );
  }

  return (
    <div className="w-full max-w-sm text-center">
      <h1 className="font-display text-ink text-4xl tracking-wide">Sign out?</h1>
      <p className="text-text-muted mt-3 text-sm">You can sign back in anytime.</p>

      <form action={signOutAction} className="mt-6">
        <button
          type="submit"
          className="bg-danger text-sheet-surface flex h-12 w-full items-center justify-center rounded-xl text-sm font-semibold"
        >
          Sign out
        </button>
      </form>

      <Link
        href={redirectTo}
        className="text-text-muted mt-4 block text-sm underline underline-offset-2"
      >
        Cancel
      </Link>
    </div>
  );
}
