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
- **Real quest spots**: where objectives were really done replaces the original data once there are enough sightings.
- **Rare timers and pins**: rares reported by other players appear on the world map; a dead rare stays as a timer with how
  long it usually takes to come back.
- **Shared with other players who have it on**: drop counts, quest times, zone paces, grind numbers, quest spots, rares and
  zone counts, as hidden messages of ids and numbers only. Details and how it is kept honest: [the Hive](HIVE.md).

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
