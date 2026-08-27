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
