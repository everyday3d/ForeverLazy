# Translating Forever Lazy

Back to the [README](../README.md)

Every text the player reads in Forever Lazy goes through one function, `L`. It looks the English text up in the table for the game's language and gives it back unchanged when there is no translation. A missing translation never breaks anything: that text simply stays English.

The game languages that WoW Forever has: `deDE`, `esES`, `esMX`, `frFR`, `itIT`, `koKR`, `ptBR`, `ruRU`, `zhCN`, `zhTW`. `enUS` (and `enGB`) is the original.

## Make a translation

1. Copy [`docs/locale-template.lua`](locale-template.lua) to `ForeverLazy/Locales/deDE.lua` (use your language code). It lists about 940 texts, one per line, grouped by the file they come from.
2. In the copy, change `ns.locales["xxXX"]` to your code, for example `ns.locales["deDE"]`.
3. Fill in the right-hand side: `["Take the tour"] = "Zur Tour",`. Leave `""` for a text you do not translate; it stays English.
4. Add the line `Locales\deDE.lua` to `ForeverLazy/ForeverLazy.toc`, right after the line `Locale.lua`.
5. In the game, type `/reload`. `/lazy l10n use deDE` forces the language if your game is set to another one (`/lazy l10n use auto` goes back).
6. `/lazy l10n` says how many texts are translated. `/lazy l10n missing` opens a window with every text the addon asked for that has no translation yet, already in the right format to paste into your file.

## Rules

- Keep every `%d`, `%s` and `%.1f` exactly as in the English text, in a sensible place for your language. `string.format` fills them in: `"%d stops left"` becomes `"noch %d Halte"`. The test `lua tests/l10n.lua` checks that a shipped translation keeps the same codes as the English.
- Keep colour codes like `|cffffd100` and `|r` where they are. They colour the text between them.
- Keep `\n` (a line break).
- Some texts are only a piece of a sentence, because the code joins pieces together (for example `"plan updated. Next: "` followed by a stop name). Translate each piece so the joined result reads well. If a piece cannot work in your language, tell us and we will change the code to use one whole sentence.
- Texts in the options are the English wording of the checkbox, so a translation should keep the same meaning (a tick means on).

## What is not translated

- **Names from our own data.** The addon carries English quest, creature, item and place names. Where the game itself gives a name (the quest log, item tooltips, spell names) you see it in your language. Plan labels built from our data can stay English.
- **Reading item stats.** The gear advisor uses the game's stat table where there is one (the Forever client has one). Where it has to read the words on a tooltip, it only understands English and says so once in chat.
- **Matching a quest's wording** (which objective is still open) compares the game's text with English names from our data, so on another language it matches less often.
- **What the addon says to other players** (party announcements and the plan sharing messages) stays English on purpose, so every player sees the same thing.
- **Debug and report windows** (`/lazy report`, `/lazy apis`) are written for bug reports and stay English.

## How the stop labels work

A plan stop carries a label such as `Turn in: The Lost Ingots` or `Pick up: ...`. The code uses the English start of that label to decide what to do (hand-ins come first, a skipped quest, the plan checks). Those labels are never translated inside the code. Only when a label is shown, `ns.LocalizeLabel` swaps `Turn in: ` / `Pick up: ` / `Class quest: ` for the translated words (keeping the number in front), so the rules cannot break.

## For developers

- In a file: `local L = ns.L`, then `Print(L("text"))`, or `string.format(L("%d things"), n)` when there are values.
- `lua tools/l10n_template.lua ForeverLazy docs/locale-template.lua` rebuilds the list of texts from the code (it picks up every `L("...")`).
- `lua tests/l10n.lua` tests the lookup and checks every translation file that ships.
