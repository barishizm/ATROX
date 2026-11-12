import { supabaseStore } from "../_shared/supabase-store.ts";
import { appleConfigFromEnv, revokeAppleTokens } from "./apple.ts";
import { createDeleteHandler } from "./handler.ts";

const apple = appleConfigFromEnv((name) => Deno.env.get(name));

Deno.serve(createDeleteHandler({
  store: supabaseStore(),
  revokeApple: apple ? (code) => revokeAppleTokens(code, apple) : undefined,
}));
