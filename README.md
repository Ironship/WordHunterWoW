# QuestWordHunter

WoW quests are full of the language you actually want to learn — but they fly by. You accept, scan for the objective, and the words are gone.

QuestWordHunter keeps the quest on screen as clickable text. See a word you don't know? Click it, add a meaning, mark it **Learning**. Next time it turns up in another quest it is already coloured. After a while you have a real vocabulary list built from the game, not from a textbook.

<img width="2560" height="1440" alt="Quest text with clickable words" src="https://github.com/user-attachments/assets/6f25b0fe-5a62-46ef-b700-5cd7f0e87d78" />

<img width="2560" height="1440" alt="Statistics of learned words" src="https://github.com/user-attachments/assets/75fcae0e-e5f8-4db7-9eb9-fdd002bcec7a" />

## What you get

- Quest text you can click instead of retyping into a notes app
- Colours and underlines for **New**, **Learning**, **Known** and **Ignored**, so you see progress in the paragraph itself — keep both or pick one
- A meaning, a personal note, and the sentence the word came from
- A word list and simple stats — `/whw words`, `/whw stats`
- A quiet **Ready for Known** hint after five different quests and two weeks. It never promotes anything by itself
- Separate lists per language, so German and French don't mix
- Windows you can move, resize and theme — `/whw settings`

Buttons stay in English. Quest text stays in the language you set in WoW.

## What changed in 1.17

**The quest log no longer opens the panel by itself.** On a live realm the quest
log is a pane of the world map, and the panel opened over the very row you had
clicked — so reading a quest's objectives, or abandoning it, meant closing the
panel first. There is a **Word Hunter** button on the log now, and the panel
waits for it. A quest giver's window is unchanged: its text is the reason that
window opened. If you liked the old behaviour, `/whw settings` has a switch for
it, off by default.

**The size sliders are two groups instead of one list.** Text sizes read as the
point size the letters end up at; window sizes read as a percentage of the whole
window. They are different measurements and always were — a font size leaves the
window where you dragged it, and a window size grows the border and buttons too
— so showing both as "80–200%" invited a comparison that could never hold. Your
stored sizes are unchanged; a window you had at 1.2 now says 120%.

## Install

Unzip into `_retail_\Interface\AddOns\`, or `_classic_era_\Interface\AddOns\`
— the download carries a build for each, then:

1. Set WoW's language and the addon's **Target language** to the same thing — `/whw lang`
2. Accept a quest, or press **Word Hunter** on a quest in the Quest Log
3. Click a word, give it a meaning, save

`/whw` closes whichever of the addon's windows is open — the word list first,
then the statistics, then the quest panel — and opens the quest panel when none
of them is.

## Add a dictionary

You don't have to define every word yourself. A dictionary pack fills them in for you:

| | |
|---|---|
| [German](https://github.com/Ironship/WordHunterWoW-Dictionary-DE) | 104,274 words, every one checked by hand |
| [French](https://github.com/Ironship/WordHunterWoW-Dictionary-FR) · [Spanish](https://github.com/Ironship/WordHunterWoW-Dictionary-ES) · [Italian](https://github.com/Ironship/WordHunterWoW-Dictionary-IT) · [Portuguese](https://github.com/Ironship/WordHunterWoW-Dictionary-PTBR) | machine-translated, not hand-checked |

Want the English quest text side by side? That is [English Quest Panel](https://github.com/Ironship/WordHunterWoW-ENPanel). With it installed, pointing at a German word lights up the English sentence that says the same thing, and picks out the English word itself.

## Helping fill the gaps

Blizzard publishes a quest's title and opening text and nothing else — no objectives, no progress line, no hand-in line, no NPC chatter. Words that live only in those places never make it into a dictionary.

Your game client has them. **Collect quest and NPC text** in `/whw settings` records the passages you actually read, so they can go into the next dictionary release.

It is **off by default**, everything stays on your machine, and nothing is uploaded. Turning it on writes to your own saved data and you decide whether to share it.

```
/whw harvest            what has been collected
/whw harvest on|off     turn it on or off
/whw harvest export     open it in a box you can copy out of
/whw harvest clear      throw it away
```

Supported languages: English, German, French, Spanish, Italian, Portuguese (Brazil). Retail 12.1 and Classic Era 1.15.9.

Everything stays on your machine. No uploads.

All rights reserved. Issues: [github.com/Ironship/WordHunterWoW](https://github.com/Ironship/WordHunterWoW)
