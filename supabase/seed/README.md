# supabase/seed/

Local and test seed data. `supabase db reset` applies every `*.sql` file here (alphabetical order) after the
migrations, as configured in `config.toml` (`[db.seed] sql_paths`).

Rules:

- Seed files run **only locally** (`db reset`). They are never pushed to staging or production.
- Idempotent and deterministic: fixed UUIDs, `on conflict do nothing`.
- No real user data and no secrets. Test accounts use obviously fake emails (`*@example.test`).
- Name files with a numeric prefix to control order: `01_exercises.sql`, `02_test_users.sql`.
- The exercise catalog itself ships as a migration or a tools/ import, not as seed data (decided in a later step).
