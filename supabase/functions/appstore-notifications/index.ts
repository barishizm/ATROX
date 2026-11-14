import { createClient } from "@supabase/supabase-js";
import { appStoreConfig } from "../_shared/appstore/entitlement.ts";
import { createJwsVerifier } from "../_shared/appstore/jws.ts";
import { rpcAppStoreStore } from "../_shared/appstore/rpc-store.ts";
import { createNotificationsHandler } from "./handler.ts";

const url = Deno.env.get("SUPABASE_URL");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
if (!url || !serviceKey) throw new Error("SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY missing");

const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });

// Apple calls this URL without a Supabase JWT (verify_jwt = false in config.toml); the signed payload is the proof.
Deno.serve(createNotificationsHandler({
  verifyJws: createJwsVerifier(),
  store: rpcAppStoreStore(admin),
  ...appStoreConfig((name) => Deno.env.get(name)),
}));
