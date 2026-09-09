-- Run from the addon root:  lua tests/every-file.test.lua
--
-- Load the eleven files the .toc names, in the order it names them, and run
-- the surfaces the rest of the suite never reaches.
--
-- Two of the eleven could not be loaded here at all until now. Init.lua indexes
-- SlashCmdList at file scope and the stub had no such table, and Settings.lua
-- calls UIDropDownMenu_SetWidth, which the fabricating __index used to answer
-- with a manufactured node. So the file that decides what happens on
-- ADDON_LOADED and on every quest event, and the whole /whw command tree, were
-- executed by nothing. The one test that names Init.lua opens it and greps the
-- text, which catches a renamed function and not a nil-global typo.
--
-- This is the hole the wowstub repair was for, left open in the two files it
-- would matter most in.

local node = dofile("tests/wowstub.lua")

local function manifest(path)
  local files = {}
  for line in io.lines(path) do
    local file = line:match("^(%S+%.lua)%s*$")
    if file then files[#files + 1] = file end
  end
  return files
end
local TOC = manifest("WordHunterWoW_Mainline.toc")
assert(#TOC == 11, "the manifest names " .. #TOC .. " lua files, expected 11")
-- The Classic manifest is a second copy of the same list. A file added to one
-- and not the other loads on Retail and is nil on Classic Era, and nothing
-- else here reads the second file at all.
local VANILLA = manifest("WordHunterWoW_Vanilla.toc")
assert(#VANILLA == #TOC, "the two manifests name a different number of files")
for i, file in ipairs(TOC) do
  assert(VANILLA[i] == file, "the manifests disagree at line " .. i .. ": " .. file .. " vs " .. tostring(VANILLA[i]))
end

-- Loaded from the manifest rather than from a list written here. A list would
-- be a second answer to "what does this addon load", and the two drift.
for _, file in ipairs(TOC) do
  local chunk, err = loadfile(file)
  assert(chunk, "the manifest names " .. file .. " but it will not load: " .. tostring(err))
  local ok, runErr = pcall(chunk, "WordHunterWoW")
  assert(ok, file .. " raised while loading: " .. tostring(runErr))
end
print("  every file the manifest names loads, in the order it names them")

local Addon = WordHunterWoW_Addon
WordHunterWoWDB = nil
Addon.initializeDatabase()
Addon.createPanel()
Addon.createEditor()

-- The slash commands, which is the surface a player reaches when nothing is on
-- screen. Driven through SlashCmdList exactly as the client does it.
local run = SlashCmdList["WORDHUNTERWOW"] or SlashCmdList["WHW"]
assert(run, "Init.lua registered no slash handler under any name this test knows")
local said = {}
local realPrint = print
print = function(...) said[#said + 1] = table.concat({ ... }, " ") end
local commands = {
  "", "settings", "words", "stats", "reset", "bg", "opacity",
  "lang", "harvest", "harvest on", "harvest off", "harvest clear", "export",
  "difficult", "difficult export", "recall", "recall on", "recall off",
}
for _, command in ipairs(commands) do
  local ok, err = pcall(run, command)
  print = realPrint
  assert(ok, "/whw " .. command .. " raised: " .. tostring(err))
  print = function(...) said[#said + 1] = table.concat({ ... }, " ") end
end
print = realPrint
print("  every /whw command runs on a fresh profile without raising")
-- The recall commands say what they did, and the switch really moves.
local recallOn
for _, line in ipairs(said) do
  if line:find("Recall check on.", 1, true) then recallOn = true end
end
assert(recallOn, "/whw recall on did not report the switch")
assert(Addon.GetRecallCheck() == false, "/whw recall off ran last and has to leave it off")
-- With a difficult word the export command opens the copy box rather than
-- saying there is nothing. The word is taken away again below, so the
-- statistics still open on an empty profile.
local now = time()
Addon.GetWordsTable().hund = { word = "Hund", status = "learning", translation = "dog", statusChangedAt = now - 3 * 86400 }
for i = 1, 5 do Addon.RecordRating("hund", 1, now + i) end
said = {}
print = function(...) said[#said + 1] = table.concat({ ... }, " ") end
local okExport, errExport = pcall(run, "difficult export")
print = realPrint
assert(okExport, "/whw difficult export with a difficult word raised: " .. tostring(errExport))
assert(Addon.copyDialog and Addon.copyDialog:IsShown(), "/whw difficult export did not open the copy box")
assert(Addon.copyDialog.title:GetText() == Addon.LABELS.difficultExport, "under its own title")
assert(Addon.copyDialog.hint:GetText() == Addon.LABELS.difficultExportHint, "with the hint that says where it goes")
for _, line in ipairs(said) do
  assert(not line:find("Nothing to copy.", 1, true), "said there was nothing to copy with a difficult word present")
end
Addon.copyDialog:Hide()
Addon.GetWordsTable().hund = nil
WordHunterWoWDB.recallByLocale = nil
print("  /whw difficult export puts a difficult word in the copy box")

-- Stats.lua, which no other test loads. Its arithmetic is checked elsewhere;
-- what is checked here is that opening it on an empty profile does not raise,
-- which is the first thing a new player who types /whw stats will do.
assert(Addon.toggleStats, "Stats.lua defined no toggleStats")
local ok, err = pcall(Addon.toggleStats)
assert(ok, "opening the statistics window on an empty profile raised: " .. tostring(err))
-- And the row this release added reads zero rather than nothing.
assert(Addon.statsFrame and Addon.statsFrame.extraRows and Addon.statsFrame.extraRows.difficult,
  "the statistics window has no difficult-words row")
assert(Addon.statsFrame.extraRows.difficult:GetText() == "0",
  "on an empty profile the difficult count reads " .. tostring(Addon.statsFrame.extraRows.difficult:GetText()))
pcall(Addon.toggleStats)
print("  the statistics window opens and closes on an empty profile")

-- The row counts, and a height saved before the row existed is lifted to
-- hold it. Closed first: the toggle above may have left it either way.
local statsFrame = Addon.statsFrame
if statsFrame:IsShown() then Addon.toggleStats() end
Addon.GetWordsTable().hund = { word = "Hund", status = "learning", translation = "dog", statusChangedAt = now - 2 * 86400 }
for _ = 1, 5 do Addon.RecordRating("hund", 1, now) end
Addon.toggleStats()
assert(statsFrame.extraRows.difficult:GetText() == "1",
  "one difficult word reads " .. tostring(statsFrame.extraRows.difficult:GetText()))
Addon.toggleStats()
WordHunterWoWDB.settings.frames[Addon.LayoutKey("stats")] =
  { point = "CENTER", relPoint = "CENTER", x = 0, y = 0, w = 340, h = 400 }
Addon.toggleStats()
assert(statsFrame:GetHeight() >= 420, "a 1.17 height of 400 was not lifted: " .. tostring(statsFrame:GetHeight()))
Addon.toggleStats()
print("  the difficult row counts, and an old short height is lifted")

print("every-file: ok")
