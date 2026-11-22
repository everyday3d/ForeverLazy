# Rebuilding the data files without the game

The files in `ForeverLazy/data` (quests, creatures, objects, items, quest XP) come from the QuestieDB add-on's data. They can be rebuilt offline, no game needed. You need Lua 5.4 (`winget install DEVCOM.Lua`).

1. `lua tools/qdb_offline.lua <QuestieDB folder> <ForeverLazy folder> <out file>` reads QuestieDB's own data file and writes the same dump `/lazy data export` makes.
2. `lua tools/build_data.lua` turns that dump into `data/Quests.lua`, `Npcs.lua`, `Objects.lua`, `Items.lua` (edit the paths at the top).
3. `lua tools/build_xp.lua` rebuilds `data/QuestXP.lua` from QuestieDB's XP tables.
4. `lua tools/compare.lua <old dump> <new dump>` and `tools/fielddiff.lua` show what changed between two dumps.

5. `lua tools/build_extras.lua <QuestieDB> <ForeverLazy> <new dump> <out dir>` rebuilds `Zones.lua`, `Extra1.lua` (hidden quests, drop chances), `Extra2.lua` (hidden groups, quest tags) and `Townsfolk.lua` from QuestieDB and Questie's own files. `tools/compare_extras.lua` compares them with the old ones.

Checked against the in-game exports: unchanged records come out the same. Quest tags the game itself answers (a handful) are carried over from the last in-game export; new quests only get Questie's own tag corrections.
