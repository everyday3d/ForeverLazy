<p align="center">
  <img src="docs/banner.svg" alt="Forever Lazy" width="100%">
</p>

<p align="center">
  <img alt="Game" src="https://img.shields.io/badge/WoW-Forever-4db8ff?style=for-the-badge">
  <img alt="Interface" src="https://img.shields.io/badge/interface-16001-ffd94d?style=for-the-badge">
  <img alt="Version" src="https://img.shields.io/badge/version-0.6.0-6bd16b?style=for-the-badge">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-ff9ad5?style=for-the-badge">
</p>

<p align="center"><b>Never think about where to go next.<br>
A levelling companion for WoW Forever: it plans your quest route, points the way and guides you through the secrets.</b></p>

---

## What it does

**Forever Lazy** looks at your quest log and tells you what to do next, and where. One arrow always points at the
next stop of an XP-efficient route; the line under it says exactly what to do there. It also guides the
Forever secrets, tracks your class quests, finds dungeon entrances for your quests and collects the world's
library books.

> **[Questie](https://www.curseforge.com/wow/addons/questie) is highly recommended for added functionality.**
> Forever Lazy runs without it, but the route planner, quest arrows, class quests, dungeon quests, service and
> trainer search and the text under the arrow all use Questie's quest and NPC database. Without Questie you keep
> the waypoints, books, follow arrow, boats, timers and the pet reminder.

Nothing in the addon needs RestedXP (see [RestedXP friends](#restedxp-friends-optional)).

## Features

### A route planner that thinks about XP

`/lrxp plan` (or the **Plan my route** button) turns your quest log into the most efficient trip:

- **XP-weighted**: stops that pay the most XP for the least walking come first
- **Does quests together**: spots where several quests overlap are done in one visit, then each turn-in comes after its objectives
- **Colour filter**: green, yellow and orange quests are in, red only as a turn-in, grey never
- **Stays in your zone**: no being sent across the world once you are somewhere
- **Updates itself**: replans when a quest is accepted, an objective or quest is finished, or you enter a new area
- **Nothing to do here?** It routes you to the nearest hub of **quest givers** instead and fills in the objectives as you accept quests
- **Class quests** you can take are slotted in with extra weight
- **Says what to do**: the line under the arrow reads your quest log (*Kill 5 more Defias Pillager (3/8)*, *Turn in X to Y*)
- A gold **?** over the arrow marks a turn-in, a gold **!** marks a quest to pick up
- **Right-click the arrow** to skip a quest or stop, or to pick any quest in the plan to do next. The plan picks up again once it is handed in

### Guides and suggestions

| | |
|---|---|
| **Cozy Sleeping Bag chain** | Follows the secret quest chain step by step, makes the next spot **stop 1** whenever you are in its zone, and gives directions for getting there (`/lrxp bag`). |
| **Class quests** | Finds the quests only your class can take, announces new ones as you level, and shows where to get them (`/lrxp class`). |
| **Dungeons** | Which of your quests need a dungeon, where its entrance is, and which dungeons suit your level (`/lrxp dungeons`). |
| **Next zone** | When you outgrow a zone it suggests where to go for your level (`/lrxp nextzone`). |
| **Find a service** | The nearest innkeeper, repair vendor, flight master, banker, auctioneer, mailbox, stable master, spirit healer, battlemaster, class trainer or profession trainer, with the arrow on it (`/lazy inn`, `/lazy repair`, `/lazy cooking`...). |
| **Boats and zeppelins** | `/lazy boat darnassus` plans the boat route and points at each dock. Docks the addon does not know yet are taught with `/lazy boat mark`. |

### Arrows

| | |
|---|---|
| **Follow a group member** | A separate purple arrow that points at anyone in your party or raid, with or without the addon. Right-click it to change who (`/lrxp follow`). |
| **My quests arrow and compass bar** | Follows the quest you have selected or tracked, with a slim compass bar at the top of the screen. |
| **Waypoints** | `/lrxp way`, Ctrl + right-click the world map, minimap and world-map pins, optional TomTom support. |
| **Three arrow styles** | Classic, chevron and thick. Colours, size, opacity and position are all yours, and everything is movable. |
| **Smart hiding** | Hide in combat, in cities and inns, on flight paths and **inside dungeons and raids**. |
| **Ghost arrow** | When you die, one arrow points at your body. Die in a dungeon and it points at the **dungeon entrance** for the corpse run. |

### Collections and timers

| | |
|---|---|
| **Library books** | All the world-collection books with waypoints, a zone alert, a level filter, collected tracking, map pins and party sharing. Includes a **Titan Panel / LibDataBroker** button with a drop-down to track any book. |
| **Flight timer** | Learns how long each flight takes the first time you fly it, then counts down (and shows the time on the flight map). |
| **Hunter pet reminder** | Tells you when your pet is unhappy or missing and what it eats. |
| **Macros** | Makes a few shared macros for you (`/lrxp macros`). |

### Party sharing

Send waypoints and whole book routes to your party. Receivers can accept or ignore them, and it stays quiet
for people who do not have the addon.

### RestedXP friends (optional)

If a friend runs RestedXP and shares their step with the party, Forever Lazy can listen and point arrows at their
quest spots and at them. It is **off by default**; turn it on under *RestedXP friend (optional)* in the options.
You do not need RestedXP installed yourself.

## Install

1. Download the latest zip from the [Releases](../../releases) page (or **Code → Download ZIP**).
2. Put the **`ForeverLazy`** folder into:
   `World of Warcraft\_forever_\Interface\AddOns\`
3. Start the game. The first time, it needs a full restart; later updates only need `/reload`.

## Getting started

- A welcome window opens the options the first time you log in. `/lrxp` (or `/forever`, `/lazy`) opens them any time.
- Click **Plan my route** (or `/lrxp plan`) and follow the blue arrow.

## Commands

| Command | What it does |
|---|---|
| `/lrxp` | Open the options |
| `/lrxp plan [all]` | Plan the most efficient route (add `all` to include other zones) |
| `/lrxp skip` `skip clear` | List or bring back quests you skipped from the arrow's right-click menu |
| `/lrxp follow [name]` `follow off` | Follow a group member with the purple arrow |
| `/lrxp class` `class go [n]` | Class quests |
| `/lrxp dungeons` `dungeons go [n]` | Dungeon quests and entrances |
| `/lrxp bag` `bag all` `bag start` `bag done` | Cozy Sleeping Bag chain |
| `/lrxp nextzone` `nextzone go` | Where to level next |
| `/lazy inn` `repair` `flight` `bank` `ah` `mailbox` `stable` `spirit` `battlemaster` | The nearest one, add a number for the next (`/lazy inn 2`) |
| `/lazy trainer` `/lazy cooking` | Class trainer, or a profession trainer (first aid, fishing, mining, ...) |
| `/lazy boat <place>` `boat mark` `boat list` `boat stop` | Boat and zeppelin routes with the dock arrow |
| `/lrxp books` `zone` `turnin` `list` `done` `share` `say` | Library book collection |
| `/lrxp arrow` | Toggle the book waypoint arrow |
| `/lrxp way <x> <y> [name]` `here` `list` `next` `remove <n>` `clear` | Waypoints |
| `/lrxp own` `compass` | Toggle the "my quests" arrow and the compass bar |
| `/lrxp pet` `pet test` | Hunter pet reminder |
| `/lrxp flight` | Flight times learned so far |
| `/lrxp macros` `macros remove` | Make or remove the addon's macros |
| `/lrxp toggle` | Turn the RestedXP friend arrows off and back on |
| `/lrxp both` `quest` `friend` `off` | Choose which RestedXP friend arrows show |
| `/lrxp lock` `unlock` `scale <n>` `reset` | Move, resize and reset the arrows |
| `/lrxp why` | Explain where the plan's arrow comes from (for bug reports) |

## Help and feedback

Questions and ideas: [Discussions](../../discussions). Bugs: [Issues](../../issues), with what you did, what you
expected, and any Lua error text.

## Notes

- Quest data, dungeon entrances, class quests and the service and trainer search come from **Questie's** database, so install Questie for the full experience.
- It is under active development and some parts have only seen light testing in-game.
- Level ranges for zones, the dungeon list and the secret-chain coordinates were collected from the community
  guides and may be slightly off. Open an issue if you find a bad spot.

## Credits

Built on [HereBeDragons](https://www.curseforge.com/wow/addons/herebedragons), AceComm, AceSerializer,
CallbackHandler, LibDeflate and LibStub (all in `ForeverLazy/libs`, under their own licences).

Not affiliated with or endorsed by RestedXP, Questie, Blizzard Entertainment or the WoW Forever team.

## Licence

[MIT](LICENSE)
