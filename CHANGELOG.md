# Changelog

## 1.0.1

- Quests picked up out of route order are handled by themselves: accept a quest whose steps the
  route has passed (an item-started quest like Chen's Empty Keg, looted late) and the guide goes
  back to it, shows only that quest and its follow-ups, then returns to where you were. Handing in
  a quest whose follow-up the route has passed works the same way.
- "Ready to hand in" only lists finished quests of the batch you are on.
- A batch step counts only the quests you actually have: "Do these 6 quests" becomes "Do these 2
  quests" when you carry two of them (quests you never picked up or skipped are not counted).
- The "Coming up" section is gone.
- A tidier header: the icon spans the title and chapter lines, which line up; the arrow and its
  distance have the top-right corner to themselves, ending on the same edge as the step text,
  which starts a little lower and uses the full width.
  The gear icon is gone - right-click the panel (or /emg options) for the settings.
- New "Panel width" setting (260-520 px, or `/emg width`) next to "Panel max height"; the outline
  preview shows the new size while you change either. The panel is now 350 px wide by default.

## 1.0.0

First release.

If you run into a problem, comment on the CurseForge page or open an issue at
https://github.com/RNYR/EarthmothersGuide/issues - the output of `/emg status` or
`/emg check <questID>` helps.

Route
- 1-60 Tauren Druid route for WoW: Forever in 12 chapters, including Riverglades, Shen'dralas,
  Mount Hyjal and the new Forever dungeons.
- Druid class quests: Bear Form, Cure Poison, Aquatic Form, the new Cat Form chain, Travel Form,
  Dire Bear Form and the Torwa Pathfinder chain.
- Dungeons are part of the route, each reached inside its level range so you can queue with the
  group finder; if you are already above a dungeon's range, its steps are skipped.
- Quest batches as one checklist step; "Also carrying", "Coming up" and "Ready to hand in"
  sections. Escort and event quests have their own step.
- Hearthstone suggestions, travel steps with how to get there, detours for hand-ins that would
  lose XP, and Teleport: Moonglade tips (reputation-aware Timbermaw tunnel tip).
- Quests up to 4 levels above you are part of the route; level pacing simulated from real Forever
  quest XP (kill XP and dungeon runs are stated assumptions), with one short "grind to level" step.
- Never more than 20 quests in your log at once.

Panel
- Built-in arrow to the nearest unfinished objective, and a Blizzard map pin.
- Replaces Blizzard's quest tracker under the minimap while the guide is shown (combat-safe).
- A checkbox beside every quest skips just that quest; Done checkbox for notes.
- Quest item buttons beside their quest, as in Blizzard's quest tracker.
- "Panel max height" setting with a preview outline; longer steps scroll.
- Settings page with a route browser; compact mode; profession quest toggle.

Smart about where you are
- Starts where your character is: reads your level and finished quests.
- Skips quests once they turn grey (the game's grey rule); a grey chain start stays only while
  the rest of the chain is worth doing.
- Waits for the quest log to load at login; a step you chose by hand survives /reload.
- Quests started by looted items are optional "Look out for" pickups.
- Warns when a step's quests are 3 or more levels above you.

Licensed GPL-3.0-only, matching the GPLv3 terms the quest data is used under.
