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

// The count is a setting now, so the thing worth pinning is that both places
// read it. They used to hold a 5 each, which is how one of them was changed and
// the other was not: the editor offered Known on a word the stats page had not
// counted as ready, and the two disagreed with no error anywhere.
test("suggests Known only after the set number of quests and fourteen days", () => {
  // Both comparison sites named individually rather than counted: the settings
  // page reads the same getter to fill its slider, so a count would pass with
  // the editor still holding a 5 as long as some third caller existed.
  assert.match(source, /\(selected\.encounterCount or 0\) >= \(Addon\.GetReadyAfter/,
    "the editor has to read the setting");
  assert.match(source, /\(entry\.encounterCount or 0\) >= readyAfter/,
    "the stats page has to read the setting");
  assert.doesNotMatch(source, /encounterCount or 0\) >= 5/,
    "no copy of the threshold may stay written into the code");
  assert.match(source, /14 \* 24 \* 60 \* 60/);
  assert.match(source, /LABELS\.readyForKnown/);
});
