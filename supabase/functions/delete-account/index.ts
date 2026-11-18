import { supabaseStore } from "../_shared/supabase-store.ts";
import { appleConfigFromEnv, revokeAppleTokens } from "./apple.ts";
import { createDeleteHandler } from "./handler.ts";

const apple = appleConfigFromEnv((name) => Deno.env.get(name));

// Recent sign-in required for deletion once the app can reauthenticate before calling (set the secret to e.g. 600).
const maxAge = Number(Deno.env.get("DELETE_MAX_SIGNIN_AGE_SECONDS"));

Deno.serve(createDeleteHandler({
  store: supabaseStore(),
  maxSignInAgeSeconds: Number.isFinite(maxAge) && maxAge > 0 ? maxAge : undefined,
  revokeApple: apple ? (code) => revokeAppleTokens(code, apple) : undefined,
}));
