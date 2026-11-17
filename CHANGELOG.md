# Changelog

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
  - It only ever sends ids and numbers, never your name, guild, position, items or chat. See [docs/HIVE.md](docs/HIVE.md) and [docs/PRIVACY.md](docs/PRIVACY.md).
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
