<p align="center">
  <img src="docs/banner.svg" alt="Forever Lazy" width="100%">
</p>

<p align="center">
  <img alt="Game" src="https://img.shields.io/badge/WoW-Forever-4db8ff?style=for-the-badge">
  <img alt="Interface" src="https://img.shields.io/badge/interface-16001-ffd94d?style=for-the-badge">
  <img alt="Version" src="https://img.shields.io/badge/version-0.8.2-6bd16b?style=for-the-badge">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-ff9ad5?style=for-the-badge">
</p>

<p align="center"><b>Never think about where to go next.<br>
A levelling companion for WoW Forever: it plans your quests, your trips and your crafting, and points the way.</b></p>

---

## What it does

**Forever Lazy** looks at your character and tells you what to do next, and where. One arrow points at the next
stop; the line under it says exactly what to do there. Press one key (**Lazy Mode**) and it decides for you:
sell and repair, visit your trainer, follow your quest route, or head for the next zone, planning the whole trip
with flight paths, boats and your hearthstone if the zone is far.

> **[Questie](https://www.curseforge.com/wow/addons/questie) is highly recommended for added functionality.**
> Forever Lazy runs without it, but the route planner, quest arrows, class quests, dungeon quests, service and
> trainer search, crafting sources and the text under the arrow all use Questie's quest and NPC database.
> Without Questie you keep waypoints, books, the follow arrow, trips by flight and boat, timers and the pet reminder.

> **Status: early test builds.** The newest releases are marked *pre-release* because a lot of the code has had
> little in-game testing. If something looks wrong, type `/lazy check` and paste what it says into an
> [Issue](../../issues).

## Quick start

1. Download the latest zip from [Releases](../../releases) and put the **`ForeverLazy`** folder in
   `World of Warcraft\_forever_\Interface\AddOns\`. Restart the game (a full restart the first time, `/reload` for
   small updates).
2. A welcome window opens the options on your first login. `/lrxp`, `/forever` or `/lazy` open them any time.
3. Pick a **preset** at the top of the options (Minimal, Leveler, Duo, Everything), or switch modules on and off one by one.
4. Press **Plan my route**, or just type `/lazy now`.

## Features

### Quests and routes

- **Route planner** (`/lrxp plan`): stops that pay the most XP for the least walking come first; quests that overlap
  are done in one visit and every turn-in comes after its objectives. Green, yellow and orange quests count, red
  only as a turn-in, grey never. It stays in your zone, replans when a quest or objective is finished or you
  change area, and when nothing of yours is in the zone it routes you to the nearest quest givers.
- **Says what to do**: the line under the arrow reads your quest log (*Kill 5 more Defias Pillager (3/8)*,
  *Turn in X to Y*). A gold **?** marks a turn-in and a **!** a quest to pick up.
- **Right-click the arrow** to skip a quest or stop, or pick any quest to do next. The plan resumes once it is done.
- **Plan window** (`/lazy window`): the stops in a movable list, and the route drawn on the world map.
- **Class quests**, **dungeon quests** and entrances, **group quest** handling (green ones are fine solo), and
  the **Cozy Sleeping Bag** secret chain guide.
- **Quest helpers**: a button for quest items, what comes next in a chain, the best quest reward pick, and the
  best place to farm a quest item (`/lazy farm`).

### Lazy Mode and trips

- **Lazy Mode** (`/lazy now`, a key, a macro, or the options button): the best next thing. Bags nearly full or gear
  damaged leads to a vendor; a due trainer visit to your trainer; otherwise your plan, then your journey.
  **Keep going** picks the next one by itself when you arrive.
- **Take me there** (`/lazy go <place>`): plans the whole trip with your flight points, boats and zeppelins, the
  Deeprun Tram, your hearthstone and walking, whichever is quickest, and the arrow follows it leg by leg.
- **Journey** (`/lazy journey`): a saved zone-by-zone route from your level to 60, with the dungeons that fit.
  **Generate** and **Regenerate** buttons in the options.
- **Find a service** (`/lazy inn`, `repair`, `flight`, `bank`, `ah`, `mailbox`, `stable`, `spirit`, `battlemaster`,
  `trainer`, `cooking`...): the nearest one, with the arrow on it.
- **Boats and zeppelins** (`/lazy boat darnassus`), **hearthstone and flight points** (`/lazy hearth`, `/lazy fp`).
  Every flight master's position in Forever is built in; it learns which flight points you have opened.

### Crafting, gathering, collecting

- **Crafting** (`/lazy craft`): reads the recipes you know (enchanting too), says what to craft next, and lists the
  materials counting your **bags and bank**, with where to get what is missing.
- **Gathering routes** (`/lazy herb peacebloom`, `/lazy ore tin`, `/lazy gather`) and **fishing spots** (`/lazy fish`).
- **Library books**: waypoints, zone alerts, collected tracking, map pins, party sharing and a Titan Panel button.
- **Flight timer** (learns each flight), **hunter pet reminder**, a few **macros** (`/lrxp macros`).

### Playing with others

- **Follow arrow**: a purple arrow that points at anyone in your group, with or without the addon.
- **Duo mode**: two players with the addon in a group of two; the party leader's plan is followed by the other,
  shared quests count extra, and your partner shows on the compass. It starts by itself.
- **Share your plan** (`/lazy shareplan`), see **quests you share** (`/lazy party`), and a note when someone in
  your group runs a newer version.

### In the game's own windows

Most things are a click, not a command. The **minimap button** (left-click = Lazy Mode, right-click = a menu with
everything) is the hub. There is a "Go to..." search box on the **world map**, buttons under the **quest log**
(plan my route, do this next, skip this), a **craft plan** beside your profession window, the materials you need
lit up in the **bank**, and buttons on the **flight map** and at boat NPCs. A **first-run tour** shows you where
everything is (`/lazy tour`), settings can be shared as one line (`/lazy export`, `/lazy import`), and a
**what's new** window appears after an update (`/lazy new`).
### Keeping it simple

- **Simple arrows** (default): one main arrow, everything else on the compass bar.
- **Modules**: every part can be switched off in the options. **Presets** set them in one click.
- **`/lazy check`** says if everything loaded and works. Paste it in a bug report.

### Arrows and display

Three arrow styles, colours, size, opacity and position are all yours. Arrows hide in combat, in cities and inns,
on flight paths and inside dungeons and raids (the ghost arrow still shows, and after a death in a dungeon it
points at the entrance for the corpse run). Optional TomTom support.

### RestedXP friends (optional)

If a friend runs RestedXP and shares their step with the party, Forever Lazy can listen and point arrows at their
quest spots and at them. **Off by default**; turn it on under *RestedXP friend (optional)*. You do not need
RestedXP installed yourself.

## Commands

`/lrxp`, `/forever` and `/lazy` all do the same thing.

| Command | What it does |
|---|---|
| `/lazy now` | Lazy Mode: point at the best next thing |
| `/lazy go <place>` `go stop` | Plan and follow a whole trip |
| `/lrxp plan [all]` | Plan the most efficient route (`all` includes other zones) |
| `/lazy window` | The plan window |
| `/lrxp skip` `skip clear` | List or bring back quests you skipped |
| `/lazy journey` `generate` `regenerate` `go <n>` | Your zone-by-zone route to 60 |
| `/lazy inn` `repair` `flight` `bank` `ah` `mailbox` `stable` `spirit` `battlemaster` | The nearest one (add a number for the next) |
| `/lazy trainer` `/lazy cooking` | Class trainer, or a profession trainer |
| `/lazy boat <place>` `boat mark` `boat list` `boat stop` | Boat and zeppelin routes |
| `/lazy hearth` `hearth set` `fp` `fp list` | Hearthstone and flight points |
| `/lazy craft [profession] [goal]` `craft go` `craft bank` | Crafting plan, materials, bank |
| `/lazy herb <name>` `ore <name>` `gather` `fish` | Gathering routes and fishing spots |
| `/lrxp class` `dungeons` `bag` `nextzone` | Class quests, dungeons, sleeping bag chain, next zone (each takes `go`) |
| `/lazy chain` `farm` | Quest chain follow-up, best place to farm |
| `/lrxp follow [name]` `follow off` | Follow a group member |
| `/lazy party` `shareplan` `acceptplan` `duo` | Group features |
| `/lazy net on` `off` | Share boat docks with your guild and group (hidden messages) |
| `/lrxp books` `zone` `turnin` `list` `done` `share` `say` | Library book collection |
| `/lrxp way <x> <y> [name]` `here` `list` `next` `remove <n>` `clear` | Waypoints |
| `/lrxp own` `compass` `pet` `flighttimes` | My quests arrow, compass bar, pet reminder, flight times (`/lazy flighttimes`) |
| `/lrxp lock` `unlock` `scale <n>` `reset` | Move, resize and reset the arrows |
| `/lrxp macros` `macros remove` | Make or remove the addon's macros |
| `/lazy preset minimal` `leveler` `duo` `full` | Switch modules in one go |
| `/lazy check` `/lrxp why` | Health report; explain where the plan arrow comes from |

## Teaching it a boat dock

The game does not tell addons where the docks are. Until a dock is known, the arrow heads for the port town's
flight master (by the harbour) and says so. To teach it the real spot, once:

1. Walk to the dock and **stand on it**, at the spot where you board.
2. Type `/lazy boat mark <port>`, for example `/lazy boat mark menethil`.
3. `/lazy boat <where>` now points at it. `/lazy boat list` shows the docks you taught.

Ports: stormwind, auberdine, rutheran (Teldrassil), menethil, theramore, southshore, ratchet, bootybay, gromgol,
orgrimmar, undercity, steamwheedle, powderfuse. If you taught a dock, please post the line from
`/lazy boat list` as an [Issue](../../issues) or in [Discussions](../../discussions) so it can be built in.

## What it sends to other players

Nothing is ever typed into chat. When you are in a group, the addon sends **hidden addon messages** to other players
who also have it: your quest list (for shared quests), your plan when you share it, and the addon's version number.
**Dock sharing is off by default**; when on, it sends a map and two coordinates to your guild and group. There is no
custom chat channel.

## Help and feedback

Questions and ideas: [Discussions](../../discussions). Bugs: [Issues](../../issues), with what you did, what you
expected, the output of `/lazy check`, and any Lua error text. See the [changelog](CHANGELOG.md) for what changed.

## Data and credits

- Quest, NPC, vendor and drop data: **Questie's** database.
- Flight master positions and boat routes: the community flight path guide at
  [wowforever.be](https://wowforever.be/guides/flight-paths/) (read from the live game files); secret-chain and travel
  details from the Forever guides at method.gg and kami-labs.fr. Zone level ranges are rough and may be slightly off.
- The welcome window photo of Sam Kinison is by The World Famous Comedy Store, via Wikimedia Commons, licensed [CC BY-SA 2.0](https://creativecommons.org/licenses/by-sa/2.0/) (details in ForeverLazy/media/CREDITS.txt).
- Built on [HereBeDragons](https://www.curseforge.com/wow/addons/herebedragons), AceComm, AceSerializer,
  CallbackHandler, LibDeflate and LibStub (all in `ForeverLazy/libs`, under their own licences).

Not affiliated with or endorsed by RestedXP, Questie, Blizzard Entertainment or the WoW Forever team.

## Licence

[MIT](LICENSE)
