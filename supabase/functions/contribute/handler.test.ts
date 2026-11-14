import { assert, assertEquals } from "../_shared/testing.ts";
import { type ContributionRow, createContributeHandler, parseContribution, parseKey } from "./handler.ts";

const NOW = Date.parse("2026-12-05T12:00:00Z");
const KEY = "0b6f1c1e-5d3a-4f7e-9a41-6c1d2e3f4a5b";
const good = {
  contribution_key: KEY, sex: "female", age_band: 30, bodyweight_kg: 64, height_band: 165, experience_band: "two_to_5_years",
  frequency_band: "3-4", month: "2026-11", model_version: "v1",
  lifts: [{ exercise_id: "barbell-bench-press", best_e1rm_kg: 62.54, best_set_reps: 5, sessions_in_month: 6 }],
};

function setup(hits = true) {
  const upserts: ContributionRow[][] = [];
  const removed: string[] = [];
  const hitCalls: unknown[][] = [];
  const handler = createContributeHandler({
    verify: (jwt) => Promise.resolve(jwt === "good" ? "user-secret-id" : null),
    hit: (...args) => {
      hitCalls.push(args);
      return Promise.resolve(hits);
    },
    store: {
      upsert: (rows) => {
        upserts.push(rows);
        return Promise.resolve();
      },
      remove: (key) => {
        removed.push(key);
        return Promise.resolve(3);
      },
    },
    now: () => NOW,
  });
  const call = (method: string, body: unknown, token = "good") =>
    handler(new Request("http://x/contribute", { method, headers: { Authorization: `Bearer ${token}` }, body: JSON.stringify(body) }));
  return { upserts, removed, hitCalls, call };
}

Deno.test("parseContribution flattens lifts and rounds e1RM to 0.1", () => {
  const rows = parseContribution(good, NOW);
  assert(rows);
  assertEquals(rows.length, 1);
  assertEquals(rows[0].best_e1rm_kg, 62.5);
  assertEquals(rows[0].month, "2026-11");
});

Deno.test("parseContribution rejects implausible or unbanded values", () => {
  const bad = (over: Record<string, unknown>) => parseContribution({ ...good, ...over }, NOW);
  assertEquals(bad({ age_band: 33 }), null);
  assertEquals(bad({ height_band: 167 }), null);
  assertEquals(bad({ bodyweight_kg: 20 }), null);
  assertEquals(bad({ bodyweight_kg: 64.5 }), null);
  assertEquals(bad({ sex: "unspecified" }), null);
  assertEquals(bad({ experience_band: "pro" }), null);
  assertEquals(bad({ frequency_band: "9" }), null);
  assertEquals(bad({ month: "2026-12" }), null, "the running month is not a finished month");
  assertEquals(bad({ month: "2020-01" }), null, "too old");
  assertEquals(bad({ lifts: [] }), null);
  assertEquals(bad({ user_id: "x" }), null, "unknown fields are refused");
  assertEquals(bad({ lifts: [{ ...good.lifts[0], best_e1rm_kg: 900 }] }), null);
  assertEquals(bad({ lifts: [{ ...good.lifts[0], best_set_reps: 0 }] }), null);
  assertEquals(bad({ lifts: [good.lifts[0], good.lifts[0]] }), null, "duplicate exercise");
  assertEquals(bad({ lifts: [{ ...good.lifts[0], exercise_id: "Bad Id" }] }), null);
  assertEquals(parseContribution("x", NOW), null);
});

Deno.test("parseKey accepts only a lone UUID", () => {
  assertEquals(parseKey({ contribution_key: KEY }), KEY);
  assertEquals(parseKey({ contribution_key: "nope" }), null);
  assertEquals(parseKey({ contribution_key: KEY, user_id: "x" }), null);
});

Deno.test("POST stores rows; the user id reaches only the rate limiter", async () => {
  const { upserts, hitCalls, call } = setup();
  const response = await call("POST", good);
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { stored: 1 });
  assertEquals(hitCalls.length, 1);
  assertEquals(hitCalls[0][0], "user-secret-id");
  assert(!JSON.stringify(upserts).includes("user-secret-id"), "no user id in what is written");
  assert(!JSON.stringify(upserts).includes("user_id"));
});

Deno.test("failures are logged without the user id or the payload", async () => {
  const messages: unknown[][] = [];
  const original = console.error;
  console.error = (...args: unknown[]) => void messages.push(args);
  try {
    const handler = createContributeHandler({
      verify: () => Promise.resolve("user-secret-id"),
      hit: () => Promise.resolve(true),
      store: { upsert: () => Promise.reject(new Error("db down")), remove: () => Promise.resolve(0) },
      now: () => NOW,
    });
    const response = await handler(new Request("http://x", { method: "POST", headers: { Authorization: "Bearer t" }, body: JSON.stringify(good) }));
    assertEquals(response.status, 500);
  } finally {
    console.error = original;
  }
  const logged = JSON.stringify(messages);
  assert(logged.includes("db down"));
  assert(!logged.includes("user-secret-id") && !logged.includes(KEY));
});

Deno.test("DELETE removes by key", async () => {
  const { removed, call } = setup();
  const response = await call("DELETE", { contribution_key: KEY });
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { deleted: 3 });
  assertEquals(removed, [KEY]);
});

Deno.test("auth, method, JSON and rate-limit errors", async () => {
  assertEquals((await setup().call("POST", good, "bad")).status, 401);
  assertEquals((await setup().call("POST", { ...good, age_band: 33 })).status, 400);
  assertEquals((await setup().call("DELETE", { nope: 1 })).status, 400);
  assertEquals((await setup(false).call("POST", good)).status, 429);
  assertEquals((await setup().call("GET", undefined)).status, 405);
});
