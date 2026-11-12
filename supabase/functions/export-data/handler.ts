import { authenticate, json, type Row, USER_TABLES, type UserDataStore } from "../_shared/user-data.ts";

export interface ExportDeps {
  store: UserDataStore;
  now?: () => Date;
}

/**
 * export-data (P045): every row the user owns, as one JSON document. Weights are kg and lengths cm, as stored.
 * `{ format_version, exported_at, user_id, tables: { <table>: [rows] } }`
 */
export function createExportHandler({ store, now = () => new Date() }: ExportDeps) {
  return async (request: Request): Promise<Response> => {
    const userId = await authenticate(request, store);
    if (userId instanceof Response) return userId;
    try {
      const tables: Record<string, Row[]> = {};
      for (const table of USER_TABLES) tables[table] = await store.rows(table, userId);
      const body = { format_version: 1, exported_at: now().toISOString(), user_id: userId, tables };
      return new Response(JSON.stringify(body, null, 2), {
        status: 200,
        headers: {
          "Content-Type": "application/json; charset=utf-8",
          "Content-Disposition": `attachment; filename="atrox-export-${body.exported_at.slice(0, 10)}.json"`,
        },
      });
    } catch (error) {
      console.error("export-data failed", error instanceof Error ? error.message : error);
      return json({ error: "export_failed" }, 500);
    }
  };
}
