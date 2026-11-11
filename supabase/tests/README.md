# supabase/tests/

pgTAP schema and RLS tests. Run with:

```bash
supabase db reset && supabase test db
```

Conventions:

- One file per area, named `NNN_<area>.test.sql` (for example `010_profiles_rls.test.sql`).
- Each file starts with `begin;` and ends with `select * from finish(); rollback;` so tests leave no state.
- Every table must have a test proving RLS is enabled and that one user cannot read or write another user's rows.
- Use `tests.create_supabase_user(...)` / `set local role authenticated` to impersonate users.

## RLS suite (P013)

| File | Purpose |
|---|---|
| `000_rls_helpers.test.sql` | `tests` helper schema (`create_two_users`, `authenticate_as`, `authenticate_as_anon`, `clear_authentication`, `try_sql`) and the **table registry** (`tests.owner_tables()`, `tests.catalog_tables()`). Committed, not rolled back. |
| `001_rls_audit.test.sql` | Fails if a public table has RLS off, no policy, is not in the registry, has an owner policy not scoped by `auth.uid()` or applying to `anon`, or a catalog table has a write policy. |
| `020_rls_matrix.test.sql` | Runs the five RLS properties against every registered table. |

**Adding a table:** add it to the registry in `000_rls_helpers.test.sql`, then add row-level tests in a new `NNN_*.test.sql`.
The audit fails until you do. CI (`core.yml`, job `database`) runs `supabase test db` and the security advisors.

