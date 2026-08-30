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
  assert.match(source, /ipairs\(Addon\.TextLines\(block\.text\)\)/);
});

test("says so when a quest record has no English opening text", () => {
  // Classic records carry a title and an objective and nothing else. The panel
  // used to show the lone objective with no explanation, where it read as a
  // translation that had been cut short. The existing caveat covered only the
  // other case -- an NPC showing progress or hand-in text -- so this one needs
  // its own branch and its own label.
  assert.match(source, /enNoOffer = "\[No English opening text/);
  assert.match(source, /elseif not hasOffer then/);
  assert.match(source, /text = LABELS\.enNoOffer, caveat = true/);
  // and it must stay an either/or with the passage caveat: two red lines above
  // one objective would be worse than none.
  assert.doesNotMatch(source, /enBlocks\[#enBlocks \+ 1\] = \{ text = LABELS\.enOfferOnly, caveat = true \}\s*\n\s*end\s*\n\s*if not hasOffer/);
});
