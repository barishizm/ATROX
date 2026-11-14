-- Fix for P087: social_score_history had RLS on but no policy, which the RLS audit (001_rls_audit) rejects.
-- An explicit deny-all policy states the intent. Clients still have no grants; only security definer functions
-- (social_publish, friends_leaderboard) touch the table.
create policy social_score_history_no_client_access on public.social_score_history
  for select to authenticated using (false);
