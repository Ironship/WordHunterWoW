-- Run from the addon root:  lua tests/dialogue-replacements.test.lua
--
-- Several addons replace the quest dialogue with a window of their own and
-- leave Blizzard's QuestFrame hidden for good. The panel decides whether to
-- open by asking whether the player is at a quest giver, and that question was
-- answered by QuestFrame:IsShown() alone -- so with any of them installed the
-- panel stopped appearing, the vocabulary stopped being clickable, and the
-- reader's buttons never arrived, all three from the same line.
--
-- This was first written for Lorewalker, which was then uninstalled in favour
-- of DialogueUI, and the bug came straight back. Hence a list, and hence a
-- test that holds both of them and does not care which is installed.

local Addon = {}
WordHunterWoW_Addon = Addon
dofile("Compat.lua")
local Compat = Addon.Compat
assert(Compat, "Compat.lua did not attach itself to the addon table")
assert(Compat.ReplacementQuestFrame, "Compat has no ReplacementQuestFrame")

local function frame(isShown, fields)
  local f = fields or {}
  function f:IsShown() return isShown end
  function f:HookScript(_, handler) self.hooked = handler end
  return f
end

local function clear()
  QuestFrame, DUIQuestFrame, LWDialogFrame = nil, nil, nil
end

-- Nothing installed: the answer must be exactly what it always was ------------
clear()
QuestFrame = frame(true)
assert(Compat.NpcQuestFrameShown(), "Blizzard's own quest frame stopped counting")
QuestFrame = frame(false)
assert(not Compat.NpcQuestFrameShown(), "a hidden quest frame counted as a quest giver")
clear()
assert(not Compat.NpcQuestFrameShown(), "a client with no quest frame at all blew up")
print("replacements: with none installed the answer is unchanged")

-- DialogueUI: one window for quests and gossip, so no child to check ----------
clear()
QuestFrame = frame(false)
DUIQuestFrame = frame(true)
assert(Compat.NpcQuestFrameShown(), "DialogueUI's window was not recognised")
assert(Compat.ReplacementQuestFrame() == DUIQuestFrame, "the wrong frame was handed back")
DUIQuestFrame = frame(false)
assert(not Compat.NpcQuestFrameShown(), "a closed DialogueUI window counted as open")
print("replacements: DialogueUI's DUIQuestFrame counts")

-- Lorewalker: the quest half counts, the gossip list does not -----------------
clear()
QuestFrame = frame(false)
LWDialogFrame = frame(true, {QuestFrame = frame(true), GossipFrame = frame(false)})
assert(Compat.NpcQuestFrameShown(), "Lorewalker's quest window was not recognised")
LWDialogFrame = frame(true, {QuestFrame = frame(false), GossipFrame = frame(true)})
assert(not Compat.NpcQuestFrameShown(), "a gossip list was treated as a quest giver")
LWDialogFrame = frame(true)
assert(not Compat.NpcQuestFrameShown(), "a window with no QuestFrame field blew up")
print("replacements: Lorewalker's quest half counts, its gossip list does not")

-- Both at once, and Blizzard's still winning ----------------------------------
clear()
QuestFrame = frame(true)
DUIQuestFrame = frame(false)
assert(Compat.NpcQuestFrameShown(), "Blizzard's frame stopped counting once a replacement existed")

-- The OnShow hook, which is what covers a window that goes up a frame late ----
clear()
assert(Compat.HookReplacementDialogue(function() end) == false,
  "it claimed to hook a window that is not installed")
DUIQuestFrame = frame(false)
local calls = 0
local handler = function() calls = calls + 1 end
assert(Compat.HookReplacementDialogue(handler), "it did not hook DialogueUI's window")
assert(DUIQuestFrame.hooked == handler, "the handler was not the one passed in")
local first = DUIQuestFrame.hooked
DUIQuestFrame.hooked = nil
Compat.HookReplacementDialogue(handler)
assert(DUIQuestFrame.hooked == nil, "it hooked the same window twice")
assert(first, "sanity: the first hook was never recorded")
print("replacements: the window is hooked once and only once")

clear()
print("replacements: ok")
