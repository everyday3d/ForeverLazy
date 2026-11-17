<p align="center">
  <img src="docs/banner.svg" alt="Forever Lazy" width="100%">
</p>

<p align="center">
  <img alt="Game" src="https://img.shields.io/badge/WoW-Forever-4db8ff?style=for-the-badge">
  <img alt="Interface" src="https://img.shields.io/badge/interface-16001-ffd94d?style=for-the-badge">
  <img alt="Version" src="https://img.shields.io/badge/version-0.8.2-6bd16b?style=for-the-badge">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-ff9ad5?style=for-the-badge">
</p>

<p align="center"><b>Never think about where to go next.</b><br>
A levelling companion for WoW Forever. One button tells you what to do and points the way.</p>

---

## What it does

Click the minimap button (or type `/lazy now`) and **Forever Lazy** points an arrow at the best next thing: your next
quest stop, a vendor when your bags are full, your trainer, or the next zone, with a full trip by flight path,
boat and hearthstone if it is far.

## Highlights

| | |
|---|---|
| **Lazy Mode** | One press points at the best next thing. |
| **Quest route planner** | An XP-efficient route through your quest log, with what to do at each stop. |
| **Take me there** | `/lazy go <place>` plans a whole trip by flight, boat, tram and hearthstone. |
| **Crafting** | What to craft next, materials counted from your bags and bank, and where to get the rest. |
| **Buttons in the game windows** | A menu, a world map search box, quest log buttons and a craft panel, so you rarely type. |
| **Duo mode** | Two players with the addon level together: shared plan, partner on the compass. |

Plus a journey to 60, class quests, dungeons, gathering and fishing routes, library books and more.
Every part can be switched off, and presets set it up in one click. See the [full feature guide](docs/FEATURES.md).

> **[Questie](https://www.curseforge.com/wow/addons/questie) is highly recommended for added functionality.**
> It powers the quest planning, class quests, services and crafting sources.
>
> **Early test builds.** Releases are marked *pre-release* because a lot of the code has had little in-game testing.
> If something looks wrong, type `/lazy check` and paste the result into an [Issue](../../issues).

## Install

1. Download the latest zip from [Releases](../../releases).
2. Put the **`ForeverLazy`** folder in `World of Warcraft\_forever_\Interface\AddOns\`.
3. Restart the game. A welcome window opens the options; `/lazy` opens them any time.

## Learn more

- [Feature guide](docs/FEATURES.md): everything it can do
- [Commands](docs/COMMANDS.md): the full list (most things are also a click)
- [Teaching it a boat dock](docs/BOATS.md)
- [What it sends to other players](docs/PRIVACY.md)
- [Changelog](CHANGELOG.md)
- Questions: [Discussions](../../discussions). Bugs: [Issues](../../issues)

## Credits and licence

Built on HereBeDragons, AceComm, AceSerializer, CallbackHandler, LibDeflate and LibStub. Data from **Questie** and the
[wowforever.be](https://wowforever.be/guides/flight-paths/) flight path guide. The welcome photo of Sam Kinison is by
The World Famous Comedy Store, via Wikimedia Commons, [CC BY-SA 2.0](https://creativecommons.org/licenses/by-sa/2.0/)
(see `ForeverLazy/media/CREDITS.txt`). Not affiliated with RestedXP, Questie, Blizzard Entertainment or the WoW Forever team.

[MIT licence](LICENSE)
