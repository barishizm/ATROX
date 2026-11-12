import { assert, assertEquals, FakeStore, post } from "../_shared/testing.ts";
import { USER_TABLES } from "../_shared/user-data.ts";
import { createExportHandler } from "./handler.ts";

const A = "00000000-0000-0000-0000-0000000000a1";
const B = "00000000-0000-0000-0000-0000000000b2";

function store() {
  const fake = new FakeStore({ "token-a": A, "token-b": B });
  fake.add("profiles", { id: "p1", user_id: A, height_cm: 180 });
  fake.add("workouts", { id: "w1", user_id: A, deleted_at: null });
  fake.add("workouts", { id: "w2", user_id: A, deleted_at: "2026-11-01T00:00:00Z" });
  fake.add("sets", { id: "s1", user_id: A, weight_kg: 100, reps: 5 });
  fake.add("workouts", { id: "w9", user_id: B });
  return fake;
}

Deno.test("export-data returns valid JSON with every table of the caller only", async () => {
  const handler = createExportHandler({ store: store(), now: () => new Date("2026-11-13T09:00:00Z") });
  const response = await handler(post("export-data", "token-a"));

  assertEquals(response.status, 200);
  assert(response.headers.get("Content-Type")?.startsWith("application/json"));
  assertEquals(response.headers.get("Content-Disposition"), 'attachment; filename="atrox-export-2026-11-13.json"');
  const body = JSON.parse(await response.text());
  assertEquals(body.format_version, 1);
  assertEquals(body.user_id, A);
  assertEquals(body.exported_at, "2026-11-13T09:00:00.000Z");
  assertEquals(Object.keys(body.tables), [...USER_TABLES]);
  assertEquals(body.tables.workouts.map((row: { id: string }) => row.id), ["w1", "w2"]);
  assertEquals(body.tables.sets[0].weight_kg, 100);
  assertEquals(body.tables.consents, []);
});

Deno.test("export-data refuses missing or invalid tokens and non-POST", async () => {
  const handler = createExportHandler({ store: store() });
  assertEquals((await handler(post("export-data"))).status, 401);
  assertEquals((await handler(post("export-data", "forged"))).status, 401);
  assertEquals((await handler(new Request("http://localhost/export-data", { method: "GET" }))).status, 405);
});

Deno.test("export-data reports a store failure as 500 without details", async () => {
  const fake = store();
  fake.failOn = "sets";
  const response = await createExportHandler({ store: fake })(post("export-data", "token-a"));
  assertEquals(response.status, 500);
  assertEquals(await response.json(), { error: "export_failed" });
});
