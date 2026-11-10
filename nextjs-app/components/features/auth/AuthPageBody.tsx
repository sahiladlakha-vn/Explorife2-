import Link from "next/link";
import type { ReactNode } from "react";
import { GitHubIcon, GoogleIcon } from "@/components/ui/icons";
import { OAuthProviderButton } from "./OAuthProviderButton";
import { friendlyAuthErrorMessage, IDENTITY_ALREADY_EXISTS } from "@/lib/auth/errors";
import { sanitizeRedirect } from "@/lib/auth/redirect";
import type { OAuthProvider } from "@/lib/auth/actions";

function isOAuthProvider(value: string | undefined): value is OAuthProvider {
  return value === "google" || value === "github";
}

const PROVIDER_LABEL: Record<OAuthProvider, string> = {
  google: "Google",
  github: "GitHub",
};

const PROVIDER_ICON: Record<OAuthProvider, ReactNode> = {
  google: <GoogleIcon className="h-5 w-5" />,
  github: <GitHubIcon className="h-5 w-5" />,
};

/**
 * `searchParams`-dependent part of `/auth`, isolated behind its own Server
 * Component so `app/auth/page.tsx` can stay a static shell and wrap just
 * this in `<Suspense>` — same reasoning as `ProfileLayoutBody`/
 * `TripLayoutBody` (Next's Cache Components otherwise refuses to prerender
 * any of the static chrome around a `searchParams` read).
 *
 * `?redirect=` carries the post-login destination (sanitized below — it's
 * attacker-controlled, see lib/auth/redirect.ts). `?error=`/`?provider=` are
 * OUR OWN params round-tripped through `/auth/callback` (see
 * lib/auth/actions.ts's `callbackUrl` doc comment) — never GoTrue's raw
 * `error_description`, which is deliberately never read or rendered here
 * (see lib/auth/errors.ts).
 */
export async function AuthPageBody({
  searchParams,
}: {
  searchParams: Promise<{ redirect?: string; error?: string; provider?: string }>;
}) {
  const params = await searchParams;
  const redirectTo = sanitizeRedirect(params.redirect);
  const conflictProvider = isOAuthProvider(params.provider) ? params.provider : null;
  const isIdentityConflict = params.error === IDENTITY_ALREADY_EXISTS && conflictProvider !== null;
  const errorMessage = params.error ? friendlyAuthErrorMessage(params.error) : null;

  return (
    <>
      {errorMessage ? (
        <div
          role="alert"
          className="border-danger/25 bg-danger/10 text-danger mt-6 rounded-xl border p-3 text-center text-sm"
        >
          {errorMessage}
        </div>
      ) : null}

      <div className="mt-6 flex flex-col gap-3">
        {isIdentityConflict && conflictProvider ? (
          <>
            <OAuthProviderButton
              provider={conflictProvider}
              redirectTo={redirectTo}
              direct
              icon={PROVIDER_ICON[conflictProvider]}
              label={`Sign in with this ${PROVIDER_LABEL[conflictProvider]} account`}
            />
            <Link
              href={`/auth?redirect=${encodeURIComponent(redirectTo)}`}
              className="text-text-muted text-center text-sm underline underline-offset-2"
            >
              Use a different account
            </Link>
          </>
        ) : (
          <>
            <OAuthProviderButton
              provider="google"
              redirectTo={redirectTo}
              icon={PROVIDER_ICON.google}
              label="Continue with Google"
            />
            <OAuthProviderButton
              provider="github"
              redirectTo={redirectTo}
              icon={PROVIDER_ICON.github}
              label="Continue with GitHub"
            />
          </>
        )}
      </div>
    </>
  );
}
