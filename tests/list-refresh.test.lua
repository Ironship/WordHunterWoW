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

-- Opening it must fill it. The guard above declines to work on a hidden window,
-- so opening has to Show first and refresh after -- the other order left the
-- list empty every time it was opened, which is worse than the stutter it was
-- meant to cure.
walks = 0
Addon.toggleWordList()
assert(Addon.listFrame, "the list frame should exist once opened")
assert(Addon.listFrame:IsShown(), "and be on screen")
assert(walks >= 1,
  "opening the list has to fill it: the window was shown without a rebuild")

-- And a refresh asked for while it is open does the work.
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

-- Built once, and a second call hands back what the player is looking at.
--
-- Nothing in the game calls these twice: ADDON_LOADED fires once per addon and
-- Init.lua's branch is guarded by the addon's own name. The cost is not a crash
-- -- it is that a second call would quietly abandon the window that is open,
-- and the position dragged onto it, for an identical empty one. That has
-- already happened inside this suite, where reaching for the frame by calling
-- the constructor again reset state the rest of the file was standing on.
Addon.createPanel()
Addon.createEditor()
local firstPanel, firstEditor = Addon.panel, Addon.editor
assert(firstPanel and firstEditor, "the panel and editor were never built")
firstPanel.marker, firstEditor.marker = "in use", "in use"
assert(Addon.createPanel() == firstPanel, "createPanel built a second panel")
assert(Addon.panel == firstPanel and rawget(Addon.panel, "marker") == "in use",
  "a second createPanel replaced the panel already on screen")
assert(Addon.createEditor() == firstEditor, "createEditor built a second editor")
assert(Addon.editor == firstEditor and rawget(Addon.editor, "marker") == "in use",
  "a second createEditor replaced the editor already on screen")
-- Cleared, it starts over, which is what lets a test build a fresh one.
Addon.panel = nil
assert(Addon.createPanel() ~= firstPanel,
  "clearing Addon.panel did not let a new one be built")
print("  the panel and editor are built once, and a second call returns them")

print("list-refresh: ok")
