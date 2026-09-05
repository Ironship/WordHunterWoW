import assert from "node:assert/strict";
import test from "node:test";
import { source } from "./source.mjs";

test("keeps long quest UI content inside dedicated bounds", () => {
  assert.match(source, /panel\.title:SetMaxLines\(1\)/);
  assert.match(source, /panel\.title:SetWordWrap\(false\)/);
  assert.match(source, /InputScrollFrameTemplate/);
  assert.match(source, /editor\.noteScroll\.EditBox/);
  assert.match(source, /copyDialog\.scroll:SetVerticalScroll\(0\)/);
});

test("keeps the copy dialog above the quest panel and word editor", () => {
  assert.match(source, /copyDialog:SetFrameStrata\("TOOLTIP"\)/);
  assert.match(source, /copyDialog:Raise\(\)/);
  assert.match(source, /frame:SetToplevel\(true\)/);
});

test("keeps the quest panel and editor above the Blizzard Quest Log", () => {
  assert.match(source, /panel:SetFrameStrata\("FULLSCREEN_DIALOG"\)/);
  assert.match(source, /panel:SetFrameLevel\(20\)/);
  assert.match(source, /editor:SetFrameStrata\("FULLSCREEN_DIALOG"\)/);
  assert.match(source, /editor:SetFrameLevel\(30\)/);
});

test("uses stable English vocabulary status labels", () => {
  for (const label of ["New", "Learning", "Known", "Ignored"]) {
    assert.match(source, new RegExp(`= "${label}"`));
  }
});

test("keeps every addon control and helper label in English", () => {
  for (const label of ["Meaning / translation", "Note", "Copy word", "Copy quest", "Save", "Cancel"]) {
    assert.match(source, new RegExp(`= "${label.replace("/", "\\/")}"`));
  }
  assert.doesNotMatch(source, /Bedeutung|Übersetzung|Notiz|kopieren|Speichern|Abbrechen|gespeichert/);
  assert.doesNotMatch(source, /GetLocale\(\) == "deDE"/);
});

test("both panel columns keep the quest's line breaks", () => {
  // Running gmatch("%S+") over a whole quest throws away every break in it, so
  // the column renders as one block and stops lining up with the one beside it.
  // The German side did exactly that while the English side did not.
  assert.doesNotMatch(source, /lastQuest\.text or ""\):gmatch\("%S\+"\)/);
  assert.doesNotMatch(source, /block\.text\):gmatch\("%S\+"\)/);
  assert.match(source, /function Addon\.TextLines\(text\)/);
  assert.match(source, /ipairs\(Addon\.TextLines\(lastQuest\.text\)\)/);
  assert.match(source, /ipairs\(Addon\.TextLines\(block.text\)\)/);
});

test("clicking a German word highlights the matching English sentence", () => {
  assert.match(source, /function Addon\.MatchEnglishSentence\(/);
  assert.match(source, /function Addon\.HighlightEnglishForWord\(/);
  assert.match(source, /Addon\.HighlightEnglishForWord\(self\.word/);
  assert.match(source, /OnHighlightEnglishForWord/);
  assert.match(source, /function Addon\.MatchEnglishTokenIndexes\(/);
  assert.match(source, /enWordHighlight/);
});

test("how a met word is marked is the player's choice, and the mark scales", () => {
  assert.match(source, /function Addon\.GetWordMarking\(/);
  assert.match(source, /function Addon\.SetWordMarking\(/);
  assert.match(source, /function Addon\.UnderlineThickness\(/);
  assert.match(source, /Addon\.LABELS\.wordMarkingLabel/);
  assert.match(source, /WORD_MARKING_ORDER/);
  // A fixed height set once at frame creation cannot follow the text size.
  assert.doesNotMatch(source, /underline:SetHeight\(\d+\)/);
  assert.match(source, /underline:SetHeight\(underlineHeight\)/);
});

test("says so when a quest record has no English opening text", () => {
  // Classic records carry a title and an objective and nothing else. The panel
  // used to show the lone objective with no explanation, where it read as a
  // translation that had been cut short. The existing caveat covered only the
  // other case -- an NPC showing progress or hand-in text -- so this one needs
  // its own branch and its own label.
  assert.match(source, /enNoOffer = "\[No English opening text/);
  assert.match(source, /elseif not hasOffer then/);
  assert.match(source, /caveat = LABELS\.enNoOffer/);
  // It must stay an either/or with the passage caveat: two red lines above one
  // objective would be worse than none. One variable, assigned in one branch or
  // the other, makes that structural rather than a matter of care.
  assert.match(source, /local caveat\s+if lastQuest\.passage/);

  // And it goes under the English text, not over it. Above, it was the first
  // thing read on every quest that has one -- a red paragraph standing between
  // the reader and what they opened the panel for.
  const enBlock = source.slice(source.indexOf("local enBlocks"), source.indexOf("panel.enTitle:SetText"));
  const descriptionAt = enBlock.indexOf("text = entry.description");
  const caveatAt = enBlock.indexOf("text = caveat, caveat = true");
  assert.ok(descriptionAt > -1 && caveatAt > -1, "both the text and the caveat should be placed");
  assert.ok(caveatAt > descriptionAt,
    "the caveat belongs after the English text it explains, not before it");
});
