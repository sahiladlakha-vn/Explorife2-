import type { ReactNode } from "react";
import { signInAction } from "@/lib/auth/actions";
import type { OAuthProvider } from "@/lib/auth/actions";

/**
 * One `<form action={signInAction}>` per button rather than a shared client
 * component with an `onClick` — `signInWithProvider` (lib/auth/actions.ts)
 * is a Server Action that ends in `redirect()`, so a plain POST-and-redirect
 * form works with zero client JS, same as `signOutAction`'s form in
 * `app/auth/sign-out/page.tsx`.
 */
export function OAuthProviderButton({
  provider,
  redirectTo,
  direct = false,
  icon,
  label,
}: {
  provider: OAuthProvider;
  redirectTo: string;
  direct?: boolean;
  icon: ReactNode;
  label: string;
}) {
  return (
    <form action={signInAction}>
      <input type="hidden" name="provider" value={provider} />
      <input type="hidden" name="redirect" value={redirectTo} />
      {direct ? <input type="hidden" name="direct" value="true" /> : null}
      <button
        type="submit"
        className="bg-sheet-surface text-sheet-ink border-sheet-border flex h-12 w-full items-center justify-center gap-2.5 rounded-xl border text-sm font-semibold transition hover:opacity-90"
      >
        {icon}
        {label}
      </button>
    </form>
  );
}
