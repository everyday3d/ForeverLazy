<p align="center">
  <img src="docs/banner.svg" alt="Lazy RestedXP Tracker" width="100%">
</p>

<p align="center">
  <img alt="Game" src="https://img.shields.io/badge/WoW-Forever-4db8ff?style=for-the-badge">
  <img alt="Interface" src="https://img.shields.io/badge/interface-16001-ffd94d?style=for-the-badge">
  <img alt="Version" src="https://img.shields.io/badge/version-0.5.7-6bd16b?style=for-the-badge">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-ff9ad5?style=for-the-badge">
</p>

<p align="center"><b>Arrows that point where your quests, your party and your next big XP are.<br>
Works on its own, and with Questie it plans your whole levelling route.</b></p>

---

## What it does

**Lazy RestedXP Tracker** started as a way to follow a friend who runs RestedXP: it listens to their party
broadcasts and points arrows at their quest spots and at them. It has grown into a levelling companion for
**WoW Forever** that plans routes, guides secret quest chains, collects the world's library books and nags you
about the small things (a hungry pet, an unspent trip to the trainer, a corpse run).

You do **not** need RestedXP installed. [Questie](https://www.curseforge.com/wow/addons/questie) is optional but
unlocks most of the planning features.

## Features

### Arrows that know where to go

| | |
|---|---|
| **Party arrows** | Quest arrows and a "friend" arrow, driven by a party member's RestedXP step. Shift-click the friend arrow to tell the party *On my way!* |
| **My quests arrow** | Follows the quest you have selected or tracked, or the nearest worthwhile one. |
| **Compass bar** | A slim bar at the top of the screen showing the direction of your targets. |
| **Waypoints** | `/lrxp way`, Ctrl + right-click the world map, minimap and world-map pins, optional TomTom support. |
| **Three arrow styles** | Classic, chevron and thick. Colours, size, opacity and position are all yours, and everything is movable. |
| **Smart hiding** | Hide in combat, in cities and inns, on flight paths and **inside dungeons and raids**. |
| **Ghost arrow** | When you die, one arrow points at your body. Die in a dungeon and it points at the **dungeon entrance** for the corpse run. |

### A route planner that thinks about XP

`/lrxp plan` (or the **Plan my route** button) turns your quest log into the most efficient trip:

- **XP-weighted**: stops that pay the most XP for the least walking come first
- **Does quests together**: spots where several quests overlap are done in one visit, then each turn-in comes after its objectives
- **Colour filter**: green, yellow and orange quests are in, red only as a turn-in, grey never
- **Stays in your zone**: no being sent across the world once you are somewhere
- **Updates itself**: replans when a quest is accepted, finished or handed in, and when you change zone
- **Nothing to do here?** It routes you to the nearest hub of **quest givers** instead and fills in the objectives as you accept quests
- **Class quests** you can take are slotted in with extra weight
- A gold **?** over the arrow marks a turn-in, a gold **!** marks a quest to pick up

### Guides and suggestions

| | |
|---|---|
| **Cozy Sleeping Bag chain** | Follows the secret quest chain step by step, makes the next spot **stop 1** whenever you are in its zone, and gives directions for getting there (`/lrxp bag`). |
| **Class quests** | Finds the quests only your class can take, announces new ones as you level, and shows where to get them (`/lrxp class`). |
| **Dungeons** | Which of your quests need a dungeon, where its entrance is, and which dungeons suit your level (`/lrxp dungeons`). |
| **Next zone** | When you outgrow a zone it suggests where to go for your level (`/lrxp nextzone`). |

### Collections and timers

| | |
|---|---|
| **Library books** | All the world-collection books with waypoints, a zone alert, a level filter, collected tracking, map pins and party sharing. Includes a **Titan Panel / LibDataBroker** button with a drop-down to track any book. |
| **Flight timer** | Learns how long each flight takes the first time you fly it, then counts down (and shows the time on the flight map). |
| **Hunter pet reminder** | Tells you when your pet is unhappy or missing and what it eats. |

### Party sharing

Send waypoints and whole book routes to your party. Receivers can accept or ignore them, and it stays quiet
for people who do not have the addon.

## Install

1. Download this repository (**Code → Download ZIP**) or clone it.
2. Copy the **`LazyRestedXPTracker`** folder (the one inside the repo) into:
   `World of Warcraft\_forever_\Interface\AddOns\`
3. Start the game. Adding the addon the first time needs a full restart, later updates only need `/reload`.

## Getting started

- Type **`/lrxp`** to open the options. Settings are grouped into pages on the left of the AddOns settings.
- Follow a friend: ask them to turn on RestedXP's party sharing. Their arrows show up by themselves.
- No friend? Click **Plan my route** (or `/lrxp plan`) and follow the blue arrow.

## Commands

| Command | What it does |
|---|---|
| `/lrxp` | Open the options |
| `/lrxp both` `quest` `friend` `off` | Choose which arrows show |
| `/lrxp lock` `unlock` `scale <n>` `reset` | Move, resize and reset the arrows |
| `/lrxp way <x> <y> [name]` `here` `list` `next` `remove <n>` `clear` | Waypoints |
| `/lrxp plan [all]` | Plan the most efficient route (add `all` to include other zones) |
| `/lrxp own` | Toggle the "my quests" arrow |
| `/lrxp compass` | Toggle the compass bar |
| `/lrxp books` `zone` `turnin` `list` `done` `share` `say` | Library book collection |
| `/lrxp arrow` | Toggle the book waypoint arrow |
| `/lrxp class` `class go [n]` | Class quests |
| `/lrxp dungeons` `dungeons go [n]` | Dungeon quests and entrances |
| `/lrxp bag` `bag all` `bag start` `bag done` | Cozy Sleeping Bag chain |
| `/lrxp nextzone` `nextzone go` | Where to level next |
| `/lrxp pet` `pet test` | Hunter pet reminder |
| `/lrxp flight` | Flight times learned so far |
| `/lrxp status` `panel` `minimap` | Info, step panel, minimap button |

## Notes

- Quest data, dungeon entrances and class quests come from **Questie's** database, so those features need Questie.
- It is under active development and some parts have only seen light testing in-game. Bug reports are very welcome:
  please include what you did, what you expected, and any Lua error text.
- Level ranges for zones, the dungeon list and the secret-chain coordinates were collected from the community
  guides and may be slightly off. Open an issue if you find a bad spot.

## Credits

Built on [HereBeDragons](https://www.curseforge.com/wow/addons/herebedragons), AceComm, AceSerializer,
CallbackHandler, LibDeflate and LibStub (all in `LazyRestedXPTracker/libs`, under their own licences).

Not affiliated with or endorsed by RestedXP, Questie, Blizzard Entertainment or the WoW Forever team.

## Licence

[MIT](LICENSE)
