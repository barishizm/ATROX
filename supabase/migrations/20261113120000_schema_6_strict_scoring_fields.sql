-- P056 · Schema 6 — restore the strict scoring-parameter rule now that the anchor ratios exist.
--
-- P011 required every weighted / bodyweight_loaded exercise to carry anchor_lift, ratio, tau and ratio_confidence.
-- P028 relaxed that to "all or none" because the numbers were only computed in P056
-- (20261112140000_schema_4_catalog_vocabulary.sql). P056 fills them for the scored core set
-- (tools/catalog/ratios.yaml → scoring_taxonomy.yaml → catalog). docs/03-ML-MODEL.md §6: only the ~150 core
-- exercises produce a percentile; the rest are logged but not scored. So the rule is now:
--   scored type and is_core     → every scoring parameter is set (bodyweight_loaded also needs bw_fraction)
--   scored type and not is_core → no anchor parameters at all
--
-- The constraints are added NOT VALID: rows already seeded from catalog v1 (core rows without parameters) stay
-- readable until `catalog-seed` writes catalog v2, and every insert/update is checked from now on. After seeding v2
-- run `alter table public.exercises validate constraint ...` for both constraints (docs/ILERLEME.md, P056 note).

alter table public.exercises
  drop constraint exercises_weighted_fields_check,
  drop constraint exercises_bodyweight_loaded_fields_check;

alter table public.exercises
  add constraint exercises_weighted_fields_check
    check (scoring_type <> 'weighted'
           or (is_core
               and anchor_lift is not null and ratio is not null and tau is not null
               and load_convention is not null and ratio_confidence is not null)
           or (not is_core
               and anchor_lift is null and ratio is null and tau is null and ratio_confidence is null))
    not valid,
  add constraint exercises_bodyweight_loaded_fields_check
    check (scoring_type <> 'bodyweight_loaded'
           or (is_core
               and anchor_lift is not null and ratio is not null and tau is not null
               and bw_fraction is not null and ratio_confidence is not null)
           or (not is_core
               and anchor_lift is null and ratio is null and tau is null and ratio_confidence is null))
    not valid;
