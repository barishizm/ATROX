import { assert, assertEquals } from "../_shared/testing.ts";
import { createCoachChatHandler, fakeLLM } from "./handler.ts";

const A = "00000000-0000-0000-0000-0000000000a1";
const THREAD = "11111111-1111-4111-8111-111111111111";

const handler = createCoachChatHandler({
  verify: (jwt) => Promise.resolve(jwt === "token-a" ? A : null),
  llm: fakeLLM,
  newThreadId: () => THREAD,
});

function chat(body: unknown, token: string | null = "token-a", raw = false): Request {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  return new Request("http://localhost/coach-chat", {
    method: "POST",
    headers,
    body: raw ? (body as string) : JSON.stringify(body),
  });
}

async function errorCode(response: Response): Promise<string> {
  return (await response.json()).error.code;
}

Deno.test("coach-chat refuses requests without a valid token (401)", async () => {
  const body = { message: "hi", locale: "en" };
  const missing = await handler(chat(body, null));
  assertEquals(missing.status, 401);
  assertEquals(await errorCode(missing), "unauthorized");
  assertEquals((await handler(chat(body, "forged"))).status, 401);
});

Deno.test("coach-chat rejects invalid bodies (400)", async () => {
  const bad: unknown[] = [
    {},
    { message: "", locale: "en" },
    { message: "   ", locale: "en" },
    { message: "x".repeat(2001), locale: "en" },
    { message: "hi" },
    { message: "hi", locale: "not a locale" },
    { message: "hi", locale: "en", thread_id: "nope" },
    { message: "hi", locale: "en", extra: true },
  ];
  for (const body of bad) {
    const response = await handler(chat(body));
    assertEquals(response.status, 400, JSON.stringify(body));
    assertEquals(await errorCode(response), "invalid_request");
  }
  const notJson = await handler(chat("{oops", "token-a", true));
  assertEquals(notJson.status, 400);
  assertEquals(await errorCode(notJson), "invalid_request");
});

Deno.test("coach-chat accepts a message of exactly 2000 characters", async () => {
  const response = await handler(chat({ message: "x".repeat(2000), locale: "tr" }));
  assertEquals(response.status, 200);
  await response.body?.cancel();
});

Deno.test("coach-chat answers GET with 405 and OPTIONS with CORS", async () => {
  assertEquals((await handler(new Request("http://localhost/coach-chat", { method: "GET" }))).status, 405);
  const options = await handler(new Request("http://localhost/coach-chat", { method: "OPTIONS" }));
  assertEquals(options.status, 204);
  assert(options.headers.get("Access-Control-Allow-Headers")?.includes("authorization"));
});

Deno.test("coach-chat streams text_delta…, usage, done in order", async () => {
  const response = await handler(chat({ message: "hello", locale: "en" }));
  assertEquals(response.status, 200);
  assert(response.headers.get("Content-Type")?.startsWith("text/event-stream"));

  const frames = (await response.text()).split("\n\n").filter(Boolean).map((frame) => {
    const [eventLine, dataLine] = frame.split("\n");
    return { type: eventLine.replace("event: ", ""), data: JSON.parse(dataLine.replace("data: ", "")) };
  });
  const types = frames.map((frame) => frame.type);
  assert(types.filter((type) => type === "text_delta").length > 1, "text arrives in several pieces");
  assertEquals(types.slice(-2), ["usage", "done"]);
  assert(types.slice(0, -2).every((type) => type === "text_delta"));
  const text = frames.filter((frame) => frame.type === "text_delta").map((frame) => frame.data.text).join("");
  assert(text.startsWith("Hi!"));
  assertEquals(frames.at(-1)?.data, { thread_id: THREAD });
});

Deno.test("coach-chat keeps the caller's thread id and reports a failing model as an error event", async () => {
  const failing = createCoachChatHandler({
    verify: () => Promise.resolve(A),
    // deno-lint-ignore require-yield
    llm: async function* () {
      throw new Error("boom");
    },
  });
  const response = await failing(chat({ message: "hi", locale: "en", thread_id: THREAD }));
  const text = await response.text();
  assert(text.includes("event: error"));
  assert(!text.includes("boom"), "no internal details leak");
  assert(!text.includes("event: done"));

  const ok = await handler(chat({ message: "hi", locale: "en", thread_id: "22222222-2222-4222-8222-222222222222" }));
  assert((await ok.text()).includes("22222222-2222-4222-8222-222222222222"));
});
