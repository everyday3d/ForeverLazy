# Forever Lazy: STOP ALT-TABBING TO GUIDES!! PRESS ONE BUTTON AND GO!!!

**Forever Lazy** is a levelling companion for **WoW Forever** that does the THINKING for you!! It knows your quests, your bags, your professions and the MAP, and it points an ARROW at the next thing worth doing. OHHHHH!

**No Questie needed.** Forever Lazy carries its own quest data. If you do run Questie, OpenMap or Bagnon, it plays nicely with them. If Forever Loot Sparkles or tullaRange are installed, those do their job and Forever Lazy stays out of the way.

---

## What you get

### THE ARROW AND THE PLAN
- **A route planner** that puts your quests in a smart order: XP for the time it takes, nearby quests counted, the little ones left out.
- **An arrow that points at the nearest kill or collect spot,** stays in the zone you are in, and moves on when you have cleared it.
- **Close hand-ins come first:** a finished quest you can hand in nearby goes before anything else (not the ones back in town). The arrow says why it points where it does.
- **Level a whole zone** with `/lazy level`: what to get, from whom, where to kill or collect, and what to hand in.
- **Autopilot** for vendor and trainer stops. The plan follows you across zones, boats, trams and flights.
- **Dungeon help:** walk into a dungeon and it shows what your quests need in there.
- **A Hunt panel** with a button for every mob your quests need: click one to target it and put a skull on it.
- **Your own quest tracker** that can replace WoW's, with plan order, XP, live objectives and who to turn in to. Click opens the quest, shift-click does it next, ctrl-click shares it.

### A GEAR ADVISOR
- **Hover any item** and a green line says if it is an upgrade for your class and spec, and by how much. Stat priorities come from the WoW Forever lists for all 27 specs.
- **A green ^** on upgrades in the bag window and at vendors, and an optional **gear bar** (off until you turn it on) with a button that equips an upgrade from your bags when you click it. It never equips by itself.
- **Quest rewards** get a star on the best pick, scored the same way.
- **Quest item sparkles** keep the game's own sparkle on quest items you can loot, even after a graphics preset.
- **Range colours** (off until you turn them on): action buttons turn red out of range, blue without mana, grey when unusable.

### THE QUEST MAP
Skulls where you kill it, diamonds where it drops, a yellow **!** for quests to pick up and a yellow **?** for hand-ins, plus coloured areas so you can SEE where to go. Click a pin and the arrow goes THERE. Works on OpenMap's big map too.

### A BETTER BAG (off by default: turn on "Replace game bags" in the options, or open it any time with /lazy bags)
- All your bags in ONE window, with search, quality borders, item levels, free slots and money.
- Real sections that only appear when you carry something for them: Travel, Quest, Equipment, Food and drink, Potions, Trade goods and more. Your Hearthstone sits at the very top.
- **The bank opens side by side with your bags,** so moving things across is easy.
- Look inside the bags, bank and mail of your OTHER characters.

### NAMEPLATES, TOOLTIPS AND MORE
- A **sword** on mobs you need to kill, a **loot bag** on mobs that drop what you need, and a gold **!** on mobs that drop a quest starter.
- **Interrupt marker:** a casting mob shows its spell. Green means your interrupt is ready, red means cooldown, grey means you have none.
- **Quest item bar** (off until you tick it): stand where a quest wants an item used and a button with the item pops up.
- **New spell rank?** It takes the old rank's place on your action bars, by itself.
- **Tooltips that talk:** hover a mob, item or NPC to see which quest it is for, how far along you are, and the real drop chances.
- **Nameplate colours** (off until you turn them on): an aggressive mob is red even before it attacks you, one fighting someone else orange, and a quest mob that is idle purple.
- **Paladin blessings:** one button blesses the next player who needs it, and you choose the blessing for each class. Paladins with Forever Lazy share their choices so you do not double up, and a Split button picks blessings the others are not giving.
- **Group finder filter:** a button on the group finder opens a list of what your search found, with drop-downs for groups or lone players, the role a group still needs (find the group that only needs a healer), how new it is and the sort order, plus word search. Click a row to whisper the leader.
- **A pedometer** that counts how far you walk on foot: today, this level, in total.
- **A damage meter** in its own chat tab laid out like Details: class icon, rank, name, a bar, and total, per second and percent. It uses the game's built-in meter, with every move a player used when you hover. Optional live bars (off until you turn them on) move over the tab while you fight.
- **Tell the party** when you finish a quest, job's done sounds, couch mode, talent reminders, ore and herb node memory, an item protector so you never sell your sleeping bag, and chat tweaks (all off until you turn them on).

---

## Getting started
1. Download **ForeverLazy-x.y.z.zip** from the Files tab.
2. Put the **ForeverLazy** folder in `World of Warcraft\_forever_\Interface\AddOns\`.
3. Log in. A welcome window walks you through it, and `/lazy` opens the options any time (the minimap button works too).

Handy commands: `/lazy` (options), `/lazy plan` (build a plan), `/lazy level` (plan the whole zone), `/lazy gear` (what you are scored as), `/lazy bags` (open the bag window), `/lazy meter` (damage meter), `/lazy report` (a bug report).

## Good to know
- Free and open source (GPL-3.0).
- Settings live in the Options window, which opens on a **Start here** page (Just point me, Leveler, Duo, Everything) and shows only the basics until you ask for more. You rarely have to type a command.
- Want it in your language? Every text can be translated: see [docs/LOCALIZATION.md](https://github.com/everyday3d/ForeverLazy/blob/main/docs/LOCALIZATION.md). `/lazy l10n` shows the state.
- Something wrong? /lazy report makes a bug report you can copy, and /lazy commands lists every command.
- Bugs and ideas: https://github.com/everyday3d/ForeverLazy

## Credits
Quest, NPC, item and drop data comes from [Questie](https://github.com/Questie/Questie) (GPL-3.0), an excellent addon, and Forever Lazy would not exist without their work. Quest item sparkles follow [Forever Loot Sparkles](https://www.curseforge.com/wow/addons/forever-loot-sparkles) by Ashtar Senior (GPL-3.0), and range colours are adapted from [tullaRange](https://github.com/tullamods/tullaRange) by Tuller (MIT). Built on HereBeDragons, AceComm, AceSerializer, CallbackHandler, LibDeflate and LibStub. Flight path info from the [wowforever.be](https://wowforever.be/guides/flight-paths/) guide. Not affiliated with Blizzard Entertainment or the Questie team.

*Brought to you by Sam Skinison and Tank Hanks.*
