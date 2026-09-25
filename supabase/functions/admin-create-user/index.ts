// Backs the Settings -> Users page's "New User" button and "Resend invite"
// row action. Runs with the service-role key so it can call the Supabase
// Auth Admin API (inviteUserByEmail / getUserById / deleteUser) — that key
// is read only from this function's own environment (Supabase injects
// SUPABASE_SERVICE_ROLE_KEY automatically) and never touches the Flutter
// app or the repo.
//
// Two separate Supabase clients, deliberately never mixed:
//   - serviceClient: service-role key. Used ONLY for the Auth Admin API
//     calls below (invite / lookup / delete). auth.uid() is null under this
//     client, so it must never be the one calling admin_create_user_profile
//     or admin_log_resend_invite — the DB's own lock_profile_role_field
//     trigger and is_super_admin() checks need a real caller identity.
//   - callerClient: the incoming request's own JWT (the real Super Admin's
//     session), forwarded via the Authorization header. Used for every
//     Postgres RPC call and the up-front role check, so auth.uid(),
//     is_super_admin(), the lock trigger, and the audit log's actor_id all
//     see the real acting admin.
import { createClient } from "jsr:@supabase/supabase-js@2";

const ALLOWED_ROLES = [
  "traveler",
  "guide",
  "business_owner",
  "content_moderator",
  "regional_admin",
  "super_admin",
  "finance_admin",
];

const USERNAME_FORMAT = /^[a-z0-9_]{3,20}$/;
const EMAIL_FORMAT = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

// Reuses the app's existing OAuth redirect route (auth_provider.dart's
// `_webRedirectTo`) rather than inventing a new URL — that route is already
// registered with GoRouter and already in the project's Auth redirect
// allowlist, and its screen already branches on a landed session vs. an
// `?error=` query string, which is exactly what an accepted invite link
// produces on success/failure.
const APP_ORIGIN = Deno.env.get("APP_URL") ?? "https://explorife2.vercel.app";
const INVITE_REDIRECT_TO = `${APP_ORIGIN}/#/auth/callback`;

function cors(resp: Response) {
  resp.headers.set("Access-Control-Allow-Origin", "*");
  resp.headers.set(
    "Access-Control-Allow-Headers",
    "authorization, x-client-info, apikey, content-type",
  );
  resp.headers.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  return resp;
}

function json(body: unknown, status = 200) {
  return cors(
    new Response(JSON.stringify(body), {
      status,
      headers: { "Content-Type": "application/json" },
    }),
  );
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return cors(new Response(null, { status: 204 }));
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "unauthorized: missing Authorization header" }, 401);
  }

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

  const callerClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });

  const serviceClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  });

  const { data: userData, error: userErr } = await callerClient.auth.getUser();
  if (userErr || !userData?.user) {
    return json({ error: "unauthorized: invalid session" }, 401);
  }

  // Fast, friendly pre-check — is_super_admin() inside the SQL functions
  // called below is the real, authoritative gate (a Supabase RLS/RPC call
  // always re-verifies server-side regardless of what this function already
  // checked, same convention as every other admin RPC in this app). This
  // just avoids sending an invite email, or attempting a resend, before
  // failing on a non-admin caller.
  const { data: profile, error: profileErr } = await callerClient
    .from("profiles")
    .select("role")
    .eq("id", userData.user.id)
    .maybeSingle();
  if (profileErr || profile?.role !== "super_admin") {
    return json({ error: "forbidden: only a super_admin may manage users" }, 403);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid JSON body" }, 400);
  }

  if (body.action === "resend_invite") {
    return handleResendInvite(body, callerClient, serviceClient);
  }
  return handleCreateUser(body, callerClient, serviceClient);
});

async function handleCreateUser(
  body: Record<string, unknown>,
  // deno-lint-ignore no-explicit-any
  callerClient: any,
  // deno-lint-ignore no-explicit-any
  serviceClient: any,
) {
  const fullName = String(body.full_name ?? "").trim();
  const email = String(body.email ?? "").trim().toLowerCase();
  const usernameInput = body.username
    ? String(body.username).trim().toLowerCase()
    : null;
  const role = String(body.role ?? "traveler");

  if (!fullName) return json({ error: "Full name is required." }, 400);
  if (!EMAIL_FORMAT.test(email)) {
    return json({ error: "That doesn't look like a valid email address." }, 400);
  }
  if (!ALLOWED_ROLES.includes(role)) return json({ error: "Unknown role." }, 400);
  if (usernameInput && !USERNAME_FORMAT.test(usernameInput)) {
    return json(
      { error: "Usernames are 3-20 lowercase letters, numbers, or underscores." },
      400,
    );
  }

  // Check the username before sending anything, so an admin doesn't get a
  // real invite email fired off only to have it deleted a moment later for
  // a taken username. This is still just the fast path — a race against a
  // concurrent invite is still possible, which is exactly what
  // admin_create_user_profile's own catch-and-retry / unique-violation
  // handling (and the delete-on-failure rollback below) are the real,
  // authoritative guard against.
  if (usernameInput) {
    const { data: existing, error: lookupErr } = await callerClient
      .from("profiles")
      .select("id")
      .eq("username", usernameInput)
      .maybeSingle();
    if (lookupErr) {
      return json({ error: `Could not validate the username: ${lookupErr.message}` }, 500);
    }
    if (existing) {
      return json({ error: "That username is already taken." }, 409);
    }
  }

  const { data: invited, error: inviteErr } = await serviceClient.auth.admin
    .inviteUserByEmail(email, {
      data: { full_name: fullName },
      redirectTo: INVITE_REDIRECT_TO,
    });

  if (inviteErr || !invited?.user) {
    // Supabase's own error code, not a message-text guess — GoTrue returns
    // `email_exists` for "there's already an account with this email."
    if (inviteErr?.code === "email_exists") {
      return json({ error: "That email already has an account." }, 409);
    }
    return json({ error: inviteErr?.message ?? "Could not send the invite." }, 500);
  }

  const newUserId = invited.user.id;

  const { data: profileRow, error: rpcErr } = await callerClient.rpc(
    "admin_create_user_profile",
    {
      p_user_id: newUserId,
      p_full_name: fullName,
      p_username: usernameInput,
      p_role: role,
    },
  );

  if (rpcErr) {
    // No half-created accounts: the invite went out but the profile step
    // failed (e.g. a last-moment race on the username), so undo the auth
    // user entirely rather than leaving an invite email pointing at a dead
    // account.
    await serviceClient.auth.admin.deleteUser(newUserId);
    const msg = rpcErr.message ?? "";
    if (msg.includes("username_taken")) {
      return json({ error: "That username is already taken." }, 409);
    }
    if (msg.includes("username_invalid")) {
      return json(
        { error: "Usernames are 3-20 lowercase letters, numbers, or underscores." },
        400,
      );
    }
    if (msg.includes("insufficient_privilege")) {
      return json({ error: "Only a super_admin may create a user." }, 403);
    }
    return json({ error: `Could not finish creating the user: ${msg}` }, 500);
  }

  return json({ user: profileRow }, 200);
}

async function handleResendInvite(
  body: Record<string, unknown>,
  // deno-lint-ignore no-explicit-any
  callerClient: any,
  // deno-lint-ignore no-explicit-any
  serviceClient: any,
) {
  const targetId = String(body.user_id ?? "");
  if (!targetId) return json({ error: "user_id is required." }, 400);

  // Email is never accepted from the client — looked up server-side so a
  // caller can't redirect the resend to an address they don't control.
  const { data: targetUser, error: lookupErr } = await serviceClient.auth.admin
    .getUserById(targetId);
  if (lookupErr || !targetUser?.user) {
    return json({ error: "User not found." }, 404);
  }

  const { invited_at, email_confirmed_at, email } = targetUser.user;
  if (!invited_at || email_confirmed_at) {
    return json({ error: "This user has already signed in; nothing to resend." }, 409);
  }
  if (!email) {
    return json({ error: "This user has no email on file." }, 409);
  }

  const { error: inviteErr } = await serviceClient.auth.admin.inviteUserByEmail(
    email,
    { redirectTo: INVITE_REDIRECT_TO },
  );
  if (inviteErr) {
    return json({ error: inviteErr.message ?? "Could not resend the invite." }, 500);
  }

  // Best-effort audit row — the resend itself already succeeded above, so a
  // logging failure here isn't reported to the caller as a failed resend;
  // it's still surfaced via this function's own logs, and
  // admin_log_resend_invite re-checks pending status independently anyway.
  const { error: logErr } = await callerClient.rpc("admin_log_resend_invite", {
    p_target_id: targetId,
  });
  if (logErr) console.error("admin_log_resend_invite failed:", logErr.message);

  return json({ ok: true }, 200);
}
