import { supabaseStore } from "../_shared/supabase-store.ts";
import { createExportHandler } from "./handler.ts";

Deno.serve(createExportHandler({ store: supabaseStore() }));
