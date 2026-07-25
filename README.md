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
- **End** (player 2): nearly as rich as Hub, heavily defended by Pirate Blockades, and cut off from natural star phase lanes. Its wealth is protected by geography and isolation: reaching End requires **Phase Gate** construction (building Phase Gates to link to End's Phase Gate) or accessing the rare Terhathum volatile stream when it occasionally flickers open.
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

### 3. Flow Awakening & Evanescent "Flicker Streams"
- **Flow Awakening at 1-Hour Mark**: For the first 60 minutes, inter-system Flow streams remain dormant, allowing factions to build up their home systems and prepare for the galactic collapse. In-game broadcasts deliver periodic countdown bulletins (`Flow awakening in X minutes...`). At the 1-hour mark, inter-system star travel awakens!
- **Dynamic Evanescent Phasing**: After 60 minutes, streams phase in and out randomly on 5-10 minute intervals.
- **Daleceisla Raid Windows**: The dormant system of Daleceisla periodically phases in as an evanescent flicker stream with a publicly broadcasted raid window (10-15 minutes). Players must rush through, secure the derelicts and starbases, and retreat before the stream phases out again!

### 4. Phase Gate Routing (All Factions)
All playable factions (Trader, Vasari, Advent) have access to Phase Gates (Phase Lane Stabilizers). Constructing Phase Gates in your owned gravity wells creates direct phase links between them. This allows all factions to build player-controlled bypass phase routes across the galaxy, providing a vital strategic counter when natural Flow streams collapse!

### 5. One-Way Streams & Isolation
The End system's connection to Hub is extremely volatile. It will eventually collapse on its own independent timer, completely isolating whoever is inside unless it randomly flickers back open. 

### 8. Periodic Galactic Inflation
As the Interdependency collapses, trade networks crumble. Every **10 minutes**, global inflation increases costs by **+5%** across all ships, structures, and research. Each collapsed Flow stream adds an extra **+6%** scarcity surcharge (capping at +100%).

### 9. Escalating Pirate & Minor House Aggression
Resource scarcity pushes pirate warlords and minor house raiders into fierce desperation. Every **15 minutes**, aggression threat levels escalate (`PIRATE & MINOR HOUSE ESCALATION`). Stronghold garrisons at Hub and End receive reinforcement calls, and holding the Imperial Throne at Xi'an draws increasingly aggressive raid waves!

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
