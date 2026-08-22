# Layer-first folder layout

We chose layer-first (`lib/ui`, `lib/domain`, `lib/data`, `lib/core`) over feature-first, per owner preference, despite feature-first reducing cross-slice collisions. Trade-off: clearer layer boundaries and shared domain models, at the cost of more files touched per vertical slice. Mitigated by slice discipline and `core/` for shared theme/l10n/supabase.
