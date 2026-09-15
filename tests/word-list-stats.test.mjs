import assert from "node:assert/strict";
import test from "node:test";
import { source } from "./source.mjs";

test("slash command opens a filterable word list", () => {
  assert.match(source, /command == "words"/);
  assert.match(source, /WordHunterWoWDB\.settings\.hideIgnored/);
  assert.match(source, /function Addon\.toggleWordList\(\)/);
  // The box refreshes the list as it is typed in. It used to call
  // refreshWordList straight from OnTextChanged, and this line pinned that
  // literal shape -- so when the call was put behind a timer, to stop a
  // seventy-thousand-word list being rebuilt once per keystroke, the assertion
  // went on failing for a change that was correct. Pinned to the behaviour
  // instead: typing schedules a refresh, and a new keystroke cancels the one
  // already waiting.
  assert.match(source, /listFrame\.search:SetScript\("OnTextChanged"/);
  assert.match(source, /if debounce then debounce:Cancel\(\) end/);
  assert.match(source, /debounce = C_Timer\.NewTimer\([\d.]+, function\(\)/);
  assert.match(source, /if listFrame:IsShown\(\) then refreshWordList\(\) end/);
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
  const computeBlock = statsSource.slice(statsSource.indexOf("local function computeStats("));
  assert.ok(computeBlock.includes("Addon.GetReadyAfter and Addon.GetReadyAfter()"),
    "the stats page has to read the setting, not a copy of its default");
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
