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
  assert.match(source, /Addon\.CreateNativeWindow\("WordHunterWoWFrame"/);
  assert.match(source, /Addon\.CreateNativeWindow\("WordHunterWoWList"/);
  assert.match(source, /Addon\.CreateNativeWindow\("WordHunterWoWEditor"/);
  assert.match(source, /template \.\. ",BackdropTemplate"/);
  // Stats and the copy/confirm dialogs used to be plain frames here, which
  // left them on the DialogFrame skin while the reader and the library wore
  // the native one -- the theme reached every window except these. They are
  // built the same way now, and CreateNativeWindow falls back to exactly this
  // create on a client without the atlases.
  assert.match(source, /Addon\.CreateNativeWindow\("WordHunterWoWStats"/);
  assert.match(source, /Addon\.CreateNativeWindow\("WordHunterWoWCopyDialog"/);
  assert.match(source, /Addon\.CreateNativeWindow\("WordHunterWoWConfirmDialog"/);
  assert.match(source, /return CreateFrame\("Frame", name, parent, "BackdropTemplate"\)/);
});

test("the content inset does not reach below the scroll it frames", () => {
  // InsetFrameTemplate's border is thick enough to draw inward from the inset's
  // bottom edge, and the inset used to hang six pixels below its scroll on top
  // of that. Whatever sits under the scroll -- the word list's "showing 200 of
  // 114181" line, the library's pagination row -- got a rule drawn straight
  // through it. Both windows were reported, and both times the cause was this
  // overhang rather than where the footer had been put. A caller cannot see it
  // to leave room for it, so there is none.
  assert.match(source, /inset:SetPoint\("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 14, 0\)/);
  assert.doesNotMatch(source, /inset:SetPoint\("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 14, -\d/);
});

test("the close button is the template's own", () => {
  // ButtonFrameTemplate brings a close button and it draws: the word editor is
  // built from that template, asks for no close button at all, and its cross is
  // the only one in this addon that has ever shown. Two attempts at supplying
  // one instead -- a bare UIPanelCloseButton, then one with the Classic
  // bitmap's texture coordinates put right -- both came out clickable and
  // invisible in every window that asked for one. The fault was in the
  // replacing rather than in the button, so these pin the order of the two
  // branches instead of the art.
  assert.match(source, /local close = rawget\(frame, "CloseButton"\)/);
  assert.match(source, /rawset\(frame, "closeButton", close\)/);
  // And every window wears the one template that has that button to inherit.
  assert.doesNotMatch(source, /"DefaultPanelFlatTemplate"/);
});

test("word editor is movable and resizable", () => {
  assert.match(source, /editor:SetMovable\(true\)/);
  assert.match(source, /Addon\.MakeResizable\(editor, "editor"/);
});

test("quest log details do not inject into blizzard frames", () => {
  assert.doesNotMatch(source, /ensureQuestLogButton/);
  assert.doesNotMatch(source, /QuestMapFrame\.DetailsFrame or QuestMapFrame/);
});
