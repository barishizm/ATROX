import { assert, assertEquals } from "../_shared/testing.ts";
import { check, createPublishHandler, type PublishFacts, type PublishService, parseRequest } from "./handler.ts";

const NOW = Date.parse("2026-11-16T12:00:00Z");
const facts = (over: Partial<PublishFacts> = {}): PublishFacts => ({
  has_profile: true, share_score: true, last_score: null, last_provisional: false, last_at: null,
  workouts_7d: 3, completed_sets: 40, ...over,
});

function setup(f: PublishFacts, hits = true) {
  const published: unknown[][] = [];
  const service: PublishService = {
    facts: () => Promise.resolve(f),
    hit: () => Promise.resolve(hits),
    publish: (...args) => {
      published.push(args);
      return Promise.resolve();
    },
  };
  const handler = createPublishHandler({ verify: (jwt) => Promise.resolve(jwt === "good" ? "u1" : null), service, now: () => NOW });
  const call = (body: unknown, token = "good") =>
    handler(new Request("http://x/publish-score", {
      method: "POST", headers: { Authorization: `Bearer ${token}` }, body: JSON.stringify(body),
    }));
  return { published, call };
}

const ok = { overall_score: 60, provisional: false, weekly_workouts: 3 };

Deno.test("parseRequest enforces 1-99 and integer fields", () => {
  assertEquals(parseRequest(ok), ok);
  assertEquals(parseRequest({ ...ok, overall_score: 0 }), null);
  assertEquals(parseRequest({ ...ok, overall_score: 100 }), null);
  assertEquals(parseRequest({ ...ok, overall_score: 60.5 }), null);
  assertEquals(parseRequest({ ...ok, weekly_workouts: -1 }), null);
  assertEquals(parseRequest({ ...ok, extra: 1 }), null);
  assertEquals(parseRequest("x"), null);
});

Deno.test("check: accepts a plausible score", () => {
  assertEquals(check(ok, facts(), NOW), null);
});

Deno.test("check: a big jump within a day is rejected, a small one is not", () => {
  const recent = new Date(NOW - 3_600_000).toISOString();
  assertEquals(check({ ...ok, overall_score: 80 }, facts({ last_score: 55, last_at: recent }), NOW), "score_jump");
  assertEquals(check({ ...ok, overall_score: 62 }, facts({ last_score: 55, last_at: recent }), NOW), null);
});

Deno.test("check: a jump after a day, or from a provisional score, is fine", () => {
  const old = new Date(NOW - 3 * 86_400_000).toISOString();
  const recent = new Date(NOW - 3_600_000).toISOString();
  assertEquals(check({ ...ok, overall_score: 90 }, facts({ last_score: 50, last_at: old }), NOW), null);
  assertEquals(check({ ...ok, overall_score: 90 }, facts({ last_score: 50, last_at: recent, last_provisional: true }), NOW), null);
});

Deno.test("check: needs synced sets and a weekly count the server can roughly confirm", () => {
  assertEquals(check(ok, facts({ completed_sets: 2 }), NOW), "no_data");
  assertEquals(check({ ...ok, weekly_workouts: 6 }, facts({ workouts_7d: 3 }), NOW), "weekly_mismatch");
  assertEquals(check({ ...ok, weekly_workouts: 5 }, facts({ workouts_7d: 3 }), NOW), null);
});

Deno.test("handler: publishes when sharing is on", async () => {
  const { call, published } = setup(facts());
  const response = await call(ok);
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { published: true });
  assertEquals(published, [["u1", 60, false, 3]]);
});

Deno.test("handler: sharing off writes nothing", async () => {
  const { call, published } = setup(facts({ share_score: false }));
  assertEquals(await (await call(ok)).json(), { published: false, reason: "sharing_off" });
  assertEquals(published.length, 0);
});

Deno.test("handler: no profile writes nothing", async () => {
  const { call, published } = setup(facts({ has_profile: false, share_score: false }));
  assertEquals(await (await call(ok)).json(), { published: false, reason: "no_profile" });
  assertEquals(published.length, 0);
});

Deno.test("handler: implausible values are not written", async () => {
  const { call, published } = setup(facts({ completed_sets: 0 }));
  assertEquals(await (await call(ok)).json(), { published: false, reason: "no_data" });
  assertEquals(published.length, 0);
});

Deno.test("handler: auth, validation and rate limit", async () => {
  const { call } = setup(facts());
  assertEquals((await call(ok, "bad")).status, 401);
  assertEquals((await call({ overall_score: 150, provisional: false, weekly_workouts: 1 })).status, 400);
  const limited = setup(facts(), false);
  assertEquals((await limited.call(ok)).status, 429);
  assert(limited.published.length === 0);
});
