import assert from "node:assert/strict";
import test from "node:test";
import { source } from "./source.mjs";

test("base form linking has been removed", () => {
  assert.doesNotMatch(source, /LABELS\.baseForm/);
  assert.doesNotMatch(source, /LABELS\.similar/);
  assert.doesNotMatch(source, /LABELS\.linkedForms/);
  assert.doesNotMatch(source, /LABELS\.unlink/);
  assert.doesNotMatch(source, /function Addon\.similarWords\(/);
  assert.doesNotMatch(source, /function Addon\.possibleBaseForms\(/);
  assert.doesNotMatch(source, /function Addon\.getHeadEntry\(/);
  assert.doesNotMatch(source, /function Addon\.resolveHeadKey\(/);
  assert.doesNotMatch(source, /function Addon\.absorbIntoHeadword\(/);
});

test("export includes all words without baseKey filter", () => {
  assert.match(source, /WordHunterWoWExport = "WHW3\|"/);
  assert.doesNotMatch(source, /if not item\.baseKey then/);
});

test("legacy baseKeys have been cleaned up", () => {
  assert.doesNotMatch(source, /cleanLegacyBaseKeys/);
  assert.doesNotMatch(source, /entry\.baseKey/);
  // The schema version moves whenever a migration is added, and hard-coding it
    // here is what made this test go stale: it still expected 9 after the Unicode
    // re-key bumped it to 10. Derive it from the migrations instead, so the test
    // checks the thing that matters -- the database is stamped with the newest
    // migration, and so will not run it twice.
const migrations = [...source.matchAll(/WordHunterWoWDB\.version or 0\) < (\d+)/g)]
    .map((m) => Number(m[1]));
const newest = Math.max(...migrations);
  assert.ok(migrations.length > 0, "no migrations found at all");
  assert.match(source, new RegExp(`WordHunterWoWDB\.version = ${newest}`));
});

test("windows are resizable and remember position", () => {
  assert.match(source, /function Addon\.SaveFramePosition\(frame, key\)/);
  assert.match(source, /function Addon\.RestoreFramePosition\(/);
  assert.match(source, /function Addon\.MakeResizable\(frame, key/);
  assert.match(source, /SetResizable\(true\)/);
  assert.match(source, /StartSizing\("BOTTOMRIGHT"\)/);
});

test("npc and questlog have separate default window layouts", () => {
  assert.match(source, /Addon\.LAYOUT_DEFAULTS/);
  assert.match(source, /function Addon\.GetLayoutContext\(\)/);
  assert.match(source, /function Addon\.LayoutKey\(base\)/);
  assert.match(source, /function Addon\.PlaceFrame\(/);
  assert.match(source, /return "questlog"/);
  assert.match(source, /npc = \{/);
  assert.match(source, /questlog = \{/);
});

test("windows use BackdropTemplate so SetBackdrop works", () => {
  for (const name of ["WordHunterWoWFrame", "WordHunterWoWEditor", "WordHunterWoWList", "WordHunterWoWStats", "WordHunterWoWCopyDialog"]) {
    assert.match(source, new RegExp(`CreateFrame\\("Frame", "${name}", UIParent, "BackdropTemplate"\\)`));
  }
});

test("word editor is movable and resizable", () => {
  assert.match(source, /editor:SetMovable\(true\)/);
  assert.match(source, /Addon\.MakeResizable\(editor, "editor"/);
});

test("quest log details do not inject into blizzard frames", () => {
  assert.doesNotMatch(source, /ensureQuestLogButton/);
  assert.doesNotMatch(source, /QuestMapFrame\.DetailsFrame or QuestMapFrame/);
});
