-- Run from the addon root:  lua tests/_loadprofile.lua <SavedVariables/WordHunterWoW.lua>
--
-- Not a test: a harness. It takes a real profile off a real client and puts it
-- through the real load path, so "the words are on disk and the addon cannot
-- see them" can be answered here instead of by another round trip through the
-- game.

local profile = ...
if not profile then
  print("usage: lua tests/_loadprofile.lua <path to WordHunterWoW.lua>")
  return
end

local node = dofile("tests/wowstub.lua")

-- The Forever client, which is where this is being chased: a Retail-family
-- build number and matching project globals, with the addon's own manifest
-- saying 16001.
GetBuildInfo = function() return "12.1.0", "69814", "2026-09-01", 120100 end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
C_AddOns = { GetAddOnMetadata = function(_, field)
  return field == "Interface" and "16001" or nil
end }

-- The game assigns the saved variables before ADDON_LOADED, which is exactly
-- what this line does: the file is Lua and its globals are the profile.
local chunk, err = loadfile(profile)
if not chunk then print("cannot read profile: " .. tostring(err)) return end
chunk()

local function countWords(where)
  local db = WordHunterWoWDB
  local byLocale = db and db.wordsByLocale
  local total, byStatus = 0, {}
  for locale, words in pairs(byLocale or {}) do
    for _, entry in pairs(words) do
      total = total + 1
      local s = entry.status or "(none)"
      byStatus[s] = (byStatus[s] or 0) + 1
    end
  end
  local parts = {}
  for s, n in pairs(byStatus) do parts[#parts + 1] = s .. "=" .. n end
  table.sort(parts)
  print(string.format("  %-28s %d words  %s", where, total,
    #parts > 0 and table.concat(parts, " ") or ""))
  return total
end

print("profile: " .. profile)
local before = countWords("straight off disk:")

dofile("Core.lua")
dofile("Compat.lua")
local Addon = WordHunterWoW_Addon
print("  flavour: " .. tostring(Addon.Compat and Addon.Compat.GameFlavor()))
countWords("after the files load:")

Addon.initializeDatabase()
local after = countWords("after initializeDatabase:")

-- And what the addon itself would answer, which is what the word list shows.
local table_ = Addon.GetWordsTable()
local n = 0
for _ in pairs(table_) do n = n + 1 end
print(string.format("  %-28s %d words", "GetWordsTable() sees:", n))

if after < before then
  print("\n  LOST " .. (before - after) .. " words during load")
elseif n < before then
  print("\n  the table is intact but GetWordsTable() reaches only " .. n)
else
  print("\n  nothing lost on this path")
end
