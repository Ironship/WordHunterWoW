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
  assert.match(source, /status = "new"/);
  assert.match(source, /for key, entry in pairs\(Addon\.GetWordsTable\(\)\) do result\[key\] = entry end/);
});

test("editor can reset translation and note to dictionary defaults", () => {
  assert.match(source, /LABELS\.resetDictionary/);
  assert.match(source, /editor\.translation:SetText\(dict\.translation or ""\)/);
  assert.match(source, /editor\.note:SetText\(dict\.note or ""\)/);
});

test("runtime keys match Python casefold for German sharp s", () => {
  assert.match(source, /gsub\("ẞ", "SS"\):gsub\("ß", "ss"\)/);
  assert.match(source, /WordHunterWoWDB\.version or 0\) < 9/);
  assert.match(source, /WordHunterWoWDB\.version = 9/);
});
