-- Run from the addon root:  lua tests/spoken-audio.test.lua
--
-- The Spoken addon reads quests aloud and puts its own Play button on
-- Blizzard's quest log. This is the same button in this panel, so a player
-- reading a quest here can hear it without leaving for the log.
--
-- Two things matter and both are about not breaking what is already there. The
-- button appears only where it can do something -- Spoken installed, and the
-- text on screen a real quest rather than a book, a journal page or a line of
-- gossip -- and when it is not there the action row is exactly the row it has
-- always been, three buttons with no hole where a fourth might have been.

local node = dofile("tests/wowstub.lua")
UIParent = node()

dofile("Core.lua")
dofile("Compat.lua")
dofile("UICommon.lua")
dofile("QuestPanel.lua")
local Addon = WordHunterWoW_Addon

WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, words = {}, wordsByLocale = {} }
Addon.initializeDatabase()
Addon.createPanel()
local panel = Addon.panel

-- The button, and the row it would sit in.
local playBtn = assert(panel.questAudioButton, "the panel has to have a Play button")

-- Nothing installed: no button, and the row is the three it has always been.
assert(rawget(_G, "Spoken") == nil, "this has to start without Spoken to mean anything")
Addon.RefreshQuestAudioButton()
assert(not playBtn:IsShown(), "with no Spoken the Play button must not be up")
assert(#panel.actions == 3, "and the row must still be three buttons, got " .. #panel.actions)

-- A book and a line of gossip come through this panel and neither has quest
-- audio, so neither may offer Play.
Addon.lastQuest = { id = 0, title = "Kearnens Tagebuch", text = "Die Wachen warten.", passage = "book" }
Addon.RefreshQuestAudioButton()
assert(not playBtn:IsShown(), "a book has no quest audio and must not offer Play")

-- Spoken's player without its quest feature is half an addon: it cannot
-- resolve a quest id to a file, so there is still nothing to play.
Spoken = { IsCompatible = function() return true end }
VoiceOver = { Enums = { SoundEvent = { QuestAccept = 1 } } }
Addon.lastQuest = { id = 184, title = "Der Auftrag", text = "Ein Hippogryph wurde gesehen.", passage = "offer" }
Addon.RefreshQuestAudioButton()
assert(not playBtn:IsShown(),
  "the Spoken player without Spoken_Quests cannot play a quest and must not offer Play")

-- The real thing. Both objects present, as Spoken's own quest-log button has
-- them. The queue is modelled as a queue: a clip that has been removed is not
-- in it any more, which is what makes "is this playing" mean anything.
local queue, removed = {}, {}
VoiceOver.Player = {
  PlayNow = function(_, clip) queue[#queue + 1] = clip return true end,
  Remove = function(_, clip)
    removed[#removed + 1] = clip
    for i, c in ipairs(queue) do
      if c == clip then table.remove(queue, i) break end
    end
  end,
  Contains = function(_, clip)
    for _, c in ipairs(queue) do if c == clip then return true end end
    return false
  end,
  Queued = function() return queue end,
}
Addon.RefreshQuestAudioButton()
assert(playBtn:IsShown(), "with Spoken and a real quest the Play button must be up")
assert(#panel.actions == 3,
  "the row's own list stays three; the Play button joins the row only while it is up, got "
  .. #panel.actions)

-- Pressing it plays this quest's opening line -- the same line Blizzard's own
-- Play button reads, which is the point of the whole thing.
Addon.ToggleQuestAudio()
assert(#queue == 1, "pressing Play has to start exactly one line, got " .. #queue)
assert(queue[1].questID == 184, "for the quest on screen, got " .. tostring(queue[1] and queue[1].questID))
assert(queue[1].event == 1, "the opening line, as the quest log's button plays it")
assert(playBtn:GetText() == "Stop", "and the button has to turn into Stop, got " .. tostring(playBtn:GetText()))

-- A second press stops it rather than stacking the same line twice.
local started = queue[1]
Addon.ToggleQuestAudio()
assert(#queue == 0 and #removed == 1 and removed[1] == started,
  "a second press must stop the line it started")
assert(playBtn:GetText() == "Play", "and the button goes back to Play")

-- Switching to a book drops the button even though Spoken is still installed.
Addon.lastQuest = { id = 0, title = "Ein Brief", text = "Lieber Bruder.", passage = "book" }
Addon.RefreshQuestAudioButton()
assert(not playBtn:IsShown(), "a book must not offer Play no matter what is installed")

-- And an installed-but-broken Spoken is not enough to draw a button with.
Addon.lastQuest = { id = 184, title = "Der Auftrag", text = "Ein Hippogryph.", passage = "offer" }
VoiceOver.Player.PlayNow = function() error("player is broken") end
Addon.RefreshQuestAudioButton()
assert(playBtn:IsShown(), "the button is about the quest, not about the player working")
assert(Addon.ToggleQuestAudio() == false, "a player that throws must not claim it played")
assert(#removed == 1, "and must not leave a stop behind")

print("spoken-audio: ok")
