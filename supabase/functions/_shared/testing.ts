// Test helpers without remote imports (CI runs `deno test --allow-env --allow-read`).
import { type Row, USER_TABLES, type UserDataStore, type UserTable } from "./user-data.ts";

export function assertEquals(actual: unknown, expected: unknown, message = ""): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`${message}\nexpected: ${e}\n  actual: ${a}`);
}

export function assert(condition: unknown, message = "assertion failed"): asserts condition {
  if (!condition) throw new Error(message);
}

/** In-memory tables keyed by name; tokens map to user ids. */
export class FakeStore implements UserDataStore {
  tables = new Map<UserTable, Row[]>(USER_TABLES.map((table) => [table, []]));
  authUsers = new Set<string>();
  deleteOrder: string[] = [];
  failOn?: UserTable;

  constructor(public tokens: Record<string, string>) {
    for (const id of Object.values(tokens)) this.authUsers.add(id);
  }

  add(table: UserTable, row: Row) {
    this.tables.get(table)!.push(row);
  }

  userIdFromToken(jwt: string) {
    return Promise.resolve(this.tokens[jwt] ?? null);
  }

  rows(table: UserTable, userId: string) {
    if (this.failOn === table) return Promise.reject(new Error("boom"));
    return Promise.resolve(this.tables.get(table)!.filter((row) => row.user_id === userId));
  }

  deleteRows(table: UserTable, userId: string) {
    if (this.failOn === table) return Promise.reject(new Error("boom"));
    this.deleteOrder.push(table);
    this.tables.set(table, this.tables.get(table)!.filter((row) => row.user_id !== userId));
    return Promise.resolve();
  }

  deleteAuthUser(userId: string) {
    this.deleteOrder.push("auth.users");
    this.authUsers.delete(userId);
    return Promise.resolve();
  }
}

export function post(path: string, token?: string, body?: unknown): Request {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (token) headers.Authorization = `Bearer ${token}`;
  return new Request(`http://localhost/${path}`, {
    method: "POST",
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}
