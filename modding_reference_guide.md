# Sins of a Solar Empire II - Map Generation Reference Guide

This guide documents the key schema and logic updates required to bring a custom map generator (originally built for earlier versions or based on older assumptions) into full compliance with the latest Sins of a Solar Empire II engine (v1.51+).

## 1. Map Coordinates and Travel Speed
**Problem:** Ships take 10+ minutes to traverse phase lanes within a system.
**Solution:** Sins 2 uses a much smaller, tighter coordinate scale than you might expect.
- Distances like `26,000` units between a star and its planets are massively too large. 
- A comfortable orbit distance for a planet is roughly `2,000` to `3,500` units.
- Outer ring distances between different star systems should sit around `10,000` to `40,000` units rather than hundreds of thousands.

## 2. Invalid Filling Names (The "Capital Defeat" Bug)
**Problem:** Loading into the scenario immediately results in "Capital Defeat", even though a home planet was generated in the JSON.
**Solution:** The game uses a strict set of valid `filling_name` strings. If a star node is assigned an invalid name (like `"star"`), the engine simply refuses to spawn it. If the star doesn't spawn, none of its child planets spawn, leaving the player with no capital planet and no fleet, triggering instant defeat.
- **Star:** Use `"random_star"` (not `"star"`)
- **Terran/Rich:** Use `"random_terran_planet"`
- **Desert/Normal:** Use `"random_desert_planet"`
- **Dead/Asteroids:** Use `"random_asteroid"`
- **Wormholes:** Use `"wormhole_fixture"`

## 3. Custom Planet Names
**Problem:** Custom names generated for planets don't actually appear in-game.
**Solution:** Do not use `"name"`, `"custom_name"`, or `"design_name"` to rename a celestial body. The correct property supported by the `galaxy_chart_node` schema is:
```json
"primary_fixture_override_name": ":Your Custom Planet Name"
```

## 4. Strict JSON Schema Requirements
**Problem:** SolarForge throws "JSON read errors" and lists unused keys.
**Solution:** The Sins 2 schemas are highly explicit and reject custom data dumped into node structures.
- **Phase Lane IDs:** The `id` key inside `phase_lanes` MUST be an integer (e.g., `1`, `2`, `3`), not a string like `"lane_1"`.
- **Deprecated Properties:** You cannot arbitrarily attach keys like `militia_strength`, `garrison_chance`, `player_home_planets`, or `flow_metadata` to map nodes. 
- **Artifacts:** Spawning ships via an `artifacts` array directly on nodes is no longer supported by the schema. Custom derelict fleets must be spawned via scenario triggers or specialized `npc_filling_name` ownership definitions.

## 5. Scenario Uniforms Updates
**Problem:** The game crashes or throws JSON read errors when parsing `uniforms/scenario.uniforms`.
**Solution:** With the introduction of DLCs, the engine strictly expects DLC scenario arrays. Your `scenario.uniforms` file must include:
```json
"dlc_scenarios": [],
"dlc_multiplayer_scenarios": []
```

## 6. NPC Ownership (Pirate Systems)
To create a hostile "pirate" system (like Hub or End), you might be tempted to assign `"enemy_faction"`. However, without assigning a specific `npc_filling_name`, the node may spawn completely empty!

To natively force the engine to generate heavy defending forces without specific configurations, the best practice is to assign `"militia"` and set a high `loot_level` on the node:
```json
"ownership": {
    "npc_filling_type": "militia"
},
"loot_level": 5
```
This guarantees the engine will automatically populate the gravity well with a scaled, hostile defensive fleet.

> [!WARNING]
> **Asteroids Cannot Support Militia:** If you assign the `"militia"` ownership type to a `dead_planet` or `random_asteroid`, the base will still spawn completely empty! Asteroids have 0 max defense slots, meaning the engine has nowhere to spawn the militia ships. Always use a colonizable planet (like `random_terran_planet` or `random_desert_planet`) for heavy pirate strongholds.
