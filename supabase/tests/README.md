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
