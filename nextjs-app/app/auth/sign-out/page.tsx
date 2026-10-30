import { Suspense } from "react";
import { SignOutPageBody } from "@/components/features/auth/SignOutPageBody";

/**
 * Static shell — the actual `searchParams`/session-dependent content lives
 * in `SignOutPageBody`, a separate Server Component, so this stays
 * prerenderable under Next's Cache Components. Same split as `AuthPage`.
 */
export default function SignOutPage({
  searchParams,
}: {
  searchParams: Promise<{ redirect?: string }>;
}) {
  return (
    <div className="flex flex-1 flex-col items-center justify-center px-6 py-12">
      <Suspense fallback={null}>
        <SignOutPageBody searchParams={searchParams} />
      </Suspense>
    </div>
  );
}
