# The Hive

The Hive is how Forever Lazy learns from real play instead of guessing. The original game's quest and drop data does not
always match a custom server, so the addon measures what actually happens, and players who have the Hive on share what
they measured with each other. **There is one switch:** Options > AddOns > Forever Lazy > **The Hive** (or
`/lazy hive on` and `/lazy hive off`). It is off until you turn it on.

## When it is ON

| What | How | Where you see it |
|---|---|---|
| **Your XP per hour** | Time and XP between gains, per zone and level. A break over 3 minutes is not counted. | `/lazy pace`, the guide window, the new-zone box |
| **Drop rates** | Every corpse you loot is counted, with the items in it (skinning too). | `/lazy drops <item>`, item tooltips, the crafting plan's "where to get it" |
| **Quest times** | Accept to turn-in for each quest, ignoring anything under 20 seconds or over 2 hours. | `/lazy pace quests`, "(slow for you)" in the arrow's skip menu |
| **Best grind** | XP per hour for each kind of mob you kill, counting the time between kills, near your level. Other players' numbers count too. | `/lazy grind`, the guide window |
| **Rare timers** | When a rare dies and is seen again, the gap is a measurement of its respawn. The pin of a dead rare stays as a timer ("killed 20 minutes ago, usually back after about 45"), and you get a line in chat when it should be back. | the world map pins, `/lazy hive rares` |
| **Real quest spots** | Where you stood when a quest objective counted up. Once a quest has enough sightings (yours and other players') the planner uses those places instead of the original data's guesses. | the plan and the arrow |
| **The Coach** | Compares quests here, the best grind, and other zones by measured XP per hour and tells you the best thing to do now, with a button that sets it up. | `/lazy coach`, the arrow menu |
| **Fights and deaths** | How long each kind of mob takes to kill and how much damage it costs you (from the game's own damage meter, no other addon needed), and where players die. You get a word when you walk into a place where people keep dying. | `/lazy grind`, `/lazy danger`, the Coach |
| **This session** | XP, quests, kills and gold since you logged in. | `/lazy session` |
| **Numbers from other players** | Drop counts, quest times and zone paces that other players with the Hive on send. They are added to your own numbers, so drop rates and quest times are good from the start. | the same places as above |
| **Rare spawns** | When anyone spots a rare, others get a pin on the world map, and a line in chat when it is in their zone. `/lazy hive rare` points an arrow at the nearest. | world map, chat |
| **Zone counts** | The map shows how many other Forever Lazy players are in a zone, by level band. | `/lazy hive who`, the world map |

When it is OFF nothing is learned, nothing is sent and nothing is received. `/lazy hive` shows what has been learned and
`/lazy hive reset` forgets all of it.

## What goes over the wire

When the Hive is on, the addon joins a small channel called `ForeverLazyHive`, kept out of your chat windows. Only hidden
addon messages go over it, and they carry **only ids and numbers**:

- drop counts: a mob id, how many kills, and item ids with counts (a few minutes of play at a time),
- quest times: a quest id with how many times, seconds and XP,
- zone XP rates: a zone name with a level, XP and seconds,
- grind numbers: a zone, a mob name, your level band, kills, XP and seconds,
- a death: a map square (about 1% of a zone) where a player died, with no name or time,
- a quest spot: a quest id and a map square (about 1% of a zone, some tens of yards) where one of its objectives counted up; no name, no time,
- a rare spawn: the rare's id and name, the zone and the place it was seen, and a "dead" note when you loot it,
- how long a rare took to come back (a number of seconds),
- a zone count: "someone is in this zone, level 10-14", about every 90 seconds,
- a "hello" when you join, answered by one other player with a short snapshot of what they know.

It **never** sends your character name, guild, realm, items, gold or anything you typed, and never a track of where you are. The only places it shares are where a rare was seen and coarse map squares where a quest objective was done or someone died.

## How shared numbers are kept honest

Anyone can write to a public channel, so every incoming message is checked: sizes, ranges and plausible rates (no
item count above 30 per kill, no XP rate above what is possible, quest times between 20 seconds and 2 hours). No sender
can add more than a fixed number of records per session, and no more than a steady trickle per second. Other players'
numbers go into a separate cache and never overwrite yours. Your own numbers count first, and the cache is capped in size.
Snapshots from other players take the larger number instead of adding, so the same data is never counted twice.

Parts of it can be switched off on their own: the chat alert for rares, the rare pins, and sharing which zone you are in.