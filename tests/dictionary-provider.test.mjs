import assert from "node:assert/strict";
import test from "node:test";
import { source } from "./source.mjs";

test("dictionary providers are overlays, not copied into SavedVariables", () => {
  assert.match(source, /function Addon\.RegisterDictionaryProvider\(locale, providerId, entries\)/);
  assert.match(source, /function Addon\.GetDictionaryEntry\(key, locale\)/);
  assert.match(source, /function Addon\.GetEffectiveWord\(key, locale\)/);
  assert.match(source, /function Addon\.GetEffectiveWords\(\)/);
});

test("dictionary words default to New and user words override them", () => {
  // Written as a checked expression now, not a literal: an unrecognised status
  // coming from a dictionary file falls back to New rather than being trusted.
  assert.match(source, /and dict\.status or "new"/);
  // The overlay used to be an inline loop here; pinning its exact text is what
  // went stale when it became ForEachEffectiveWord. It went stale again when the
  // walk grew a locale argument, so the signature is matched only as far as the
  // callback -- the part that says "this is the overlay, called once per word".
  // What the walk actually produces is checked for real in
  // tests/effective-words.test.lua.
  assert.match(source, /function Addon\.ForEachEffectiveWord\(fn/);
  // The walk has to read an entry carrying only the player's own encounter
  // record as "no wording of theirs", or the pack's wording stays hidden behind
  // a record that has no meaning in it. That entry is what the editor leaves
  // when a word is saved unchanged.
  assert.match(source, /if \(own == nil or carriesEncounters\(own\)\)/);
});

test("editor can reset translation and note to dictionary defaults", () => {
  assert.match(source, /LABELS\.resetDictionary/);
  assert.match(source, /editor\.translation:SetText\(dict\.translation or ""\)/);
  assert.match(source, /editor\.note:SetText\(dict\.note or ""\)/);
});

test("runtime keys match Python casefold for German sharp s", () => {
  assert.match(source, /gsub\("ẞ", "SS"\):gsub\("ß", "ss"\)/);
  // The fold migration is version 9; later migrations moved the stamp past it,
  // so only the guard is pinned here.
  assert.match(source, /WordHunterWoWDB\.version or 0\) < 9/);
});
