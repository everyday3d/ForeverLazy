# Changelog

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
