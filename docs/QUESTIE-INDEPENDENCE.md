# Plan: not relying on Questie

Status: done in 0.15.0. The data set, the rules, the service lists, quest XP and zones are checked against Questie with no differences, and the addon runs without Questie. The plan below is kept for the reasoning.

## Where we depend on it today

About 330 references in 25 files, almost all calling Questie directly. The biggest users are `Extras.lua` (planner, arrow), `Dungeons.lua`, `ClassQuests.lua`, `ForeverLazy.lua`, `Quests.lua`, `Services.lua`, `Crafting.lua`.

What we read from it:

| Need | Questie source | Used for |
|---|---|---|
| Quest facts: name, level, required level/race/class, group size, zone, chain (`nextQuestInChain`), objectives | `QuestieDB.QueryQuestSingle` | planner, tracker, dungeon/class checks |
| Who gives / takes a quest and where they stand | `QueryNPCSingle`, `QueryObjectSingle`, `startedBy`, `finishedBy` | pick-up and hand-in stops |
| Where to kill / collect | NPC, object and item spawns | arrow, kill spots |
| XP per quest | `QuestXP` module (`xpDB-classic`) | XP-for-time planning |
| What is available to me | `AvailableQuests` | zone plan, "nearby givers" |
| Drop tables, zone to map ids | `classicItemDrops`, `areaIdToUiMapId`, `subZoneToParentZone` | crafting, zones |

## The one thing to settle first: licence

Questie and QuestieDB are **GPL-3.0**. Forever Lazy is **MIT**. Today that is fine, because we only call Questie at run time as an optional add-on. Copying its data or code into our repo is not fine under MIT: the combined work would have to be GPL-3.0.

So the plan depends on one decision:

- **A. Relicense Forever Lazy to GPL-3.0**, ship a data set derived from Questie's (credited), and carry on from there. Fastest, full coverage. Costs: the MIT licence goes, and anyone reusing our code has to be GPL.
- **B. Stay MIT, build our own data**: what the game tells us (quest log, quest and gossip windows, map, flight and nodes) plus what players see and share through the Hive. Clean and independent, but only knows what has been seen. Quests nobody has taken are missing, so planning a whole zone you have not played is weak at first.
- **C. Hybrid (recommended):** B as the foundation, and Questie stays an optional extra that fills gaps when installed. We never ship its data, so MIT stays. Over time our own data grows until Questie is not needed for the common path.

## Phases

**Phase 1 - One door (no change in behaviour).** Add `Data.lua` with a small interface: `Quest(id)`, `Npc(id)`, `Object(id)`, `Item(id)`, `QuestXP(id, level)`, `Available()`, `SpawnsFor(kind, id)`. Move every direct Questie call behind it, one file at a time, starting with `Extras.lua`. A fake provider lets the offline tests (`tests/run.lua`) cover the planner without Questie. Done when `grep Questie` finds it only in `Data.lua`.

**Phase 2 - Our own store.** `ForeverLazyData` (saved variables) with the same shapes. Filled from play:
- Quest log reads: id, title, level, zone, objectives, XP reward (`GetQuestLogRewardXP`), group tag.
- Quest and gossip windows: the giver or taker (NPC id from the GUID), and where we stood (that is the giver's position).
- Kills, loot and nameplates: mob id, name, level and position (like the new mob levels), and what dropped.
- Nodes, flight points, trainers, vendors: already partly recorded.
- Objective spots: already in the Hive.

**Phase 3 - Provider chain.** `Data.lua` asks our store first, then Questie if installed. Add `/lazy data` to show coverage (quests, NPCs, spawns known, and how many came from our store versus Questie) so we can see how close we are.

**Phase 4 - Share it.** Extend the Hive so players pool what they learned (quest givers, spawns, XP), the same privacy rules as now: coarse squares only, never names or tracks. Add a validation step (a fact needs several independent sightings).

**Phase 5 - Questie optional.** The plan runs on our data alone. Questie, if present, only fills what is still missing. Update the docs, the README and the add-on's optional dependencies.

## What will not be as good without Questie

- Quests you have not yet taken in an area you have not visited: we cannot list them until someone has seen them (or we ship a data set, option A).
- Spawn positions for rare or little-killed mobs.
- Pre-computed chains for quests you have not started.

Phases 1 and 2 are safe under any licence choice and worth doing first.
