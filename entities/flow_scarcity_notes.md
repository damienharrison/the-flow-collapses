# Scarcity: rising ship prices as the Flow dies

Design: every collapsed stream raises ship build prices for ALL empires by
`scarcity_pct_per_collapse` (default 6%), capped at `scarcity_pct_cap`
(default 48%). Reopened streams relieve one level. Both values live in the
CONFIG table of scripts/flow_collapse.lua. The fiction: the Interdependency
was built so no system is self-sufficient, so every severed route makes
everything more expensive everywhere.

Deliberate gameplay consequences:
- Early aggression gets cheaper relative to late aggression. Turtling into
  the endgame means paying 1.5x for your doom fleet.
- The Dalasysla derelicts (two starbases, three capitals) are pre-inflation
  hardware. Their value rises every time a stream dies, which makes the
  reopening race hotter the later it happens.
- Fleets in being become precious. Losing a fleet at +36% replacement cost
  hurts far more than the same loss in the opening hour.

## Implementation routes, in order of preference

1. Player modifier via scripted grant (cleanest). Vanilla research subjects
   already carry unit build price scalars (several factions have cost
   reduction techs), so the modifier type exists. Create eight hidden
   research subjects `flow_scarcity_1` to `flow_scarcity_8`, each granting
   a cumulative +6% `unit_build_price_scalar` style player modifier (copy
   the exact modifier block from a vanilla cost-reduction subject and flip
   the sign/scalar). Bindings.apply_scarcity_level then grants
   `flow_scarcity_<level>` to every player. Check the Lua API for a
   grant-research or apply-buff call in the Lua Event Tutorial.

2. Buff route: if the API can apply a named buff to players or their home
   planets, a stacking buff entity carrying the same price scalar works
   identically and avoids research tree clutter.

3. Fallback if neither is scriptable: pre-authored escalation without Lua.
   Change the mechanic from collapse-driven to time-driven using whatever
   timed global effects the current schema supports, and say so honestly
   in the mod description. Less elegant, still thematic.

The localisation keys IDS_FLOW_SCARCITY_NAME / _DESC in
localized_text/en.localized_text are ready for whichever entity carries
the modifier, so the price rise shows a proper tooltip rather than
mystery inflation.
