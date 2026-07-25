#!/usr/bin/env python3
"""
Flow network map generator for "The Flow Collapses" mod
Sins of a Solar Empire II custom scenario based on John Scalzi's
Interdependency novels (The Collapsing Empire trilogy).

Design intent
-------------
Six player map. Each star system is a node in the Flow network. Flow
streams are WORMHOLE lanes between wormhole fixtures ("Flow shoals").
Normal phase lanes only exist WITHIN a system, so every trip through the
Flow carries the same risk as in the books: the stream home may not be
there when you want to come back.

System profiles:
  * Hub: extremely rich, extremely well defended. Taking it is a war.
  * End: nearly as rich, moderately defended, and hanging off a single
    fragile stream. High reward, one door.
  * Dalasysla: dead system. Two capturable starbases and a derelict
    capital ship flotilla guard the ruins. Only reachable if the dormant
    Bremen stream reopens mid-game.
  * The Houses of the Interdependency appear as minor faction wells
    scattered through the network (Wu, Lagos, Nohamapetan, Claremont are
    canon; the rest are generic minor factions).

IMPORTANT: the .scenario JSON schema and the exact filling / unit names
evolve with game patches. Open the output in SolarForge, let it validate,
correct any filling names it flags against its dropdowns, then re-save.
Names most likely to need correcting are marked with FIXME comments in
the FILLINGS and UNITS tables below. Node ids and lane names are the
stable contract used by scripts/flow_collapse.lua, keep those unchanged.
"""

import json
import math
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "scenarios" / "the_interdependency.scenario"

# ---------------------------------------------------------------------------
# FIXME TABLE: validate every name here against SolarForge's dropdowns for
# your game version, then forget about it. Everything else derives from this.
# ---------------------------------------------------------------------------
global_house_counter = 0

FILLINGS = {
    "star":            "random_star",
    "rich_planet":     "random_terran_planet",
    "planet":          "random_desert_planet",
    "metal_planet":    "random_volcanic_planet",
    "crystal_planet":  "random_ice_planet",
    "credit_planet":   "random_terran_planet",
    "dead_planet":     "random_asteroid",
    "minor_faction":   "random_terran_planet",
    "wormhole":        "wormhole_fixture",
    "asteroid_rich":   "random_asteroid",
}

UNITS = {
    # Derelict defenders and capture rewards at Dalasysla.
    "starbase":        "trader_starbase",          # FIXME: capturable starbase entry
    "capital_battle":  "trader_battle_capital_ship",   # FIXME
    "capital_carrier": "trader_carrier_capital_ship",  # FIXME
    "capital_colony":  "trader_colony_capital_ship",   # FIXME
}

# Militia strength expressed as garrison chance tiers. SolarForge exposes
# per-node militia / garrison settings; these keys mirror that intent.
DEFENCE = {
    "fortress": {"militia_strength": 3.0, "garrison_chance": 1.0},
    "strong":   {"militia_strength": 1.5, "garrison_chance": 0.8},
    "normal":   {"militia_strength": 1.0, "garrison_chance": 0.5},
    "derelict": {"militia_strength": 2.0, "garrison_chance": 1.0},
}

# ---------------------------------------------------------------------------
# Flow network definition
# ---------------------------------------------------------------------------
# profile fields: ring, angle, planets, richness ("rich"/"normal"/"dead"),
#                 defence tier, houses (minor faction wells), home (player idx)
SYSTEMS = {
    "hub": {
        "name": "Hub", "ring": 0, "angle": 0,
        "planets": 6, "richness": "rich", "defence": "fortress",
        "houses": [], "home": None,
    },
    "end": {
        "name": "End", "ring": 1, "angle": 30,
        "planets": 5, "richness": "rich", "defence": "strong",
        "houses": [], "home": None,
    },
    "ikoyi": {
        "name": "Ikoyi", "ring": 2, "angle": 0,
        "planets": 4, "planet_fillings": ["metal_planet", "metal_planet", "metal_planet", "credit_planet"],
        "richness": "normal", "defence": "normal",
        "houses": ["House of Lagos"], "home": 0,
    },
    "bremen": {
        "name": "Bremen", "ring": 2, "angle": 60,
        "planets": 4, "planet_fillings": ["crystal_planet", "crystal_planet", "crystal_planet", "planet"],
        "richness": "normal", "defence": "normal",
        "houses": ["House of Assan"], "home": 1,
    },
    "terhathum": {
        "name": "Terhathum", "ring": 2, "angle": 120,
        "planets": 4, "planet_fillings": ["credit_planet", "credit_planet", "credit_planet", "metal_planet"],
        "richness": "normal", "defence": "normal",
        "houses": ["House of Nohamapetan"], "home": 2,
    },
    "kivu": {
        "name": "Kivu", "ring": 2, "angle": 180,
        "planets": 4, "planet_fillings": ["metal_planet", "metal_planet", "crystal_planet", "crystal_planet"],
        "richness": "normal", "defence": "normal",
        "houses": ["House of Persaud"], "home": 3,
    },
    "melacrion": {
        "name": "Melacrion", "ring": 2, "angle": 240,
        "planets": 4, "planet_fillings": ["planet", "planet", "planet", "planet"],
        "richness": "normal", "defence": "normal",
        "houses": ["House of Rju"], "home": 4,
    },
    "blight": {
        "name": "Blight", "ring": 2, "angle": 300,
        "planets": 4, "planet_fillings": ["dead_planet", "dead_planet", "dead_planet", "credit_planet"],
        "richness": "normal", "defence": "normal",
        "houses": ["House of Claremont"], "home": 5,
    },
    "dalasysla": {
        "name": "Daleceisla", "ring": 3, "angle": 0,
        "planets": 3, "richness": "dead", "defence": "derelict",
        "houses": [], "home": None,
    },
}

FLOW_STREAMS = [
    # Hub connects to all 6 player stars
    ("hub", "ikoyi"),
    ("hub", "bremen"),
    ("hub", "terhathum"),
    ("hub", "kivu"),
    ("hub", "melacrion"),
    ("hub", "blight"),
]

DORMANT_STREAMS = [
    # End is isolated from standard star phase lanes; requires Phase Gates or rare volatile Terhathum stream
    ("terhathum", "end"),
    # Dalasysla starts isolated. Lua script opens these as flicker streams.
    ("ikoyi", "dalasysla"),
    ("bremen", "dalasysla"),
    ("terhathum", "dalasysla"),
    ("kivu", "dalasysla"),
    ("melacrion", "dalasysla"),
    ("blight", "dalasysla"),
]

RING_RADIUS = {0: 0, 1: 8000, 2: 16000, 3: 24000}

# ---------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------

def centre(ring, angle_deg):
    r = RING_RADIUS[ring]
    a = math.radians(angle_deg)
    return r * math.cos(a), r * math.sin(a)


def orbit_pos(cx, cy, radius, angle_deg):
    a = math.radians(angle_deg)
    return [round(cx + radius * math.cos(a), 1),
            round(cy + radius * math.sin(a), 1)]


def make_system(sys_id, spec, nid):
    """Return (nodes, lanes, shoal_id, home_planet_id, next_id)."""
    nodes, lanes = [], []
    cx, cy = centre(spec["ring"], spec["angle"])
    defence = DEFENCE[spec["defence"]]

    star_id = nid
    star_node = {
        "id": star_id,
        "filling_name": FILLINGS["star"],
        "position": [round(cx, 1), round(cy, 1)],
        "primary_fixture_override_name": f":{spec['name']}",
        "child_nodes": []
    }
    nodes.append(star_node)
    nid += 1

    planet_fillings = spec.get("planet_fillings", [])
    if not planet_fillings:
        planet_filling = {
            "rich": FILLINGS["rich_planet"],
            "normal": FILLINGS["planet"],
            "dead": FILLINGS["dead_planet"],
        }[spec["richness"]]
        planet_fillings = [planet_filling] * spec["planets"]
    else:
        planet_fillings = [FILLINGS[f] for f in planet_fillings]

    ring_step = 400
    planet_ids = []
    for i in range(spec["planets"]):
        pr = 600 + i * ring_step
        pa = i * (360 / spec["planets"]) + spec["angle"]
        node = {
            "id": nid,
            "filling_name": planet_fillings[i],
            "position": orbit_pos(cx, cy, pr, pa),
        }
        planet_ids.append(nid)
        star_node["child_nodes"].append(node)
        nid += 1

    # Rich systems get bonus resource asteroids interleaved between planets.
    if spec["richness"] == "rich":
        for i in range(spec["planets"]):
            pr = 900 + i * ring_step
            pa = i * (360 / spec["planets"]) + spec["angle"] + 30
            ast_node = {
                "id": nid,
                "filling_name": FILLINGS["asteroid_rich"],
                "position": orbit_pos(cx, cy, pr, pa),
            }
            star_node["child_nodes"].append(ast_node)
            lanes.append({"node_a": planet_ids[i], "node_b": nid,
                          "type": "normal"})
            nid += 1

    # Minor faction wells: the Houses of the Interdependency.
    MINOR_FACTION_NAMES = [
        "alutar_sect", "aluxian_resurgence", "viturak_cabal",
        "eivonns_frigates", "nilari_cult", "pranast_united"
    ]
    global global_house_counter
    house_ids = []
    for j, house in enumerate(spec["houses"]):
        pr = 600 + spec["planets"] * ring_step
        pa = spec["angle"] + 120 + j * 60
        mf_name = MINOR_FACTION_NAMES[global_house_counter % len(MINOR_FACTION_NAMES)]
        global_house_counter += 1
        mf_node = {
            "id": nid,
            "filling_name": FILLINGS["minor_faction"],
            "position": orbit_pos(cx, cy, pr, pa),
            "primary_fixture_override_name": f":{house}",
            "ownership": {"npc_filling_name": mf_name},
        }
        house_ids.append(nid)
        star_node["child_nodes"].append(mf_node)
        nid += 1

    sr = 600 + (spec["planets"] + 1) * ring_step
    pirate_base_id = None
    if spec["home"] is not None:
        pirate_base_id = nid
        pb_node = {
            "id": pirate_base_id,
            "filling_name": FILLINGS["rich_planet"],
            "position": orbit_pos(cx, cy, sr - (ring_step / 2.0), spec["angle"] + 45),
            "primary_fixture_override_name": ":Pirate Stronghold",
            "ownership": {"npc_filling_type": "militia"},
            "loot_level": 5
        }
        star_node["child_nodes"].append(pb_node)
        nid += 1

    shoal_id = nid
    shoal_name = f":{spec['name']} Phase Gate & Flow Shoal"
    if sys_id == "hub":
        shoal_name = ":Naffa Dolg Phase Gate & Memorial Shoal"
        
    shoal_node = {
        "id": shoal_id,
        "filling_name": FILLINGS["wormhole"],
        "position": orbit_pos(cx, cy, sr, spec["angle"] + 45),
        "primary_fixture_override_name": shoal_name,
    }
    star_node["child_nodes"].append(shoal_node)
    nid += 1

    # Dalasysla's ruins: two capturable starbases guarding the shoal
    # approach, and a derelict capital flotilla parked at the inner planet.
    # Modelled as ship artifacts on unowned nodes (the mapmaker convention:
    # ship groups are only allowed on unowned colonizable bodies).
    if sys_id == "dalasysla":
        shoal_node["primary_fixture_override_name"] = ":Daleceisla Phase Gate & Flow Shoal (evanescent)"
        # Sins 2 1.51+ schema no longer supports 'artifacts' arrays on nodes. 
        # For the derelict fleet, you will need to spawn them via scenario triggers 
        # or use a custom 'npc_filling_name'. I have commented this out to fix the generation errors.
        # for k, target in enumerate((planet_ids[-1], planet_ids[-2])):
        #     for n in star_node["child_nodes"]:
        #         if n["id"] == target:
        #             n.setdefault("artifacts", {})["ship_groups"] = [
        #                 {"unit": UNITS["starbase"], "count": 1,
        #                  "capturable": True,
        #                  "design_name": f":Dalasysla Bastion {k + 1}"}
        #             ]
        # for n in star_node["child_nodes"]:
        #     if n["id"] == planet_ids[0]:
        #         n.setdefault("artifacts", {})["ship_groups"] = [
        #             {"unit": UNITS["capital_battle"], "count": 1, "capturable": True,
        #              "design_name": ":IS Tell Me Another One"},
        #             {"unit": UNITS["capital_carrier"], "count": 1, "capturable": True,
        #              "design_name": ":IS Auvergne"},
        #             {"unit": UNITS["capital_colony"], "count": 1, "capturable": True,
        #              "design_name": ":IS Oliveer Bransid"},
        #         ]

    for pid in planet_ids:
        lanes.append({"node_a": star_id, "node_b": pid})
    for a, b in zip(planet_ids, planet_ids[1:]):
        lanes.append({"node_a": a, "node_b": b})
    for hid in house_ids:
        lanes.append({"node_a": star_id, "node_b": hid})
        
    if pirate_base_id is not None:
        lanes.append({"node_a": planet_ids[-1], "node_b": pirate_base_id})
        lanes.append({"node_a": pirate_base_id, "node_b": shoal_id})
    else:
        lanes.append({"node_a": planet_ids[-1], "node_b": shoal_id})

    return nodes, lanes, shoal_id, planet_ids[0], nid


def build():
    all_nodes, all_lanes = [], []
    shoals = {}
    nid = 1

    xian_node_id = None
    dalasysla_planets = None
    hub_end_nodes = []
    home_militia_nodes = []

    for sys_id, spec in SYSTEMS.items():
        nodes, lanes, shoal_id, first_planet, nid = make_system(sys_id, spec, nid)
        if sys_id == "hub":
            xian_node_id = first_planet
            nodes[0]["child_nodes"][0]["primary_fixture_override_name"] = ":Xi'an"
        elif sys_id == "dalasysla":
            dalasysla_planets = [c["id"] for c in nodes[0]["child_nodes"] if "planet" in c.get("filling_name", "") or "asteroid" in c.get("filling_name", "")]
            
        if sys_id in ("hub", "end"):
            hub_end_nodes.extend([c["id"] for c in nodes[0]["child_nodes"] if "planet" in c.get("filling_name", "") or "asteroid" in c.get("filling_name", "")])
            
        if spec["home"] is not None:
            nodes[0]["child_nodes"][0]["ownership"] = {"player_index": spec["home"]}
            nodes[0]["child_nodes"][0]["filling_name"] = "player_home_planet"
            
            # Defend the rest of the home system's planets with militia
            for child in nodes[0]["child_nodes"][1:]:
                if "ownership" not in child and child.get("filling_name") != FILLINGS["wormhole"]:
                    child["ownership"] = {"npc_filling_type": "militia"}
                    child["loot_level"] = 5
                    if "planet" in child.get("filling_name", "") or "asteroid" in child.get("filling_name", ""):
                        home_militia_nodes.append(child["id"])
        else:
            for child in nodes[0]["child_nodes"]:
                if child["id"] != shoal_id and child.get("filling_name") != FILLINGS["wormhole"]:
                    if sys_id == "dalasysla":
                        child["ownership"] = {"npc_filling_name": "dalasysla_derelicts"}
                        child["loot_level"] = 1
                    elif sys_id == "hub":
                        child["ownership"] = {"npc_filling_name": "hub_fortress"}
                        child["loot_level"] = 5
                    elif sys_id == "end":
                        child["ownership"] = {"npc_filling_name": "end_fortress"}
                        child["loot_level"] = 5
        all_nodes += nodes
        all_lanes += lanes
        shoals[sys_id] = shoal_id

    for a, b in FLOW_STREAMS:
        all_lanes.append({
            "node_a": shoals[a], "node_b": shoals[b],
            "type": "normal"
        })

    for a, b in DORMANT_STREAMS:
        all_lanes.append({
            "node_a": shoals[a], "node_b": shoals[b],
            "type": "normal"
        })

    for i, lane in enumerate(all_lanes):
        lane["id"] = i
        if "type" in lane and lane["type"] == "phase_lane":
            del lane["type"]

    scenario_info = {
        "version": 1,
        "name": ":The Interdependency",
        "description": (":Six empires on a dying Flow network. Hub is a fortress "
                        "of riches, End is the rich back door with one way in, "
                        "and every jump risks the stream home collapsing behind "
                        "you. The Houses watch, and wait."),
        "desired_player_slots_configuration": {
            "player_count": 6,
            "team_count": 0
        }
    }

    galaxy_chart = {
        "version": 1,
        "skybox": "skybox_random",
        "root_nodes": all_nodes,
        "phase_lanes": all_lanes,
    }
    
    flow_metadata = {
        "shoal_node_ids": shoals,
        "xian_node_id": xian_node_id,
        "dalasysla_planets": dalasysla_planets,
        "hub_end_nodes": hub_end_nodes,
        "home_militia_nodes": home_militia_nodes,
        "active_streams": [f"{a}_{b}" for a, b in FLOW_STREAMS],
        "dormant_streams": [
            {"id": f"{a}_{b}", "node_a": shoals[a], "node_b": shoals[b]}
            for a, b in DORMANT_STREAMS
        ],
    }
    return scenario_info, galaxy_chart, flow_metadata


if __name__ == "__main__":
    scenario_info, galaxy_chart, flow_metadata = build()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    import zipfile
    with zipfile.ZipFile(OUT, 'w', zipfile.ZIP_DEFLATED) as zf:
        zf.writestr('scenario_info.json', json.dumps(scenario_info, indent=2))
        zf.writestr('galaxy_chart.json', json.dumps(galaxy_chart, indent=2))
    
    # Dump flow data for lua script
    def lua_format(obj):
        if isinstance(obj, dict):
            return "{\n  " + ",\n  ".join([f'["{k}"] = {lua_format(v)}' for k, v in obj.items()]) + "\n}"
        elif isinstance(obj, list):
            return "{ " + ", ".join([lua_format(v) for v in obj]) + " }"
        elif isinstance(obj, str):
            return f'"{obj}"'
        else:
            return str(obj)

    lua_out = OUT.parent.parent / "scripts" / "flow_data.lua"
    lua_out.parent.mkdir(parents=True, exist_ok=True)
    with open(lua_out, "w") as f:
        f.write("return " + lua_format(flow_metadata) + "\n")
    

    houses = sum(len(s["houses"]) for s in SYSTEMS.values())
    print(f"Wrote {OUT}")
    print(f"  systems: {len(SYSTEMS)}, nodes: {len(galaxy_chart['root_nodes'])}, "
          f"lanes: {len(galaxy_chart['phase_lanes'])}, "
          f"players: {scenario_info['desired_player_slots_configuration']['player_count']}, houses: {houses}")
    print("  Now open it in SolarForge to validate and re-save.")
