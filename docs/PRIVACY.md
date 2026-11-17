# What it sends to other players

Back to the [README](../README.md)

Nothing is ever typed into chat. By default there is no custom chat channel either. When you are in a group, the addon
sends **hidden addon messages** to other players who also have it:

- your **quest list** (so it can show quests you share),
- your **plan**, only when you share it or you are the leader in duo mode,
- the addon's **version number**.

**Dock sharing is off by default.** When you switch it on (`/lazy net on`), a taught dock (a map and two coordinates) is
sent to your guild and your group.

**The Hive is off by default.** Only if you switch it on (Options > The Hive, or `/lazy hive on`) does the addon join a
small channel called `ForeverLazyHive` (kept out of your chat windows) and send hidden addon messages that hold ids and
numbers only: drop counts, quest times and zone XP rates; a rare spawn you spotted (its id, name and the place it was seen);
and "someone is in this zone, level 10-14" with no name and no position. It never sends your character name, guild, realm,
position, items, gold or anything you typed. Details and how incoming numbers are checked are in [the Hive](HIVE.md).
Players without the addon see nothing at all.
