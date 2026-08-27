import assert from "node:assert/strict";
import test from "node:test";
import { source } from "./source.mjs";

test("slash command opens a filterable word list", () => {
  assert.match(source, /command == "words"/);
  assert.match(source, /WordHunterWoWDB\.settings\.hideIgnored/);
  assert.match(source, /function Addon\.toggleWordList\(\)/);
  assert.match(source, /listFrame\.search:SetScript\("OnTextChanged", function\(\) refreshWordList\(\) end\)/);
});

test("word list shows all words without forms count", () => {
  assert.doesNotMatch(source, /forms = counts\[key\]/);
  assert.doesNotMatch(source, /%d forms/);
  assert.match(source, /row\.meta:SetText\(Addon\.trim\(item\.entry\.translation/);
});

test("word list is resizable and remembers position", () => {
  assert.match(source, /Addon\.MakeResizable\(listFrame, "list"/);
  assert.match(source, /listFrame\.scroll:UpdateScrollChildRect\(\)/);
  assert.match(source, /listFrame\.content:SetWidth\(math\.max\(300, listFrame:GetWidth\(\) - 60\)\)/);
});

test("slash command opens word statistics", () => {
  assert.match(source, /command == "stats"/);
  assert.match(source, /function Addon\.toggleStats\(\)/);
  assert.match(source, /local function computeStats\(now\)/);
  assert.match(source, /LABELS\.statsSummary/);
});

test("statistics count all words without linked forms", () => {
  assert.doesNotMatch(source, /forms = forms \+ 1/);
  assert.match(source, /total = total \+ 1/);
  assert.match(source, /string\.format\(LABELS\.statsSummary, stats\.total\)/);
});

test("statistics respect ready-for-known thresholds", () => {
  const statsSource = source;
  const computeBlock = statsSource.slice(statsSource.indexOf("computeStats"));
  assert.ok(computeBlock.includes("(entry.encounterCount or 0) >= 5"));
  assert.ok(computeBlock.includes("14 * 24 * 60 * 60"));
});

test("panel exposes words and stats buttons", () => {
  assert.match(source, /LABELS\.wordsButton/);
  assert.match(source, /LABELS\.statsButton/);
});

test("word list and stats remember position", () => {
  assert.match(source, /Addon\.PlaceFrame\(listFrame, "list"\)/);
  assert.match(source, /Addon\.PlaceFrame\(statsFrame, "stats"\)/);
  assert.match(source, /Addon\.LayoutKey\("list"\)/);
  assert.match(source, /Addon\.LayoutKey\("stats"\)/);
});
