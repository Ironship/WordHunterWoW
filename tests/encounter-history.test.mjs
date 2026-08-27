import assert from "node:assert/strict";
import test from "node:test";
import { source } from "./source.mjs";

test("exports encounter history without counting the same quest twice", () => {
  assert.match(source, /WordHunterWoWExport = "WHW3\|"/);
  assert.match(source, /item\.firstSeenAt/);
  assert.match(source, /item\.lastSeenAt/);
  assert.match(source, /not item\.encounteredQuests\[questKey\]/);
  assert.match(source, /item\.encounterCount = item\.encounterCount \+ 1/);
});

test("suggests Known only after five quests and fourteen days", () => {
  assert.match(source, /\(selected\.encounterCount or 0\) >= 5/);
  assert.match(source, /\(entry\.encounterCount or 0\) >= 5/);
  assert.match(source, /14 \* 24 \* 60 \* 60/);
  assert.match(source, /LABELS\.readyForKnown/);
});
