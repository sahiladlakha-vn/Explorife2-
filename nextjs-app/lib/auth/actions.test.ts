import { describe, expect, it, vi, beforeEach } from "vitest";

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(),
}));

class RedirectSignal extends Error {
  constructor(public url: string) {
    super(`NEXT_REDIRECT:${url}`);
  }
}

vi.mock("next/navigation", () => ({
  redirect: vi.fn((url: string) => {
    throw new RedirectSignal(url);
  }),
}));

import { createClient } from "@/lib/supabase/server";
import { redirect } from "next/navigation";
import { signInWithProvider, signInAction, signOutAction } from "./actions";

type MockUser = { id: string; is_anonymous: boolean } | null;

function mockAuthClient(options: {
  user: MockUser;
  linkIdentity?: ReturnType<typeof vi.fn>;
  signInWithOAuth?: ReturnType<typeof vi.fn>;
  signOut?: ReturnType<typeof vi.fn>;
}) {
  const client = {
    auth: {
      getUser: vi.fn().mockResolvedValue({ data: { user: options.user } }),
      linkIdentity:
        options.linkIdentity ??
        vi.fn().mockRejectedValue(new Error("linkIdentity() not expected to be called")),
      signInWithOAuth:
        options.signInWithOAuth ??
        vi.fn().mockRejectedValue(new Error("signInWithOAuth() not expected to be called")),
      signOut: options.signOut ?? vi.fn().mockResolvedValue({ error: null }),
    },
  };
  // eslint-disable-next-line @typescript-eslint/no-explicit-any -- partial Supabase client stub
  vi.mocked(createClient).mockResolvedValue(client as any);
  return client;
}

function formData(entries: Record<string, string>): FormData {
  const fd = new FormData();
  for (const [key, value] of Object.entries(entries)) fd.set(key, value);
  return fd;
}

beforeEach(() => {
  vi.clearAllMocks();
});

describe("signInWithProvider", () => {
  it("plain signInWithOAuth for an unauthenticated visitor", async () => {
    const signInWithOAuth = vi.fn().mockResolvedValue({
      data: { url: "https://accounts.google.com/o/oauth2/auth?..." },
      error: null,
    });
    mockAuthClient({ user: null, signInWithOAuth });

    await expect(signInWithProvider("google", "/profile/overview")).rejects.toThrow(
      RedirectSignal,
    );

    expect(signInWithOAuth).toHaveBeenCalledWith(
      expect.objectContaining({ provider: "google" }),
    );
    expect(redirect).toHaveBeenCalledWith("https://accounts.google.com/o/oauth2/auth?...");
  });

  it("links identity for a guest session (preserves auth.uid())", async () => {
    const linkIdentity = vi.fn().mockResolvedValue({
      data: { url: "https://accounts.google.com/link?..." },
      error: null,
    });
    mockAuthClient({ user: { id: "guest-1", is_anonymous: true }, linkIdentity });

    await expect(signInWithProvider("google", "/profile/overview")).rejects.toThrow(
      RedirectSignal,
    );

    expect(linkIdentity).toHaveBeenCalledWith(expect.objectContaining({ provider: "google" }));
    expect(redirect).toHaveBeenCalledWith("https://accounts.google.com/link?...");
  });

  it("bypasses linking for direct=true even when the session is a guest", async () => {
    const signInWithOAuth = vi.fn().mockResolvedValue({
      data: { url: "https://github.com/login/oauth/authorize?..." },
      error: null,
    });
    const linkIdentity = vi.fn();
    mockAuthClient({
      user: { id: "guest-1", is_anonymous: true },
      signInWithOAuth,
      linkIdentity,
    });

    await expect(
      signInWithProvider("github", "/profile/overview", true),
    ).rejects.toThrow(RedirectSignal);

    expect(signInWithOAuth).toHaveBeenCalled();
    expect(linkIdentity).not.toHaveBeenCalled();
  });

  it("plain signInWithOAuth for an already-real session", async () => {
    const signInWithOAuth = vi.fn().mockResolvedValue({
      data: { url: "https://github.com/login/oauth/authorize?..." },
      error: null,
    });
    mockAuthClient({ user: { id: "real-1", is_anonymous: false }, signInWithOAuth });

    await expect(signInWithProvider("github", "/profile/overview")).rejects.toThrow(
      RedirectSignal,
    );
    expect(signInWithOAuth).toHaveBeenCalled();
  });

  it("redirects to /auth with an error when the provider call fails", async () => {
    const signInWithOAuth = vi.fn().mockResolvedValue({
      data: null,
      error: { message: "boom" },
    });
    mockAuthClient({ user: null, signInWithOAuth });

    await expect(signInWithProvider("google", "/profile/overview")).rejects.toThrow(
      RedirectSignal,
    );
    expect(redirect).toHaveBeenCalledWith(
      expect.stringMatching(/^\/auth\?redirect=.*&error=server_error$/),
    );
  });
});

describe("signInAction (FormData adapter)", () => {
  it("rejects an unsupported provider value without calling Supabase", async () => {
    mockAuthClient({ user: null });

    await expect(
      signInAction(formData({ provider: "facebook", redirect: "/profile/overview" })),
    ).rejects.toThrow(RedirectSignal);
    expect(redirect).toHaveBeenCalledWith(expect.stringContaining("/auth?"));
  });

  it("starts a plain sign-in for a valid provider", async () => {
    const signInWithOAuth = vi.fn().mockResolvedValue({
      data: { url: "https://accounts.google.com/o/oauth2/auth?..." },
      error: null,
    });
    mockAuthClient({ user: null, signInWithOAuth });

    await expect(
      signInAction(formData({ provider: "google", redirect: "/profile/overview" })),
    ).rejects.toThrow(RedirectSignal);
    expect(signInWithOAuth).toHaveBeenCalled();
  });
});

describe("signOutAction", () => {
  it("throws without signing out an unconfirmed guest", async () => {
    const signOut = vi.fn();
    mockAuthClient({ user: { id: "guest-1", is_anonymous: true }, signOut });

    await expect(signOutAction(formData({ confirmed: "false" }))).rejects.toThrow(
      /requires confirmation/i,
    );
    expect(signOut).not.toHaveBeenCalled();
  });

  it("signs out a confirmed guest and redirects home", async () => {
    const signOut = vi.fn().mockResolvedValue({ error: null });
    mockAuthClient({ user: { id: "guest-1", is_anonymous: true }, signOut });

    await expect(signOutAction(formData({ confirmed: "true" }))).rejects.toThrow(RedirectSignal);
    expect(signOut).toHaveBeenCalledTimes(1);
    expect(redirect).toHaveBeenCalledWith("/");
  });

  it("signs out a real user without requiring confirmation", async () => {
    const signOut = vi.fn().mockResolvedValue({ error: null });
    mockAuthClient({ user: { id: "real-1", is_anonymous: false }, signOut });

    await expect(signOutAction(formData({}))).rejects.toThrow(RedirectSignal);
    expect(signOut).toHaveBeenCalledTimes(1);
    expect(redirect).toHaveBeenCalledWith("/");
  });
});
