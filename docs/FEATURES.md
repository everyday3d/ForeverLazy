# Feature guide

Back to the [README](../README.md) · [Commands](COMMANDS.md)

## Getting around

- **Lazy Mode** (`/lazy now`, left-click the minimap button, a key or a macro): the best next thing. Bags nearly full or
  gear damaged leads to a vendor; a due trainer visit to your trainer; otherwise your quest plan, then your journey.
  **Keep going** picks the next one by itself when you arrive.
- **Take me there** (`/lazy go <place>`): plans the whole trip with your flight points, boats and zeppelins, the Deeprun
  Tram, your hearthstone and walking, whichever is quickest. The arrow follows it leg by leg. Every Forever flight master
  is built in; it learns which ones you have opened.
- **Far-off stops use flights by themselves**: when the next plan stop is a long way off and a flight is quicker, the trip
  starts on its own: the arrow points at the flight master, the text says where to fly, and the flight map rings that
  destination. Trips are drawn on the world map and the minimap, with flights, boats, the tram and walks in different colours.
- **Boats and zeppelins** (`/lazy boat darnassus`) and **hearthstone and flight points** (`/lazy hearth`, `/lazy fp`).
- **Find a service** (`/lazy inn`, `repair`, `flight`, `bank`, `ah`, `mailbox`, `stable`, `spirit`, `battlemaster`,
  `trainer`, `cooking`...): the nearest one, with the arrow on it.
- **Journey** (`/lazy journey`): a saved zone-by-zone route from your level to 60, with the dungeons that fit.

## Quests

- **Route planner** (`/lazy plan`): the stops that pay the most XP for the least walking come first; quests that overlap
  are done in one visit and every turn-in comes after its objectives. Green, yellow and orange quests count, red only as
  a turn-in, grey never. It stays in your zone, replans when something changes, and routes you to the nearest quest
  givers when nothing of yours is in the zone.
- **It finishes an area before handing in**: quests near each other are done first and handed in together, unless
  handing one in opens the next quest of a chain. A quest handed in out of order, or dropped, leaves the plan at once.
- **Says what to do**: the line under the arrow reads your quest log (*Kill 5 more Defias Pillager (3/8)*, *Turn in X to Y*).
  A gold **?** marks a turn-in and a **!** a quest to pick up.
- **One arrow, your choice**: right-click it to pick what it points at (what is next, your plan or trip stop, your nearest
  quest, your partner, the nearest library book, your friend's quest) and it switches at once. The same menu has services
  near me (only those close by, or every one in a city), skip a quest or stop, the Coach and Lazy Mode.
- **Plan window** (`/lazy window`) and the **route drawn on the world map** with numbered stops. The line is straight
  between stops, not a walking path.
- **Class quests**, **dungeon quests** and entrances, **group quests** (green ones are fine solo), and the
  **Cozy Sleeping Bag** secret chain guide.
- **Quest helpers**: a button for quest items, what comes next in a chain, the best quest reward pick, and the best place
  to farm a quest item (`/lazy farm`).

## The guide and the Coach

- **Levelling guide** (`/lazy guide`): your journey to 60 in one window: where you are, the quests worth doing in each
  stretch, the dungeons that fit, your measured pace and fastest zone, and a **Take me there** button per stretch. The
  window scales for the couch and TV (**A-**, **A+**, **TV**, `/lazy guide tv`, or a slider in the options).
- **The Coach** (`/lazy coach`, "Ask the Coach" in the menus): compares doing the quests here, the best grind near your level
  and other zones by measured XP per hour, says what is best right now and what each answer rests on, and has a button
  that sets it up.
- **XP hot spots** (the **XP** button on the world map, `/lazy xpmap`): a light heat layer showing where the quests worth
  doing for your level are.
- **New-zone box**: after you stay in a new zone for a bit it offers to plan it, and stays quiet when you are just passing
  through or every quest there is red or grey.

## The Hive

The Hive learns from real play, because the original game's data does not always match a custom server. **One switch**
(Options > The Hive, or `/lazy hive on`), off until you turn it on.

- **Your pace**: XP per hour by zone and level, your time to the next level, your fastest zone (`/lazy pace`, `/lazy session`).
- **Drop rates** (`/lazy drops <item>`): every corpse you loot is counted; item tooltips and the crafting plan use them.
- **Quest times** (`/lazy pace quests`): quests that were slow for you are marked in the skip menu.
- **Best grind** (`/lazy grind`): XP per hour for each kind of mob, and where you killed it most.
- **Fights and deaths**: how long each kind of mob takes to kill and what it costs you, shown in the grind advice, and a
  warning when you walk into a place where players keep dying (`/lazy danger`).
- **Real quest spots**: where objectives were really done replaces the original data once there are enough sightings.
- **Rare timers and pins**: rares reported by other players appear on the world map; a dead rare stays as a timer with how
  long it usually takes to come back.
- **Shared with other players who have it on**: drop counts, quest times, zone paces, grind numbers, quest spots, rares and
  zone counts, as hidden messages of ids and numbers only. Details and how it is kept honest: [the Hive](HIVE.md).

## Damage meter

- **A damage meter in its own chat tab** called **Meter**, so it stays out of the way (`/lazy meter`). It reads the game's
  built-in damage meter, so no other addon is needed. Pick what to show (damage per second, damage done, healing, damage
  taken, interrupts, deaths), this fight or everything since the last reset, and how many players to list. In combat the
  game hides the numbers from addons, so the tab keeps the last picture until the fight is over. If a chat tab cannot be
  made, it uses a small window instead.

## Levelling a zone

- **`/lazy level`** plans the whole zone for the fastest levelling: your quests plus every quest worth taking there, in a
  walking order that earns the most XP for the walk, and a window that says what to get and from whom, where to kill or
  collect, and what to hand in. `/lazy level ashenvale` takes you there first. `/lazy level steps` reopens the window.
- **Ask a guard** where something is and the arrow takes you there and goes away when you arrive.
- **Class quests**: a pop-up once when you enter a zone that has something for one, and `/lazy class quest` lists every
  class quest with what to do for it.
- **Dungeon quests are never in a plan.** The plan rebuilds when you change continent, and a hand-in you walk close to comes
  next.

## The quest tracker

- **`/lazy tracker`** shows your quests in plan order with level colour, XP, live objectives and who to turn in to. Click one to do
  it next, right-click for skip, share, show in the log or abandon. A quest item button sits on the row.
- It can replace WoW's tracker (Questie's is turned off in Questie's options). It scrolls, resizes from the corner and
  edges, fits its text, has a compact mode and a no-background option, and shows dungeon quests only inside a dungeon.

## Autopilot

- **`/lazy autopilot on`**: the vendor or trainer between quest stops when due, then, when a zone is done, the next zone on
  your journey and a plan for it. The arrow also points at the nearest spot for kills and items.

## Making sure the plan is right

- **The plan log** (`/lazy plan log`): every rebuild, removal, hand-in moved up and arrival, with the reason.
- **A self-check** that runs by itself and with `/lazy plan check`: dungeon quests, skipped quests, early hand-ins, quests
  already accepted or handed in and duplicate steps are taken out, and each fix is logged.
- **An audit** notes any quest in your log that the plan left out, and why (skipped, dungeon, grey, a group quest, or small for the time).
- **Stuck detection**: a few minutes at a stop with no progress and it asks if you want to skip the quest.
- **The plan against reality**: it works out the XP per hour the plan should give, and tells you if you earn much less after 15 minutes.
- **Steps only count when done**: accepted, objectives complete, or handed in. Arriving is not enough.

## Ore and herb nodes

- **Every node you gather is remembered** and marked on the world map and the minimap as a round pin showing the ore
  (hover for what it is and when you last found it). A node you just took fades while it respawns, and with Find Minerals or
  Find Herbs on, the minimap pins stay faint so the game's own blip shows through.
- **Farm them with the arrow**: `/lazy nodes farm`, or right-click the arrow. It walks you node to node, skipping ones you
  just emptied, with the route drawn on the map and minimap.
- **Find a node by name** (`/lazy nodes silver`): a window of the zones that have it, from Questie's data and your own
  finds, each with a Take me there button.

## Your plan, off and on

- `/lazy plan off` puts the stops still to do aside and clears the route lines, numbered markers, XP heat and the quest item
  bar, and nothing replans on its own. `/lazy plan on` puts them back where you left them.

## Items to keep

- `/lazy keep <item>` protects an item from vendors (your Cozy Sleeping Bag is protected from the start). The tooltip says
  DO NOT SELL, opening a vendor lists protected items in your bags, and one sold anyway is bought back at once.

## Crafting and gathering

- **Crafting** (`/lazy craft`): reads the recipes you know (enchanting too), says what to craft next, and lists the
  materials counting your **bags and bank**, with where to get what is missing. A craft plan panel sits beside the
  profession window. The recipe to craft next is lit up in the recipe list with how many to make, and the materials are lit up in the bank. When a material has no known source it names the zones to skin, mine or loot it.
- **Gathering routes** (`/lazy herb peacebloom`, `/lazy ore tin`, `/lazy gather`) and **fishing spots** (`/lazy fish`).

## In the game's own windows

The **minimap button** is the hub: left-click = Lazy Mode, right-click = a menu with everything, shift-click = options.
The route is also drawn on the **minimap**. There is a "Go to..." search box on the **world map**, buttons under the **quest log** (plan my route, do this next,
skip this), buttons on the **flight map**, and **Mark this dock** at boat NPCs. A **first-run tour** shows you where
everything is (`/lazy tour`), settings can be shared as one line (`/lazy export`, `/lazy import`), and a **what's new**
window appears after an update (`/lazy new`).

## With other players

- **Follow arrow**: a purple arrow that points at anyone in your group, with or without the addon.
- **Duo mode**: two players with the addon in a group of two; the party leader's plan is followed by the other, shared
  quests count extra and your partner shows on the compass. It starts by itself.
- **Share your plan** (`/lazy shareplan`), see **quests you share** (`/lazy party`), and a note when someone in your
  group runs a newer version.

## Collections and timers

- **Library books**: waypoints, zone alerts, collected tracking (a green tick on the map), party sharing, and the arrow can
  point at the nearest one.
- **Item tooltips** say how many you have in your bags, bank, mail and worn, what your other characters have, and what is in
  your guild bank, and where the item has been seen dropping (`/lazy has <item>`).
- **Hunters**: a big FEED ME across the screen when the pet is hungry (with your own sound clip if you add one), a warning
  when ammo runs low, and a reminder when a better kind of arrow or bullet opens up for your level.
- **Titan Panel and other bars**: one Forever Lazy button with your next stop, and the whole menu when you hover over it.
- **Flight timer** (learns each flight) and a few **macros** with their own icons (`/lazy macros`).

## Keeping it simple

- **Simple arrows** (default): one main arrow, everything else on the compass bar.
- **Modules**: every part can be switched off in the options. **Presets** (Minimal, Leveler, Duo, Everything) set them in one click.
- **`/lazy check`** says if everything loaded and works. Paste it in a bug report.

## Arrows and display

Three arrow styles; colours, size, opacity and position are all yours. Arrows hide in combat, in cities and inns, on
flight paths and inside dungeons and raids. The ghost arrow still shows, and after a death in a dungeon it points at the
entrance for the corpse run. Optional TomTom support.

## RestedXP friends (optional)

If a friend runs RestedXP and shares their step with the party, Forever Lazy can listen and point arrows at their quest
spots and at them. It is **off by default**; turn it on under *RestedXP friend (optional)* in the options. You do not
need RestedXP installed yourself.

## No Questie needed
Forever Lazy carries its own copy of the quest data: quests, creatures and their positions, objects, items, the XP each quest
gives, zones, and the vendor, trainer and inn lists, plus its own rules for which quests you can take (level, race, class,
earlier quests, reputation, professions). `/lazy data verify` compares all of it with Questie's and the two agree. If Questie
is installed it is still used as a second source. The addon also learns from play: every quest you hold and every creature you
meet is noted (`/lazy data`), and it fills gaps. Click **Test without Questie** in the options to try it.

## The compass
A bar across the top of the screen: the white line is the way you face, and each marker is a target. It has its own page in the
options (switch, size, lock, and when to hide), separate from the arrows. You can turn on direction letters, the distance under
each marker, quest icons and the next stop in words. Hover a marker to see what it is; right-click the bar for a quick menu.
As a ghost it shows your body as a tombstone. The big arrow is off until you turn it on with /lazy arrow; the compass points at
the same stop the arrow would.

## Paladin helpers
Off until ticked, in the options under My class, beside the blessing panel: a seal button and an aura button that turn red when
yours is missing, each with a pop-out menu of the ones you know, a Righteous Fury button with a warning when a fight starts
without it, and cleanse buttons for the party. The panel has its own size, lock and layout. Each cast takes its own click, and
what a button casts can only change between fights. `/lazy paladin` shows what is on.

## Specs on player tooltips
Off until ticked (Chat and groups, Player tooltips, or `/lazy spec on`). Point at a player of level 10 or higher and the
tooltip shows their spec, such as `Spec: Holy (31/20/0)`. Another player has to be close enough to inspect, and new players
are not looked up during a fight. `/lazy spec check` with a player targeted says what the game answers.

## Interrupt marker and cast bar flash

- While a mob casts, its nameplate shows the spell: green border when your interrupt is ready, red on cooldown, grey if you have none.
- The cast bar can also flash while your interrupt is ready (off until you turn it on): `/lazy flash on`. If nothing flashes, target the mob and type `/lazy flash check` while it casts.

## Shaman helpers
Off until ticked, in the options under My class: a totem bar with timers and sets, a range warning (outdoors), weapon buff and
shield buttons, ankhs and Reincarnation, cure buttons for the party, a Purge mark and a Ghost Wolf reminder. Point at a totem
on the bar for a menu of that element's totems. The panel has its own size, lock and layout, a recall button, and can hide the
game's totem bar. Each cast takes
its own click, and what a button casts can only change between fights. `/lazy shaman` shows what is on.
Drop the set can have its own key (options, My class, Totems, or the game's key bindings): one totem a press, from the set picked on the panel.

## Fishing
All of it is off until you turn it on, on the **Fishing** page of the options.
- **Cast key:** click the button in the options and press a key. With your pole in your bags, the first press puts it on; after that each press casts. **Double right-click** casting is a separate tick, and works only with the pole on, out of combat.
- **Louder bobber splash:** while your line is out, sound effects go up and music and background noise go down. Your own settings come back a few seconds later, and at once if a fight starts.
- **Pole button:** pole on with one click, and your weapons, shield or off-hand back with the next. There is a key for it in the game's key bindings too.
- **Lure button:** puts the best lure in your bags that your skill allows on your pole, with a warning when there is none or it is about to wear off.
- **Auto loot while fishing**, a **catch log** per zone (`/lazy fish log`, `/lazy fish log all`, `/lazy fish log reset`), your **skill and points gained** (`/lazy fish status`), and **pool spots on the world map**. A map marker does not mean the pool is there right now.
- **Cooking tie-in:** `/lazy fish cook`, or a tick that adds a line to the fishing bar, shows the recipes you know that use the fish in your bags: how many you can make now, what is missing, and which can still raise your cooking. Open your cooking window once first; the colours are from the last time you opened it.
- `/lazy fish` still takes you to the nearest pool.

Nothing fishes for you: you press the key or button every cast and click the bobber yourself.

## Plates v2: threat on nameplates
All of it is off until you turn it on, under **Combat, Plates v2** in the options. **Which plates** picks one kind at a time: Plates v1 (the red, orange and purple health bar colours) or Plates v2 (these). Each keeps its own settings, ticking something switches to its kind, and `/lazy platestyle v1|v2` does it too. Quest icons and the interrupt marker show with both, and the v2 words move over to make room for them.
- **Who each mob is attacking:** a short name beside the nameplate in that player's class colour, or YOU.
- **Your threat** on each mob as a percentage.
- **Pull warning:** PULL! and one sound from 80% threat. It stays quiet when the game hides your threat numbers.
- **Tank colours:** green is on you, yellow is on you but someone has more threat, pink got away. The pull warning is off while these are on.
- Some combat values are hidden from addons. Names and numbers are handed to the game to show without being read, and where a colour cannot be worked out the game's own is left. `/lazy threat check`, with a mob targeted in a fight, says what is hidden.

## The quest map
Your quests on the world map and the minimap: coloured areas where to kill or collect, one colour per quest (on the minimap,
small dots in that colour), a small green dot for each thing to click on the ground, a yellow `!` on quests you can pick up
in this zone and a yellow `?` where a finished quest is handed in. Skull and purple diamond icons on the mob spots are an
option. Hover a pin or an area for the quest and what is left. The checkboxes are in the options under Quest map.

## Quest tooltips and your group
Hover a mob, an object or an item a quest needs and the tooltip names the quest (bold, gold) and your progress, with finished
objectives in green. People in your group who have Forever Lazy or Questie show up too ("Alex: Redridge Brute slain 3/10").
Forever Lazy speaks Questie's group messages, to your party or raid only, so Questie users see your progress as well.
`/lazy questie` shows who it has heard from.

## Couch mode, talents and coming back later
`/lazy couch on` makes the text big, accepts and hands in quests by itself (rewards are advised, never picked) and reads the
steps aloud. `/lazy talents` lists unspent points and the key talents for your class. Right-click the arrow or the tracker to
put a quest off (too many people there) and it returns to the plan when you are near it again.