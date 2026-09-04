-- Run from the addon root:  lua tests/harvest-export.test.lua
--
-- Getting the collected text out of the game was a slash command nobody could
-- discover: you had to have read the addon's description to know it existed.
-- It is a button in the settings now, beside the switch that starts the
-- collecting.
--
-- The part that actually trips people up is not the export. It is that the file
-- only reaches disk when the game writes its saved variables, which happens on
-- reload or logout and at no other time. Export, go looking, and you find
-- yesterday's file and reasonably conclude it is broken. So the dialog says so,
-- offers the reload, and shows the path in a box you can copy out of.

strlower = string.lower
strtrim = function(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
time = os.time
GetLocale = function() return "deDE" end
CreateFrame = function() return setmetatable({}, {__index = function() return function() end end}) end

dofile("Core.lua")
local Addon = WordHunterWoW_Addon
assert(Addon.HarvestExportPath, "Core.lua should say where the file lands")

-- The path names the game, because the two clients keep separate folders and
-- sending the wrong one is a wasted round trip.
Addon.Compat = { IsClassic = function() return false end }
local retail = Addon.HarvestExportPath()
assert(retail:find("_retail_", 1, true), "Retail's path should name _retail_: " .. retail)

Addon.Compat = { IsClassic = function() return true end }
local classic = Addon.HarvestExportPath()
assert(classic:find("_classic_era_", 1, true), "Classic's path should name _classic_era_: " .. classic)
assert(not classic:find("_retail_", 1, true), "and must not name the other one")

for _, path in ipairs({ retail, classic }) do
  assert(path:find("SavedVariables", 1, true), "the path has to reach SavedVariables")
  assert(path:find("WordHunterWoW.lua", 1, true), "and name the file")
  -- The account directory is a Battle.net id that no addon API exposes, so it
  -- is a placeholder rather than a guess.
  assert(path:find("<your account>", 1, true), "the account folder cannot be known, and should say so")
end

-- The wording has to carry the one fact that makes this work.
local labels = Addon.LABELS
assert(labels.harvestExport and labels.harvestExport ~= "", "the button needs a name")
assert(labels.harvestExportBody:find("Ctrl+C", 1, true),
  "the dialog must say how to copy the block")
assert(labels.harvestExportBody:find("passages", 1, true)
    and labels.harvestExportBody:find("words", 1, true), "and how much is in it")
assert(labels.harvestExportEmpty:find("Nothing has been collected", 1, true),
  "an empty export should say so rather than pointing at a file with nothing in it")
assert(labels.harvestExportReload and labels.harvestExportReload ~= "")

-- And the settings panel has to actually offer it, wired to the export.
local settings = io.open("Settings.lua"):read("a")
assert(settings:find("LABELS.harvestExport", 1, true), "the button belongs in the settings")
assert(settings:find("Addon.rebuildHarvestExport", 1, true), "pressing it must write the export")
assert(settings:find("showCopyText", 1, true), "and put the blob in a box that can be copied")
assert(settings:find("WordHunterWoWCorpusExport", 1, true), "the box holds the export, not a file path")
assert(settings:find("harvestExportEmpty", 1, true), "with nothing collected it must not pretend otherwise")

local ui = io.open("UICommon.lua"):read("a")
assert(ui:find("HighlightText", 1, true), "the path must be selected so it can be copied")
assert(ui:find('gsub("|", "||")', 1, true) or ui:find('gsub("|", "||")', 1, true),
  "pipes in the blob must be escaped or the edit box swallows the text")

print("harvest-export: ok")
