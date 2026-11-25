# Changelog

## 0.23.1
### Changed
- **Fresh quest data** from QuestieDB 1.1.6: 1 new quest, about 65 quests changed (quest chains, quest spots, the starter for Tattered Journal), about 1,170 creatures with moved spawns, 4 new objects and 266 changed ones, two corrected drop chances (Thunder Lizard Blood, Super Reaper 6000 Blueprints), faction fixes for Arille Azuregaze, Alfred Copperworth, Paige and Angelique Butler, and 5 new quest XP values. The data files are rebuilt without the game (see tools/README.md).

## 0.23.0
### New
- **Live meter bars in a fight** (off until you turn them on: Live bars while I fight under Damage meter in the options, or `/lazy meter live on`). The game hides damage numbers from addons while you fight, so the Meter tab could only keep its last picture. A game bar can still be handed a hidden number, so for the length of a fight a window of real bars sits over the Meter tab (rank, class colour, name, amount) and moves as you fight. When the fight ends it goes away and the tab shows the full list again. `/lazy meter debug` says what it is doing.

### Changed
- **Range colours are off by default.** The red, blue and grey colouring of action buttons now starts off. Tick Colour action buttons in the options, or type `/lazy range on`, to use it. If you had switched it off yourself, nothing changes for you.

## 0.22.4
### Fixed
- **The Blessings button blessed the same player over and over.** A new blessing takes a moment to show on the player, so the button kept pointing at them (and a quick second click blessed them twice). A blessing you just cast now counts as given for 8 seconds and the button moves on to the next person at once. It also moves on when a cast did not land, and comes back to that player later.
- **A quest key got an item button.** The Dalaran Sewer Key (quest Key to the City) showed a button in the quest item button, the tracker and the quest-giver panel, although it opens a gate when you walk up to it. Keys get no button now (the game's Key items, and quest items named ... Key or Key to ...).

### New
- **/lazy keys show|hide** brings the key buttons back, or hides them again.

### Changed
- **/lazy blessings debug** prints what the button does when you click it only until the next reload, in plain words, and not for good.

## 0.22.3
### Fixed
- **Item tooltips listed one character several times.** A character saved under different realm spellings showed up as extra lines (Bad, Bad Altitude and Bad-CAMWOW US1 Realm 7 PvE) and the total counted it again. Characters are matched by first name and class now, and one copy is listed: yours, or else the one with the full name.

## 0.22.2
### Changed
- **The gear bar is off by default.** Tick Gear bar in the options, or type `/lazy gear bar on`, to bring it back. The green ^ arrows in the bags and at vendors and the Upgrade line in tooltips stay on.

## 0.22.1
### Fixed
- **The pedometer never counted.** The game was asked for your position in a way that kept only the first of its three values, so no step was ever added. The same mistake is fixed in four quest and map spots (the arrow's spot choice in another zone, quest items, the quest map and quest search), where a missing value could cause errors or odd results.
- **Nameplate colours:** an aggressive mob is red before it attacks you (not only in a fight), and a mob fighting someone else is orange instead of yellow.
- **The Blessings button did nothing when clicked.** It casts through a macro now, and it listens for both the press and the release of the click.
- **The blessings panel hid without saying why.** It now says whether it is switched off, you are not a paladin, you are not in a group, you are in combat, or no blessing spells were found, and it no longer says everyone is blessed when no blessing is chosen.
- **The quest tracker listed every quest inside a dungeon** on this server, because it does not label The Stockade as a dungeon. The dungeon is now found by its zone name too, so the tracker, the dungeon arrow, the quest popup and /lazy dungeons here work there. The tracker's title shows the dungeon name.
- **Item tooltips listed your own character twice** when an old copy was saved under another realm name.
- **Green gear arrows were missing** in the standard bag windows (they only showed in the Forever Lazy bag window and at vendors).

### New
- **Group finder filter.** A Filter groups button under the group finder (or /lazy groups) lists what your search found with drop-down filters: groups or lone players, a role a started group still needs, how new the listing is, the sort order, word search and right level for me. Click a row to whisper the leader. /lazy groups button off hides the button.
- **Paladins work together.** Paladins with Forever Lazy share what blessing they give each class. When two give the same one, the one first in the alphabet casts it and the other's button skips that class. A Split button picks, for every class, a blessing the others are not giving (/lazy blessings split), /lazy blessings team shows everyone's choices, and your button covers a class when the paladin who has it is dead, offline or far away. /lazy blessings share on|off.
- **/lazy gear why** lists every piece of gear in your bags and why it is or is not marked as an upgrade.
- **/lazy steps debug** shows what the pedometer reads (position, on foot, yards counted).

### Changed
- **After an update you get one line in chat** instead of the What's new window opening. /lazy new opens it, and /lazy new test shows the chat line.
- **The newer-version line tells you to update on CurseForge** (curseforge.com/wow/addons/foreverlazy).

## 0.22.0
### New
- **Pedometer.** It adds up the distance you cover on foot (not mounted, not on a flight, not teleported): this session, today, this level, the level before, and in total, plus the zones you walk the most and the last seven days. `/lazy steps` opens the numbers, `/lazy steps show` puts a small movable readout on the screen, `/lazy steps reset` starts again. The unit follows the distance setting in the options (yards, meters or steps).
- **Paladin blessings.** For a paladin in a group, one button blesses the next player who is missing their blessing (it skips the dead, the offline and anyone out of range, and rebuffs when under 90 seconds are left). Every class in the group has its own blessing, which you change by clicking the class (right-click goes back): Might for fighters and Wisdom for casters to start with. The button's target changes between fights, never during one. `/lazy blessings` shows or hides the panel, `/lazy blessings debug` shows the blessing spells, the group and the buffs it sees, `/lazy blessings reset` goes back to the usual choices.
- **Nameplate colours** (off until you turn them on, in the options under Nameplates, or `/lazy platecolors on`). A hostile mob that is attacking you is red, one that is fighting someone else is yellow, and a quest mob that is not in a fight is purple. The colours are yours to change, and each part can be switched off. Players, friendly mobs, tapped mobs and idle mobs keep the game's own colour. A mob attacking you stays red even when another nameplate addon colours it green.
- **Group finder report.** `/lazy lfg` shows what the Forever group finder gives to addons, so we can see what a group finder filter could do.

## 0.21.0
### New
- **Translations.** Every text the addon shows now goes through one lookup, so a language file only has to list the texts (about 940 are ready: the options, the tour, what's new, the chat messages and the windows). Nothing is translated yet; everything stays English until a language file is added. `docs/LOCALIZATION.md` says how, `docs/locale-template.lua` lists every text, `/lazy l10n` shows what is translated, `/lazy l10n missing` lists what still is not, and the options have a Language button. Plan stop labels (Turn in, Pick up, Class quest) are translated for showing while the rules still work on the English words.

### Changed
- **Under the hood:** a new offline test builds the options window, the tour, what's new and the report windows, so a mistake inside a window shows up before a release.

## 0.20.0
### Fixed
- **The spell rank swap never started.** The file stopped on an event the Forever client does not know, so nothing watched for a new spell, and `/lazy check` reported it. Events are registered one by one now, and the swap also uses the newer function for picking a spell up (and names the one that is missing if there is a problem).
- **/lazy check** now lists the new files and every file reaches its own end marker.

### New
- **Gear advisor.** Hover any item you could wear and a green line says whether it is an upgrade for your class and spec. Upgrades in your bags get a green ^ in the bag window and at vendors, and a button on the gear bar that equips them when you click it. An optional chat note tells you when you loot or buy one. Stats are scored with each spec's stat order from the WoW Forever priority lists (hit counts only up to the hit cap). `/lazy gear` shows what you are scored as, `/lazy gear stats` shows what it reads from your gear, `/lazy gear list` lists the upgrades in your bags. It has its own group in the options and a module switch.
- **Quest item sparkles.** The game's own loot sparkle on quest items stays switched on, even after a graphics preset. Credit to Forever Loot Sparkles by Ashtar Senior (GPL-3.0). `/lazy sparkles on|off`.
- **Range colours.** Action buttons turn red out of range, blue without mana and grey when unusable. Adapted from tullaRange by Tuller (MIT). `/lazy range on|off`. Both of these step aside when the original addon is installed.
- **Keep a low rank on purpose.** `/lazy rankup keep <spell>` leaves one spell on the rank you put there, `rankup unkeep <spell>` undoes it, and the swap has a checkbox in the options.
- **Bug report.** `/lazy report` opens a window with the version, game build, your settings, the plan and arrow, other addons that matter, and the last errors from Forever Lazy, ready to copy. Nothing is sent anywhere. `/lazy apis` lists the game functions the newer features need and whether this client has them. `/lazy commands` lists every command in groups. All three are buttons in the options too.

### Changed
- **Under the hood:** the 3,500 line Extras.lua is split into five files (the plan menus, the step window, the plan detail, the sharing and import tools, and what is left). Nothing is meant to change for you.
- **The arrow is cheaper.** Its target is kept for a fraction of a second and thrown away the moment the plan or a setting changes.
- **The gear advisor says so** when the game language is not English and item stats cannot be read from the tooltip.
- **The tour and the options text** know about the damage meter, range colours, sparkles and the new bug report buttons.
- **The quest reward star** uses the same gear scoring as the advisor, so it knows your spec, two-handers against two weapons, and the hit cap.
- The credits in `media/CREDITS.txt` now name Forever Loot Sparkles and tullaRange, with tullaRange's licence notice.

## 0.19.1
### Fixed
- **Quest titles in the wrong capitals.** Seven quests showed in Title Case ("Look To The Stars"). They are spelled like the game now: "Look to the Stars" (four quests), "Plea to the Alliance", "Your Place in the World" and "Aid for the Refugees".

### Changed
- **Fresh quest data** from Questie 12.13.0 (QuestieDB 1.1.5): 3 new quests and 6 new objects, moved creature spawns (about 1,000), updated quest flags (about 150, including repeatable and daily quests), a longer hidden-quest list, and one new quest XP value.
## 0.19.0
This release rolls up everything since 0.17.7.

### Fixed
- **Quest item buttons did nothing** in the quest tracker, the quest item bar and the quest-giver panel. They now use a /use macro and work again.
- **Arriving at a stop that was not first in the plan never cleared it.** Since closest-first, the arrow could point at a later stop; now arriving at it clears that stop.
- **A skipped quest could still become the arrow target** when the plan ran out of stops, or when the quest was the one selected in the quest log. A skipped quest is never an arrow target now.
- **Picking a quest to do next did nothing** when it had no stop in the plan (skipped, put off, or in another zone). The plan is rebuilt so it gets one.

### New
- **Close hand-ins first.** A finished quest you can hand in nearby goes to the front of the plan (within about 600 yards) and the arrow goes to it first (within about 450 yards). Hand-ins back in town stay where they were.
- **A skipped quest you finished still gets its hand-in** when the hand-in is close.
- **The arrow says why it points where it does:** a hand-in close by, a hand-in before it turns grey, the closest stop, the quest you picked, or next in your plan. Options has a checkbox.
- **Quest tracker clicks.** Click opens the quest in the quest log, shift-click moves the plan and arrow to it, ctrl-click shares it.
- **Options start on a "Start here" page** with the presets (Just point me, Leveler, Duo, Everything) and a group of extras to tick on or off.
- **Damage meter tab** laid out like Details: class icon, rank, name, a class-coloured bar, and total, per second and percent. Your own row stays on screen.
- **Fresh quest data** from Questie 12.12.0 (QuestieDB 1.1.4): about 100 new quests, 173 objects, 113 items, and many fixes to levels, zones, drops and names. The data files are rebuilt without the game now; see tools/README.md.

### Changed
- **The quest item bar is off by default.** Tick it in the options to bring it back.
- **Options show only the basics** until you press Show all options. Switching a module off hides its options. Ticking an option says what happened in chat. The option texts were rewritten in plainer words, and the tour describes all of it.
## 0.17.7
- **Yellow party tag.** The [Forever Lazy] tag in party announcements shows in yellow for everyone running the addon.

## 0.17.6
- **Hunt panel.** A small panel with one button per mob your quests need. Click one to target it and mark it with a skull. When you follow someone's shared plan it names the mobs for their current stop. It has an X to close it. /lazy hunt on|off.
- **Arrow: closest first.** The arrow goes to the nearest of your next stops in the zone, and a finished quest that is about to turn grey is handed in first. Options has a Closest first checkbox.
- **Plan sharing.** A plan only counts as new when its places change, so you are not asked to accept a new one after every kill. Shared plans carry their quest ids.
- **Bag window off by default.** The game has its own one-bag view. Turning ours off turns the game's Combine Bags on. The free slot count uses the game's own number, and /lazy bags debug shows what the game's bags are doing.
- **Minimap button** sits on the outer edge of any size or shape of minimap.
- **Trainer visits** only come due at even levels.
- **Craft planner** panel is off by default (a checkbox turns it on).
- **What's new window** that pops up after an update fades away after 5 seconds.

## 0.17.5
- **Free slots on top.** In the sectioned bag window the Free row comes first.
- **Fix: pet test.** /lazy pet test left the pet reminder on for good when you were not a hunter. It switches off when the test ends.
- **Credits.** Questie and the libraries are credited in media/CREDITS.txt and the description.

## 0.17.4
- **Fix: options that could only be switched off.** Eleven checkboxes (quest sounds, quest announce, the three quest map switches, quest link tooltips, hand-in ping, quest item reminder, nameplate quest icons, interrupt marker, newest spell rank) stored the wrong value when ticked, so once off they stayed off. The bag settings for auto sort, quest border and item level had the same fault. All work both ways now.
- **Spell rank swap says why.** The Fix my bars now button and the new /lazy rankup report why nothing changed (switched off, in combat, carrying something, nothing to change). /lazy rankup debug opens a popup with what the action bars and the spellbook look like.

## 0.17.3
- **Fix: bag error.** Since 0.17.1 the bag auto sort hit a Lua error after every bag change. Fixed.
- **Arrow stays in your zone.** The kill or collect spot the arrow picks is in the zone you are in (or right next to you). Cross a zone border and it chooses again.
- **Nameplate ! checks.** Only mobs that really drop a quest starter get it: not when you already carry the item, did or have the quest, or when the item is a random drop from many mobs.
- **Damage meter.** One hidden player no longer blanks the whole list. The Meter chat tab is found or made again if it is closed. Hover tooltips never show an old list, and a stuck hover lets go. Zoning clears a stale picture, and a new dungeon or raid starts a fresh meter (/lazy meter autoreset off keeps the old numbers).
- **Plan sharing** is only sent and announced when the plan changes (from 0.17.2).
- The .toc now has Author, License (GPL-3.0-or-later) and Website lines.

## 0.17.2
- **Fix: plan-sharing spam.** The group plan is only sent again when it (or the group) changes, and a plan you already have is not announced again.
- **Cleaner release.** The zip holds only the ForeverLazy folder, with proper paths. Download ForeverLazy-0.17.2.zip from the release, not GitHub's Source code link.

## 0.17.1
- **The bank is a second window.** At the bank your bags and the bank open side by side (bank on the left), so you can move items across. Closing the bank window leaves the bank.
- **Travel section.** The Hearthstone has its own Travel section (and tab) at the top of the bag.
- **Right-click uses an item** in the bag again (recipes, food, sleeping bag).
- **OpenMap.** Quest areas are sized to their zone, and the skulls, diamonds, ! and ? show on OpenMap's stitched map. Quest givers show for the map you are viewing, not only the zone you stand in.
- **Debug popups.** `/lazy questmap debug` and `/lazy tracker debug` open a window with text you can copy.
- **Dungeon tracker.** Inside a dungeon the tracker keeps only that dungeon's quests (still being checked; `/lazy tracker debug` shows what it matched).

## 0.17.0
- **Real bag sections.** Equipment, Food and drink, Potions, Bandages, Consumables, Trade goods, Reagents, Recipes, Gems, Ammo, Bags, Keys, Misc and Junk. A section and its tab only exist while you carry something for it. Layout by category is now the default (the `...` settings still switch back to bag order). The tabs are plain text, and the section titles are bigger.
- **The bag scrolls** with the mouse wheel and never grows past about 60% of the screen.
- **Spell ranks.** A newly learned rank replaces the old one on your action bars, out of combat. Options, Action bars: on/off and a "Fix my bars now" button.
- **Interrupt marker on nameplates.** A casting mob shows its spell; the border is green (interrupt ready), red (on cooldown) or grey (no interrupt). Options, Nameplates.
- **Quest item reminder.** A button with the quest item appears when you are at the spot (or have the mob targeted). Shift-drag moves it. Options, Quest items.
- **Quest starters.** The gold ! is bigger and sits above the nameplate. Accepting a quest started by an item drop tells your party (same switch as the completed-quest message).
- **Arrow.** Clicking a quest on the game's world map points the arrow at it. A quest stop in another zone stays off the arrow until you are in that zone. A map pin clicked in another zone is kept until you move to another zone.
- **Fix:** nameplate sword and loot bag icons go away when the quest is done with that mob (finished objectives, finished quests, late kill counts).
- New files: RankUp.lua, NameplateCasts.lua, QuestItems.lua (one full game restart needed).## 0.16.0
- **ONE BAG WINDOW!!** All your bags in one window (B, or the bag buttons) with a search box that dims what does not match, All / Trade / Use / Gear / Quest / Misc buttons, a button per bag to hide its items, quality borders you can set, item levels on gear, free slots and money, and the bank in the same window at the bank. Settings are under the `...` button: auto sort, border colours, quest border, replacing the game's bags, item size, background and layout. It takes over the bag keys when Bagnon is not running; `/lazy bags` always opens it.
- **Layout by category.** Quest, Gear, Consumables, Trade goods, Misc, Junk, with the empty slots in one row.
- **Other characters.** Look inside the bags, bank and mail of any character you have played, with their full names.
- **Nameplate icons.** A sword on mobs a quest needs killed, a loot bag on mobs that drop a quest item, a bag with a ! on mobs that drop an item that starts a quest you can take. `/lazy plates off` hides them.
- **Tell the party** when you finish a quest, with the item or kill that finished it. `/lazy announce off` stops it.
- **Quest tools.** Quest search (`/lazy find`), quest history (`/lazy history`), quest chain info and quest link tooltips in chat (`/lazy links`), map filters (hide quest givers far above your level, pin size), and a hand-in ping (`/lazy ping`).
- **New zones and dungeons** in the coach and the levelling guide, found from the quest data (`/lazy zones`). The levelling guide text no longer overlaps.
- **Chat tweaks** like Prat, all off until turned on (Options, Chat): timestamps, class colours, levels, short channel names, keyword highlight, copy chat, clickable links, sticky channels, font, and resizable chat windows.
- **Fix:** a drop rate over 100% in item tooltips now reads "about 1.5 per kill". Characters show their full names in item tooltips, and a character saved twice (while the realm name was empty) is no longer listed twice.
- The files now have real names (QuestMap.lua, QuestSounds.lua, BagWindow.lua and so on) instead of Spare1 to Spare12.
## 0.15.4
- **STARTER ITEMS GO AWAY!!** An item that only started a quest no longer stays on the quest item button (or the tracker row) once the quest is in your log. Items the quest still needs keep their button.
## 0.15.3
- **CLICK A QUEST, OPEN A QUEST!!** A click on a quest in the tracker opens it in your quest log. Ctrl-click does what a click used to do: do this quest next. Shift-click still links it and right-click still opens the menu.
- **16/40!!** The tracker title counts your quests out of the 40 the quest log holds.
## 0.15.2
- **JOB'S DONE!!** Quest sounds, all from the game itself (no sound file ships with the addon): a sound effect when a quest step is done (all the items or kills of one objective), and the Job's done voice (Peasant for the Alliance, Peon for the Horde) when the quest is ready to hand in. Choose them in the options under Quest sounds, with Hear it and Change buttons, or `/lazy sound`.
- **Quest giver tooltips.** Hover an NPC and the tooltip lists the quests they give (`!`) and the quests of yours you can hand in to them (`?`, green when ready).
- **Click the quest map!** Click a pin or a coloured area and the arrow points there. Hover for the quest level, the mob levels and the named area (like Goldshire, not just the zone).
- **Named areas** on the arrow's sub-line and in the plan window, when the data knows the area of a stop.
- **Damage meter tooltips.** Hover a name in the Meter tab for the moves they used, with amounts and percents of their total. The meter no longer redraws under your mouse, so the tooltip appears at once and goes away when you leave.
- **Fix:** fly to a new zone and the plan and arrow now update by themselves (also after a map click had set its own spot).
## 0.15.1
- **DROP RATES WITHOUT QUESTIE!!** The addon now carries the real chance that every creature drops every quest item, taken from Questie's own drop tables and merged the way Questie merges them: manual corrections first, then the private-server numbers, then Wowhead's. 16,683 pairs, 1,252 items! So "where's the best place to farm this?" is a REAL answer now, not a flat guess. With Questie running it still asks Questie first. `/lazy data verify` has a new line that compares a sample of the chances.
## 0.15.0
- **Forever Lazy no longer needs Questie.** It carries its own quest data (quests, creatures, objects, items, quest XP, zones, vendor and trainer lists) and its own rules for which quests you can take, all checked against Questie's with no differences. If Questie is installed it still works with it and uses it as a second source; if not, everything runs on the addon's own data. The addon is now **GPL-3.0** (it uses data and code from Questie). `/lazy data` shows what it knows, `/lazy data verify` compares it with Questie, and **Test without Questie** in the options tries it for you.
- **Quest map.** The world map and the minimap show where your quests' mobs, items and objects are: a skull to kill, a purple diamond to collect (where it drops), a green triangle to use, with soft coloured areas behind them (one colour per quest). A yellow `!` marks quests you can pick up in the zone and a yellow `?` finished quests to hand in. Hover a pin for the quest and what is left. The lines between plan stops are off by default now.
- **Quest tooltips.** Hover a mob, an object or an item a quest needs and the tooltip says which quest it is for (bold, gold) and how far along you are, with finished objectives in green. It stays quiet for quests another addon, such as Questie, already names.
- **Party progress on tooltips**, for people who have Forever Lazy and for people who run Questie: the tooltip shows what each person in your group still needs ("Alex: Redridge Brute slain 3/10"). Forever Lazy reads and sends Questie's group messages (only to your group), so Questie users see you too. `/lazy questie` shows who it has heard from.
- **Turn-ins first.** In an area with quests you can hand in, the plan puts those first, nearest first. Yellow quests rank ahead of orange ones. The "Ready: turn in" line in the tracker is green.
- **Couch mode** (`/lazy couch on`): big text, quests accept and hand in by themselves (rewards are advised, never picked), steps read aloud.
- **Talent reminders** with a guide of key talents per class (from Maxroll, credited), `/lazy talents`.
- **Come back later** to a quest (right-click the arrow or the tracker): a crowded spot is put off and comes back into the plan when you are near it again.
- **The quest tracker** groups quests by zone (collapsible), can minimise, and hides in combat. The craft plan panel can be closed.
- **A dungeon arrow** and a run-through for dungeon quests when you are in the dungeon.
- **Mob levels** (`/lazy moblevels`): the level range of the hostile mobs you have met in each zone.
- **An update notice**: players in your group or guild on a newer version make a small button appear at the top of the screen ("What's new" and where to get it). Debug commands (`/lazy data`, `/lazy check`, `/lazy why` and others) open a window you can scroll and copy from, not chat.
- **Fixes:** an accepted quest's "pick it up" step now clears from the plan even when the game's accept event is missed, and the tooltip lines no longer flicker or double.
## 0.14.0
- **Forever Lazy's own quest tracker** (`/lazy tracker`, or Options): your quests in plan order, the one you are on first, each with its level colour, XP, live objectives and who to turn in to. Click a quest to do it next, shift-click to link it, right-click to skip, share, show in the log or abandon. Quest item buttons sit on the quest rows. It can replace WoW's tracker, has a no-background option and a compact mode, scrolls, resizes from the corner and edges, fits its text, and shows dungeon quests only inside a dungeon (and only dungeon quests there, class quests included).
- **Autopilot** (`/lazy autopilot on`, off by default): the next step after a quest stop is the vendor when bags are full or gear is damaged, or the trainer when something new is waiting; when a zone has nothing left worth doing it moves on to the next zone on your journey and plans it when you arrive. It never interrupts a quest you are in the middle of.
- **The arrow points at the nearest kill or collect spot** and moves on when you have stood there a while with nothing counting up.
- **Making sure the plan is right**: a plan log (`/lazy plan log`, every change to the plan and why), a self-check (`/lazy plan check`, and it runs by itself) that takes out dungeon quests, skipped quests, hand-ins that came up early, quests already accepted or handed in, and duplicates, an audit that notes quests in your log the plan left out and why, a "stuck here?" prompt when nothing moves at a stop for a few minutes, and a note when the plan earns much less XP per hour than it promised. The rules have offline tests (`lua tests/run.lua`).
- **The plan only moves on when a step is really done**: accepted, objectives complete, or handed in. Arriving at a stop is not enough.
- **A step window** (`/lazy steps`): the plan as steps (accept, do, turn in) that tick off by themselves.
- **The planner weighs XP for the time** (walking included), counts nearby quests you have not taken, and leaves small quests out.
- **Quest rewards are picked for your class and spec.**
- **In a group, entering a dungeon your quests need something in** shows a pop-up with the exact items (and who drops them) and kills; `/lazy dungeons here` shows it any time.

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
