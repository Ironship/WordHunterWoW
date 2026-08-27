import assert from "node:assert/strict";
import test from "node:test";
import { source } from "./source.mjs";

test("opens the companion panel for the selected Quest Log entry", () => {
  assert.match(source, /hooksecurefunc\("QuestMapFrame_ShowQuestDetails"/);
  assert.match(source, /QuestMapFrame_GetDetailQuestID/);
  assert.match(source, /C_QuestLog\.GetLogIndexForQuestID\(questId\)/);
  assert.match(source, /readCurrentQuest\(questId\)/);
  assert.match(source, /loadedAddon == "Blizzard_WorldMap"/);
});

test("does not use noisy Quest Log update events", () => {
  assert.doesNotMatch(source, /RegisterEvent\("QUEST_LOG_UPDATE"\)/);
});

