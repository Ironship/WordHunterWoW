import assert from "node:assert/strict";
import test from "node:test";
import { source } from "./source.mjs";

test("opens the companion panel for the selected Quest Log entry", () => {
  // The hook is installed by name from Compat's list now rather than written
  // out at the call site, so that Classic's equivalents can sit beside it.
  assert.match(source, /"QuestMapFrame_ShowQuestDetails",/);
  assert.match(source, /QuestMapFrame_GetDetailQuestID/);
  assert.match(source, /Compat\.QuestLogIndexForID\(questId\)/);
  assert.match(source, /readCurrentQuest\(questId\)/);
  assert.match(source, /loadedAddon == "Blizzard_WorldMap"/);
});

test("never hooks a Blizzard function without checking it exists", () => {
  // Classic has neither of Retail's quest-detail functions. hooksecurefunc on a
  // name that is not there is an error, and it would take the addon down at
  // login rather than at the moment the missing feature was used.
  const calls = [...source.matchAll(/hooksecurefunc\(([^)]*)/g)].map((m) => m[1]);
  assert.ok(calls.length > 0, "expected the addon to hook something");
  for (const call of calls) {
    assert.doesNotMatch(call, /^"/, `hooked a literal name unguarded: ${call}`);
  }
  assert.match(source, /type\(_G\[name\]\) == "function"/);
});

test("quest log updates never open the reader and debounce the visible library", () => {
  assert.match(source, /RegisterEvent\("QUEST_LOG_UPDATE"\)/);
  const start = source.indexOf('elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_QUERY_COMPLETE" then');
  assert.ok(start >= 0, "quest-state events need a dedicated branch");
  const end = source.indexOf("\n  else\n", start);
  const branch = source.slice(start, end);
  assert.match(branch, /SyncCharacterQuestHistory/);
  assert.match(branch, /refreshCatalogSoon\(\)/);
  assert.doesNotMatch(branch, /readCurrentQuest|panel:Show/);
  const helperStart = source.indexOf("local function refreshCatalogSoon()");
  const helper = source.slice(helperStart, source.indexOf('events:SetScript("OnEvent"', helperStart));
  assert.match(helper, /Addon\.questsFrame and Addon\.questsFrame:IsShown\(\)/);
  assert.match(helper, /browserTimer:Cancel\(\)/);
  assert.match(helper, /C_Timer\.NewTimer\(0\.2/);
});

