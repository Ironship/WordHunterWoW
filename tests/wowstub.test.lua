-- Run from the addon root:  lua tests/wowstub.test.lua
--
-- The stub itself. Everything else in this directory is measured through it, so
-- when it answers a question it was never asked it does not fail -- it quietly
-- agrees with whatever it is shown, and the tests built on it go green for no
-- reason. That has now happened three times in the same file: GetWidth returned
-- a manufactured table instead of a number for any frame that was anchored
-- rather than sized; GetText did the same for a font string nothing had written
-- to; and _G manufactured a frame for any name beginning "WordHunterWoW", which
-- includes WordHunterWoW_Addon itself -- so the addon namespace was a
-- manufacturing node and assert(Addon.AnythingYouLike) passed everywhere.
--
-- So: what the stub must invent, and what it must refuse to.

local node = dofile("tests/wowstub.lua")

-- Refuse: the addon's own namespace. Core.lua reads this global before it
-- assigns it, so if the stub answers, the table the whole suite talks to is a
-- manufacturing node rather than the addon.
assert(rawget(_G, "WordHunterWoW_Addon") == nil, "the namespace must not exist before Core.lua makes it")
assert(WordHunterWoW_Addon == nil, "and reading it must not bring it into being")

-- Refuse: the saved variables. A test has to be able to say "this is a fresh
-- install", and it cannot if the file it would be missing is manufactured on
-- sight. The five are the ones both .toc files declare.
for _, name in ipairs({ "WordHunterWoWDB", "WordHunterWoWExport", "WordHunterWoWLanguage",
                        "WordHunterWoWCorpus", "WordHunterWoWCorpusExport" }) do
  assert(_G[name] == nil, name .. " is a saved variable, and a fresh install has none")
end

-- Refuse: the quest text the separate ENPanel addon publishes. Not everyone has
-- it installed, and the panel has a branch for that.
assert(WordHunterWoW_QuestEN == nil, "the ENPanel is a separate addon and may not be there")

-- Refuse: anything that is not an addon name at all.
assert(_G.QuestFrameDetalPanel == nil, "a typo in a Blizzard global has to stay a typo")

dofile("Core.lua")
local Addon = WordHunterWoW_Addon
assert(Addon == rawget(_G, "WordHunterWoW_Addon"), "Core.lua's own table is what the tests get")
-- The point of all of it: a symbol the addon does not have reads as missing, so
-- an assertion about one can fail.
assert(rawget(Addon, "SymbolThatDoesNotExist") == nil, "nothing defines this")
assert(Addon.SymbolThatDoesNotExist == nil,
  "a field the addon has not got must read nil -- an existence assertion is worthless otherwise")

-- Invent: the children a frame template hangs off a named frame. The client
-- really does create these, and Settings.lua looks up three per slider by name.
local slider = CreateFrame("Slider", "WordHunterWoWProbeSlider")
assert(_G.WordHunterWoWProbeSlider == slider, "a named frame is reachable by its name")
for _, suffix in ipairs({ "Text", "Low", "High" }) do
  assert(type(_G["WordHunterWoWProbeSlider" .. suffix]) == "table",
    "a template child named after the frame has to be answered: " .. suffix)
end
-- But only for a frame that exists. The name has to be earned, not guessed.
assert(_G.WordHunterWoWNoSuchFrameText == nil, "no frame, no children")

-- And the refusals above outrank the rule. A frame whose name happens to be the
-- start of a saved variable's would otherwise reopen the hole by the back door,
-- which is the whole reason those names are written down rather than left to be
-- inferred from whatever CreateFrame has been handed.
CreateFrame("Frame", "WordHunterWoWCorpus")
assert(_G.WordHunterWoWCorpusExport == nil,
  "a frame named like a saved variable must not start manufacturing one")

-- A frame's own bookkeeping is the stub's, not a child frame. These read back as
-- the absence they are, or as the documented fallback.
local frame = CreateFrame("Frame")
assert(frame:GetText() == nil, "a font string nothing has written to has no text")
assert(type(frame:GetWidth()) == "number", "an unsized frame answers its width with a number")
assert(type(frame:GetHeight()) == "number", "and its height")
assert(frame:GetAnchor("TOPLEFT") == nil, "a point that was never set has no offset")
frame:SetText("Hund")
assert(frame:GetText() == "Hund", "and what was written comes back")

print("wowstub: ok")
