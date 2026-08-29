import assert from "node:assert/strict";
import test from "node:test";
import { source } from "./source.mjs";

test("dictionary providers are overlays, not copied into SavedVariables", () => {
  assert.match(source, /function Addon\.RegisterDictionaryProvider\(locale, providerId, entries\)/);
  assert.match(source, /function Addon\.GetDictionaryEntry\(key, locale\)/);
  assert.match(source, /function Addon\.GetEffectiveWord\(key\)/);
  assert.match(source, /function Addon\.GetEffectiveWords\(\)/);
});

test("dictionary words default to New and user words override them", () => {
  // Written as a checked expression now, not a literal: an unrecognised status
  // coming from a dictionary file falls back to New rather than being trusted.
  assert.match(source, /and dict\.status or "new"/);
  // The overlay used to be an inline loop here; pinning its exact text is what
  // went stale when it became ForEachEffectiveWord. What the walk actually
  // produces is checked for real in tests/effective-words.test.lua.
  assert.match(source, /function Addon\.ForEachEffectiveWord\(fn\)/);
  assert.match(source, /if user\[key\] == nil/);
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
