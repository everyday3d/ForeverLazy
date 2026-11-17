<p align="center">
  <img src="docs/banner.svg" alt="Forever Lazy" width="100%">
</p>

<p align="center">
  <img alt="Game" src="https://img.shields.io/badge/WoW-Forever-4db8ff?style=for-the-badge">
  <img alt="Interface" src="https://img.shields.io/badge/interface-16001-ffd94d?style=for-the-badge">
  <img alt="Version" src="https://img.shields.io/badge/version-0.11.1-6bd16b?style=for-the-badge">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-ff9ad5?style=for-the-badge">
</p>

<h2 align="center">Stop alt-tabbing to guides.<br>Press one button and go.</h2>

<p align="center">
Forever Lazy is a levelling companion for WoW Forever that does the thinking for you.<br>
It knows your quests, your bags, your professions and the map, and it points an arrow at the next thing worth doing.
</p>

---

## A level 20 on a Tuesday night

You log in with a full quest log and no idea where to start. You click the minimap button.

- The arrow points at the **quest stop that earns the most XP for the walking**, with a note on what to do there.
- Your bags fill up, so the next click sends you to the **nearest vendor**.
- The next quest is two zones away, so it plans the **flight path, the boat and the hearthstone** for you.
- Your skill is stuck at 56, so it lights up **the exact recipe to craft** in your profession window and tells you how many.

No spreadsheets. No second monitor. No typing, unless you want to.

<p align="center">
  <img src="docs/recipe-highlight.jpg" alt="The recipe to craft next glows in the profession window with a craft 19 badge" width="620"><br>
  <i>The recipe to craft next glows in your own profession window, with how many to make.</i>
</p>

<p align="center">
  <img src="docs/world-map-route.jpg" alt="The planned route drawn on the world map, with a Go to box and a Lazy button" width="620"><br>
  <i>Your route drawn on the world map, with a "Go to..." box and a Lazy button built in.</i>
</p>

## New: it learns from how you play

- **The Coach** looks at the quests here, the best mob to grind and the other zones, ranks them by **your measured XP per
  hour**, and tells you the best thing to do right now. Each line says what it rests on, and a button sets it up.
- **The Hive** (off until you switch it on) measures your real pace, drop rates, quest times and where quest objectives are
  really done. Turn it on to share those numbers with other players who have it on, so a new player starts with real data,
  rare spawns show up as pins on the map, and the planner stops trusting spawn data made for a different server.
  It only ever sends ids and numbers, never your name. [How it works and what it sends](docs/HIVE.md).
- **Far-off quests use flights by themselves**: the arrow points at the flight master and says where to fly.
- **The plan finishes an area before handing in**, unless a hand-in opens the next quest of a chain.
- **A levelling guide** for your whole journey to 60, with text that scales for the couch and TV.

## What you get

| | |
|---|---|
| **One-button Lazy Mode** | Click, and the arrow points at the best next thing: quest, vendor, trainer, or the next zone. |
| **A route that respects your time** | Your quest log planned for XP per minute, with stops numbered on the world map. |
| **Take me there** | Type a place and get a whole trip by flight, boat, tram and hearthstone. |
| **Crafting that tells you what to make** | The recipe to craft next glows in your recipe list with a count, using what is in your bags and bank, and says where to get the rest. |
| **Buttons where you already look** | A menu on the minimap, a search box on the world map, buttons on the quest log. Nothing to memorise. |
| **The Coach** | Compares the quests here, the best grind and other zones by your measured XP per hour and tells you the best thing to do now. |
| **A levelling guide** | Your whole journey to 60 in one window, with your pace and the dungeons that fit. Its text scales for the couch and TV. |
| **The Hive** | Learns from real play (your pace, drops, quest times, where objectives are done) and, if you turn it on, shares those numbers with other players. Off until you switch it on. |
| **One arrow, your choice** | Right-click it to pick what it points at: what is next, your plan, a quest, your partner, a library book. |
| **Duo mode** | Level with a friend who has the addon: shared plan, partner on your compass. |

And more: class quests, dungeon levels, gathering and fishing routes, library books, item tooltips that count your bank and your other characters, hunter ammo and pet reminders, a Titan Panel button, a first-run tour.
See everything in the [feature guide](docs/FEATURES.md).

## It does not get in your way

- **Every part switches off.** Want only the arrow? One click.
- **Presets** set it up in seconds: Minimal, Leveler, Duo or Full.
- **Private.** By default it only talks to your own group or guild. The Hive, which shares numbers with other players, is off until you turn it on, and it only ever sends ids and numbers. See [what it sends](docs/PRIVACY.md).
- **Free and open source**, MIT licensed.

<p align="center">
  <img src="docs/options-list.png" alt="Forever Lazy's options pages: Presets, Modules, Lazy mode, Journey, Arrows and more" width="240"><br>
  <i>Every part has its own page in the game's options.</i>
</p>

## Install in a minute

1. Download the latest zip from [**Releases**](../../releases/latest).
2. Drop the **`ForeverLazy`** folder into `World of Warcraft\_forever_\Interface\AddOns\`.
3. Start the game. A welcome window walks you through it, and `/lazy` opens the options any time.

> **Get [Questie](https://www.curseforge.com/wow/addons/questie) too.** Forever Lazy uses its quest data to plan routes,
> find class quests and vendors, and work out where to get crafting materials.

## Early days, and I want your feedback

This is a young addon built by one player who levels with it. It works, and it is getting better fast, but some
corners have had little testing. If something looks wrong, type `/lazy check` and paste the result into an
[Issue](../../issues). Ideas and questions are welcome in [Discussions](../../discussions).

## Learn more

[Feature guide](docs/FEATURES.md) · [Commands](docs/COMMANDS.md) · [The Hive](docs/HIVE.md) · [Teaching it a boat dock](docs/BOATS.md) · [Privacy](docs/PRIVACY.md) · [Changelog](CHANGELOG.md)

## Credits and licence

Built on HereBeDragons, AceComm, AceSerializer, CallbackHandler, LibDeflate and LibStub. Data from **Questie** and the
[wowforever.be](https://wowforever.be/guides/flight-paths/) flight path guide. The welcome photo of Sam Kinison is by
The World Famous Comedy Store, via Wikimedia Commons, [CC BY-SA 2.0](https://creativecommons.org/licenses/by-sa/2.0/)
(see `ForeverLazy/media/CREDITS.txt`). Not affiliated with RestedXP, Questie, Blizzard Entertainment or the WoW Forever team.

[MIT licence](LICENSE)
