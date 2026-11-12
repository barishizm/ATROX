import { assertEquals, FakeStore, post } from "../_shared/testing.ts";
import { USER_TABLES } from "../_shared/user-data.ts";
import { createDeleteHandler } from "./handler.ts";

const A = "00000000-0000-0000-0000-0000000000a1";
const B = "00000000-0000-0000-0000-0000000000b2";

function store() {
  const fake = new FakeStore({ "token-a": A, "token-b": B });
  for (const table of USER_TABLES) {
    fake.add(table, { id: `${table}-a`, user_id: A });
    fake.add(table, { id: `${table}-b`, user_id: B });
  }
  return fake;
}

Deno.test("delete-account removes every row of the caller, children first, then the auth user", async () => {
  const fake = store();
  const response = await createDeleteHandler({ store: fake })(post("delete-account", "token-a"));

  assertEquals(response.status, 200);
  assertEquals(await response.json(), { deleted: true, apple_revoked: null });
  for (const table of USER_TABLES) {
    assertEquals(fake.tables.get(table)!.map((row) => row.user_id), [B], table);
  }
  assertEquals(fake.deleteOrder, [...[...USER_TABLES].reverse(), "auth.users"]);
  assertEquals([...fake.authUsers], [B]);
});

Deno.test("delete-account revokes Apple tokens with the code from the app", async () => {
  const codes: string[] = [];
  const handler = createDeleteHandler({
    store: store(),
    revokeApple: (code) => {
      codes.push(code);
      return Promise.resolve();
    },
  });
  const response = await handler(post("delete-account", "token-a", { apple_authorization_code: "c0de" }));

  assertEquals(await response.json(), { deleted: true, apple_revoked: true });
  assertEquals(codes, ["c0de"]);
});

Deno.test("a failed Apple revocation still deletes the account and says so", async () => {
  const fake = store();
  const handler = createDeleteHandler({ store: fake, revokeApple: () => Promise.reject(new Error("apple down")) });
  const response = await handler(post("delete-account", "token-a", { apple_authorization_code: "c0de" }));

  assertEquals(await response.json(), { deleted: true, apple_revoked: false });
  assertEquals([...fake.authUsers], [B]);
});

Deno.test("delete-account validates the token and the body", async () => {
  const fake = store();
  const handler = createDeleteHandler({ store: fake });
  assertEquals((await handler(post("delete-account"))).status, 401);
  assertEquals((await handler(post("delete-account", "forged"))).status, 401);
  assertEquals((await handler(post("delete-account", "token-a", { apple_authorization_code: 42 }))).status, 400);
  const broken = new Request("http://localhost/delete-account", {
    method: "POST",
    headers: { Authorization: "Bearer token-a" },
    body: "{not json",
  });
  assertEquals((await handler(broken)).status, 400);
  assertEquals(fake.deleteOrder, []);
});

Deno.test("a database failure stops before the auth user is removed", async () => {
  const fake = store();
  fake.failOn = "workouts";
  const response = await createDeleteHandler({ store: fake })(post("delete-account", "token-a"));

  assertEquals(response.status, 500);
  assertEquals(fake.authUsers.has(A), true);
});
