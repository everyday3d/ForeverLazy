# Changelog

## 0.13.0
- **Level a whole zone** (`/lazy level`, or `/lazy level ashenvale` to be taken there first): one plan from your quests plus every quest worth taking in the zone, and a window that says what to get and from whom, where to kill or collect, and what to hand in. It keeps quests of an area open and hands them in together, unless a hand-in opens the next quest of a chain.
- **Ask a guard, get an arrow**: when a guard points you to a trainer, the bank or the inn, the arrow guides you there, plan on or off, and goes away when you arrive.
- **Class quests**: a pop-up once when you enter a zone where a class quest needs something (who to get it from, where to kill, what to hand in), `/lazy class quest` for a window of every class quest and what to do for it, and `/lazy class here` for the zone you are in.
- **No dungeon quests in any plan**, found from the game's own Dungeon tag and Questie's data, including the same quest under a second id. A finished one can still be handed in.
- **The plan follows you between continents**: it rebuilds after a hearthstone, boat, tram, zeppelin or portal, and puts away stops left on the other continent.
- **Hand-ins near you come first**: walk close to a quest you can hand in and the plan puts it next.
- **Crafting**: the craft plan stops where your profession trainer next has something and plans one batch at a time, because training changes the best recipe.
- **Protected items**: a protected item that gets sold anyway shows a big message in the middle of the screen. The tooltip warning is bigger.
- **Nodes**: pins show the same hover tooltip on the minimap, fade while a node should be respawning, and stay faint with Find Minerals or Find Herbs on so the real blip shows. When the arrow farms nodes, the route is drawn on the map and minimap.
- **Fixes**: a stop for a quest you have not finished stays until its objectives are done (arriving is not enough, so it no longer sends you to hand in early); skipping a quest takes it out of your plan at once; the arrow menu keeps its skip option when another stop is in front; leftover stops from a "Show me" or `/lazy class go` no longer stay on the arrow; the craft panel no longer covers the profession tabs.

## 0.12.0
- **Ore and herb nodes** (`/lazy nodes`): every node you mine or pick is remembered and marked on the world map and the minimap, as a round pin showing the ore (copper, tin, silver and so on). Hover a pin for what it is and when you last found it. A node you just emptied fades until it should be back, and with Find Minerals or Find Herbs on, the minimap pins stay faint so the game's own blip shows through. The arrow can **farm** them (`/lazy nodes farm ore`, or right-click the arrow): it walks you from node to node, with the route drawn on the map and minimap.
- **Find a node by name** (`/lazy nodes silver`): a window lists the zones that have it, from Questie's data and from your own finds, each with a Take me there button.
- **Turn the plan off and keep your place** (`/lazy plan off`, `/lazy plan on`, the arrow menu, or Options): the stops still to do are put aside, the route lines, numbered markers, XP heat and quest item bar go away, and nothing replans on its own. Turning it on puts the stops back.
- **Protect items from vendors** (`/lazy keep <item>`): your Cozy Sleeping Bag is protected from the start. The tooltip says DO NOT SELL, opening a vendor lists protected items in your bags, and one that gets sold anyway is bought back at once.
- **Fix:** the craft plan panel no longer sits on top of the profession window's tabs (it can also be dragged, and Shift + right-click puts it back).- **A damage meter in its own chat tab** called Meter (`/lazy meter`), so it stays out of the way. It reads the game's built-in damage meter, so no other addon is needed. Choose what to show (damage per second, damage done, healing, damage taken, interrupts, deaths), this fight or everything since the last reset, and how many players to list. In combat the game hides the numbers from addons, so it keeps the last picture until the fight ends. If a chat tab cannot be made it falls back to a small window.
- **Fights and deaths in the Hive**: how long each kind of mob takes to kill and how much damage it costs you (in `/lazy grind` and the Coach), and where players die, with a warning when you walk into a place where people keep dying (`/lazy danger`). Deaths are shared as coarse map squares only, never names.
- **Fixes** since 0.11.2: a leftover trip stop can no longer stay on the arrow after a reload or a cancelled trip, a trip you walk away from cancels itself, trips by tram, boat or flight finish properly, the automatic flight trip is now off by default, the plan rebuilds when you move somewhere else in the zone, and learned quest spots no longer replace a closer valid one. `/lazy plan debug` and `/lazy go steps` show what the planner and the trip are working from.
## 0.11.2
- **Fix: trip steps by tram, boat or flight** now finish when the ride has taken you away from where you boarded (or you are back out of the tram's own area). Before, the Deeprun Tram step could stay open and the arrow kept pointing back at the boarding spot.

## 0.11.1
- **Fix: the measured XP per hour was too high.** A big quest hand-in after a long walk used to count as 30 seconds of play. The time since your last XP now counts, up to 15 minutes. If your Coach or guide shows a pace that looks far too high, `/lazy pace reset` clears the old numbers (your drop counts and quest times are kept).

## 0.11.0
- **The Coach** (`/lazy coach`, "Ask the Coach" in the menus): compares doing the quests here, the best grind and other zones by measured XP per hour, and says what is best right now, with a button for each that sets it up. Every line says what it rests on. The guide shows what the Coach says.
- **Real quest spots**: with the Hive on, the addon records the map square where each quest objective counted up (and shares it with other Hive players). Once a quest has enough sightings, the plan and arrow use those places instead of the original game's spawn data. An option turns it off. Grind advice can now point at where you killed a mob most.
- **Far-off plan stops use flights by themselves**: when the next stop is more than about 1,500 yards away and a flight is quicker, the trip starts on its own (flight master, where to fly, then the quest). An option turns it off.
- **Fix:** a quest handed in out of the plan's order (or dropped) is now taken out of every plan stop at once, wherever it is in the list, so the arrow no longer sends you back to a quest giver you have already seen.
- Privacy wording updated: the only places shared are rare sightings and coarse map squares for quest objectives, never a track of where you are. See [docs/PRIVACY.md](docs/PRIVACY.md).
## 0.10.2
- **The plan batches quests by area**: it finishes the quests around here before walking back to hand any in, unless handing one in opens the next quest of a chain. An option turns it off.
- The what's new window has Sam on it (credited, CC BY-SA 2.0).

## 0.10.1
- **Fix: the craft plan panel** beside the profession window could be missed when another addon loaded the professions window first. It now appears whenever a profession window is open, and says in chat why if it cannot.

## 0.10.0
- **The Hive**: the addon learns from real play and players who have it on share what they measured. One switch (Options > The Hive, or `/lazy hive on`), off until you turn it on.
  - **Your real pace**: XP per hour per zone and level (`/lazy pace`), shown in the guide with your fastest zone lately and the time to your next level.
  - **Real drop rates**: every corpse you loot is counted. `/lazy drops <item>`, item tooltips and the crafting plan's "where to get it" use the mobs actually seen dropping things.
  - **Real quest times**: each quest is timed from accept to turn-in (`/lazy pace quests`). Quests that were slow for you are marked in the skip menu.
  - **Best grind** (`/lazy grind`): XP per hour for each kind of mob, counting the time between kills, near your level, also shown in the guide.
  - **Rare timers**: the pin of a rare that died stays as a timer, with how long it usually takes to come back, learned from deaths and later sightings, and a line in chat when it should be back.
  - **Session report** (`/lazy session`): XP, XP per hour, quests, kills and gold this session.
  - **Shared numbers**: with the Hive on, drop counts, quest times and zone paces are exchanged with other players over a hidden channel and added to your own, so the numbers are good from the first day. Rare spawns show as pins on the world map, and the map says how many other Forever Lazy players are in a zone.
  - It only ever sends ids and numbers, never your name, guild, items or chat, and never a track of where you are. See [docs/HIVE.md](docs/HIVE.md) and [docs/PRIVACY.md](docs/PRIVACY.md).
## 0.9.2
- **Item tooltips know your stock**: hover an item and it says how many you have in your bags, bank, mail and worn, what each of your other characters has, and what is in your guild bank (as of the last time you opened them). `/lazy has <part of a name>` lists it. Options turn it off.
- **Hunters**: a warning when ammo runs low (you choose how low), and a reminder when a better kind of arrow or bullet opens up for your level.
## 0.9.1
- The arrow's right-click menu can now point at **the nearest library book** (one you do not have yet, skipping zones too far above your level).

## 0.9.0
- **The levelling guide** (`/lazy guide`): your journey to 60 in one window, with where you are, the quests worth doing in each stretch, the dungeons that fit, and a Take me there button per stretch. The whole window scales for the couch and TV (A-, A+, TV buttons, `/lazy guide tv`, or a slider in the options).
- **XP hot spots**: an optional, light heat layer on the zone map (the XP button, or `/lazy xpmap`) showing where the quests worth doing for your level are, with the hottest spot spelled out.
- **One arrow, your choice**: right-click the arrow to pick what it points at: what is next (automatic), my plan or trip stop, my nearest quest, my partner or friend, or my friend's quest target. It switches at once, and the choice is kept.
## 0.8.9
- **Hunter pets get a scream**: a huge red, shaking FEED ME!!! across the screen when your pet needs feeding (an option turns it off).
- Your own sound for the pet reminder: put `feedme.ogg` or `feedme.mp3` in `ForeverLazy/media/custom/` and it plays instead of the raid warning. That folder is never part of the addon download.

## 0.8.8
- **New zone offer**: once you have stayed in a new zone for a bit, a small box offers to plan it (Plan it, Not now, Not in this zone). It does not appear while you are just passing through, on a flight, in a town or dungeon, or when every quest there is red or grey. There is an option to turn it off.

## 0.8.7
- **One button for Titan Panel** (and any LibDataBroker bar): an icon, your next stop with its distance, and the whole menu opens when you hover over it.
- **Your route on the minimap**: numbered stops joined in order, and trips are drawn on both the world map and the minimap, with flights, boats, the tram and walks in different colours.
- **Far-off stops use flights**: when the quickest way to a stop includes a flight, Lazy Mode points at the flight master, says where to fly, and the flight map rings that destination.
- Lazy Mode **skips the trainer when there is nothing to learn**, learning from your trainer visits.
- Collected library books now lose their book icon and show the green tick, and picking one up is recognised more reliably.
## 0.8.6
- **A custom minimap button**: a Sam Kinison icon (credited, CC BY-SA 2.0), with a tooltip that matches what the clicks do.
- The services menu on the arrow adapts to where you are: in a city it offers every service in that city, in the open world only those within about 900 yards.
- The what's new window scrolls, so a long history never runs off the screen.

## 0.8.5
- **Right-click the arrow** for a short menu: **Services near me** (repair, inn, bank, auction house, mailbox, flight master, trainers and more, listing only those within 500 yards, with distances), skip this quest stop or do it next, and Lazy Mode.
- The addon's macros now have their own icons instead of a question mark, and macros from older versions are renamed to Lazy ... on login.

## 0.8.4
- **The old LRXP name is gone.** Commands are `/lazy` (`/forever` too), macros are called Lazy ..., window and key binding names are Forever Lazy's own. Your settings and old macros carry over on their own; `/lrxp` still works as a quiet alias. If you had keys bound under the old binding names, bind them again in Key Bindings > Forever Lazy.

## 0.8.3
- **Fixes found by testing in the game:** crafting no longer stops on an event this client does not have, the window buttons file loads again, and the missing item functions are replaced.
- The craft plan reads your recipes from the newer professions window, lights up the recipe to craft next in the window's list, and has **Plan it** and **Show it** buttons.
- `/lazy check` names any file that failed to load, `/lazy windows` reports which windows were found, and a command that hits an error shows it in chat.
- The next-zone data is shared correctly again (journey, trips and Lazy Mode's zone step).

## 0.8.2 (pre-release)
- **Buttons and menus in the game windows**: a menu on the minimap button, a search box on the world map, buttons under the quest log, a craft plan beside the profession window, bank highlights, flight map and boat NPC buttons.
- Numbered stop markers on the route drawn on the world map.
- A **first-run tour**, **settings export and import**, and a **what's new** window.
- A new welcome window with a photo (CC BY-SA 2.0, credited).

## 0.8.0 (pre-release)
- **Take me there**: `/lazy go <place>` plans a whole trip (flight points, boats and zeppelins, the Deeprun Tram, hearthstone, walking). Lazy Mode uses it when the next zone is far.
- Every Forever flight master position is built in (from the community flight path guide); the addon learns which flight points you have opened.
- Boat routes updated for Forever's new ones; a dock that has not been taught falls back to the port town's flight master.

## 0.7.0 (pre-release)
- **Lazy Mode** (`/lazy now`), **simple arrows** (one main arrow, the rest on the compass).
- **Crafting** (with enchanting) counting bags and bank, **gathering routes**, **fishing spots**.
- **Journey** (saved, with Generate and Regenerate), **quest helpers** (item button, chain, reward pick, farm).
- **Duo mode** that starts by itself, plan window with the route on the world map, version note.
- **Modules and presets**, `/lazy check`.
- Hearthstone and flight points, services and trainers, boats and zeppelins, class quests, dungeons, group quests, shared quests, plan sharing.

## 0.6.0
- Renamed to **Forever Lazy** (was Lazy RestedXP Tracker). RestedXP is optional and off by default.
- Follow arrow for any group member, boats, service search, welcome window and macros, right-click skip menu.

## 0.5.x
- Route planner, library books, Sleeping Bag guide, class quests, dungeons, corpse arrow, flight timer, pet reminder.
