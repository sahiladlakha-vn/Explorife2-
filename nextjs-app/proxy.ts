import { type NextRequest } from "next/server";
import { updateSession } from "@/lib/supabase/middleware";

// Next.js 16 renamed the `middleware.ts` convention to `proxy.ts` (same
// functionality, new file/export name) — see
// https://nextjs.org/docs/messages/middleware-to-proxy. The helper itself
// stays in lib/supabase/middleware.ts; only this top-level file convention
// changed.
export async function proxy(request: NextRequest) {
  return await updateSession(request);
}

export const config = {
  matcher: [
    /*
     * Match all request paths except static assets and image optimization
     * files, so Auth session refresh runs on page/Server Action traffic
     * without doing unnecessary work on every asset request.
     */
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
