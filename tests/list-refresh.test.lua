-- Run from the addon root:  lua tests/list-refresh.test.lua
--
-- Saving a word made the whole game stutter -- but only once you had opened the
-- word list, and then for the rest of the session even with the list closed.
--
-- Saving calls refreshWordList, and that guarded on whether the list frame
-- existed, not on whether anyone could see it. Once the frame existed, every
-- save walked all ~74,000 dictionary entries, folded a sort key for each
-- survivor, sorted them and laid out rows -- for a window that was shut.
--
-- The cost is invisible in any test that measures correctness, so this one
-- counts the walk instead.

local node = dofile("tests/wowstub.lua")

dofile("Core.lua")
dofile("Compat.lua")
dofile("UICommon.lua")
dofile("QuestPanel.lua")
dofile("Editor.lua")
dofile("WordList.lua")
local Addon = WordHunterWoW_Addon
assert(Addon.toggleWordList and Addon.refreshWordList, "WordList.lua must provide both")

WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, words = {}, wordsByLocale = {} }
Addon.initializeDatabase()

-- Count every full pass over the vocabulary. This is the expensive thing, and
-- the only thing that matters here.
local walks = 0
local realForEach = Addon.ForEachEffectiveWord
Addon.ForEachEffectiveWord = function(fn)
  walks = walks + 1
  return realForEach(fn)
end

-- Never opened: nothing to refresh, and nothing walked.
walks = 0
Addon.refreshWordList()
assert(walks == 0, "with no list at all there is nothing to walk, got " .. walks)

-- Open it. A visible list has to be rebuilt, so this one is expected.
Addon.toggleWordList()
assert(Addon.listFrame, "the list frame should exist once opened")
assert(Addon.listFrame:IsShown(), "and be on screen")
walks = 0
Addon.refreshWordList()
assert(walks == 1, "a visible list is rebuilt on request, got " .. walks)

-- Close it. The frame stays -- it is pooled for next time -- but nothing about
-- it is worth recomputing while it is hidden.
Addon.listFrame:Hide()
walks = 0
Addon.refreshWordList()
assert(walks == 0,
  "a closed list must not walk the dictionary, got " .. walks .. " walks")

-- And the path that actually bit: saving a word. It refreshes the list
-- unconditionally, which is right -- the list has to be correct when reopened --
-- but must cost nothing while the list is shut.
walks = 0
Addon.refreshPanel()
Addon.refreshWordList()
assert(walks == 0, "saving with the list closed must not walk the dictionary either, got " .. walks)

-- Reopening has to show current data: the saving above did not update the list,
-- so opening it must rebuild.
Addon.listFrame:Show()
walks = 0
Addon.refreshWordList()
assert(walks == 1, "reopening rebuilds, so nothing is stale, got " .. walks)

print("list-refresh: ok")
