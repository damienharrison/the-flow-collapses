# The Flow Collapses

A Sins of a Solar Empire II mod inspired by John Scalzi's Interdependency trilogy (The Collapsing Empire, The Consuming Fire, The Last Emperox). Inter-system travel depends entirely on Flow streams, and the Flow is dying. Streams destabilise, shift and collapse as the game runs. Hold Hub while the network shrinks around you, or fortify End and wait for the door to close behind everyone else.

## What is in the box

```
the_flow_collapses/
├── .mod_meta_data                      Mod manifest (compatibility_version 2)
├── uniforms/
│   └── scenario.uniforms               Registers the map with the game
├── scenarios/
│   └── the_interdependency.scenario    The Flow network map (generated)
├── scripts/
│   ├── flow_collapse.lua               Stream collapse / shift event logic
│   └── flow_data.lua                   Generated node mappings for the script
└── tools/
    └── generate_map.py                 Regenerates the map, tweak and rerun
```

## The Map Design

A six player map. Nine systems arranged as the Flow network from the books:

- **Hub** (player 1): the centre, five streams, six rich planets. The prize of the map, heavily fortified with massive Pirate Blockades on every planet. The central planet is **Xi'an**.
- **End** (player 2): nearly as rich as Hub, heavily defended by Pirate Blockades, and reachable only via the Terhathum stream. Its wealth is protected less by guns and more by geography: one door, and that door is the least stable stream on the map.
- **Ikoyi, Bremen, Terhathum, Kivu** (players 3 to 6): standard middle ring starts.
- **Melacrion**: unowned free real estate, the tempting expansion that might strand your fleet.
- **Dalasysla**: dead system behind a dormant stream. Two capturable starbases (Dalasysla Bastion 1 and 2) guard the shoal approach, and a derelict capital flotilla sits at the inner planet: the *IS Tell Me Another One*, the *Auvergne* and the *Oliveer Bransid*, all capturable. If the Bremen stream reopens mid-game as a flicker stream, the race is on.
- **Earth**: unreachable at start. A late shoal to Earth is the map's lottery ticket.

## Features & Mechanics

We have fully implemented several bespoke mechanics using the map generator and Sins 2's Lua event engine:

### 1. Monopoly Economies
The Interdependency's political design relies on enforced mutual dependence: no system is self-sufficient. Every player home system is deliberately lopsided with unique planetary fillings, forcing them to trade or conquer to survive.

### 2. The Throne at Xi'an
Holding the central planet of the Hub (Xi'an) grants you the title of Emperox. The Lua script automatically checks ownership of Xi'an every 5 minutes and taxes the Interdependency on your behalf, granting you a massive credit injection.

### 3. Evanescent "Flicker Streams"
The Flow is unstable. Occasionally, the script will open a temporary "raid window" by forming a stream to a dormant system (like Dalasysla). A strict lifespan is announced publicly. You must dash through, secure the derelicts, and get out before the stream collapses again, trapping you forever.

### 4. One-Way Streams & Isolation
The End system's connection to Hub is extremely volatile. It will eventually collapse on its own independent timer, completely isolating whoever is inside unless it randomly flickers back open. 

### 5. Restored Houses & Pirate Blockades
The six Houses of the Interdependency exist as active minor factions (e.g. `alutar_sect`, `aluxian_resurgence`), ready to be courted.
Meanwhile, Hub and End are completely overrun by Pirate Blockades spawned immediately on tick 1 by the Lua script (Starbases and heavy cruisers on every planet) ensuring they are terrifying fortresses to crack.

### 6. Flow Physics & Rachela's Prophecy
A multi-tier Flow Physics research tree exists. Advancing through it allows you to get earlier warnings about stream collapses. Reaching Tier 3 grants you exclusive access to Rachela's Prophecy dialogue, giving you a massive head start on the public bulletins.

## Installation

1. Copy the whole `the_flow_collapses` folder to `%localappdata%\sins2\mods\`.
2. Launch the game, open Modding, Local tab, enable the mod, then Manage, Apply Changes.
3. The Interdependency appears in the scenario list.

For quick map-only testing without the mod system, you can also drop the `.scenario` file into `%localappdata%\sins2\drop_in_scenarios\`.

## Tuning

Everything interesting lives at the top of the two files:

- `tools/generate_map.py`: systems, streams, dormant streams, planets per system, ring radii. Rerun with `python generate_map.py` after editing.
- `scripts/flow_collapse.lua`: `CONFIG` table for timings and reopen chance, `COLLAPSE_WEIGHT` for which streams die first, `ONE_WAY_STREAMS` if you want directional Flow flavour.

## Sources

- Custom scenario and mod structure: StardockCorp sins2modtools, docs/making_a_custom_scenario.md
- Lua Event Tutorial: wiki.sinsofasolarempire2.com (SSEFW/3170238513)
