-- Run from WordHunterWoW: lua tests/voice-sentence-highlight.test.lua
-- Keep WordHunterWoW-ENPanel and WordHunterWoW-Voice-DE beside it.
--
-- The German voiceover tells the English side which sentence it is speaking.
-- That is the one caller with a sentence number and no word -- nobody clicked
-- anything -- and every link in the chain used to drop it on the floor. The
-- base panel's own English column asked for a word before it would look
-- anything up, and the voiceover called the notification the base addon sends
-- out after painting rather than the function that paints. In the integrated
-- layout, which is the default, that left nothing lit anywhere: the column was
-- never painted and the separate window was not on screen to hear about it.
--
-- So the three addons are loaded together here. Each of them can be made to
-- pass on its own while the thing the player sees stays dark.

local node = dofile('tests/wowstub.lua')
local frames = {}
local create = CreateFrame
CreateFrame = function(kind, name, parent, template)
  local f = create(kind, name, parent, template)
  f.parent = parent
  f.glow = false
  function f:CreateTexture()
    local texture = node()
    function texture:SetColorTexture(...) self.color = {...} end
    return texture
  end
  function f:GetHeight() return rawget(self, 'h') or 240 end
  function f:GetWidth() return rawget(self, 'w') or 430 end
  function f:GetVerticalScroll() return rawget(self, '_scroll') or 0 end
  function f:SetVerticalScroll(value) self._scroll = value end
  function f:CreateFontString()
    local fs = node()
    function fs:SetTextColor(r, g, b) self.color = { r, g, b } end
    return fs
  end
  frames[#frames + 1] = f
  return f
end

-- Both namespaces are assigned here rather than left to the file that declares
-- them. A stub that manufactures a table for an unknown global would otherwise
-- hand each file a namespace answering to every name, and an assertion that a
-- function is there would pass whether or not it is.
WordHunterWoW_Addon = {}
WordHunterWoW_Voice = {}
WordHunterWoW_Voice_Parts = {}

dofile('Core.lua')
dofile('Compat.lua')
dofile('UICommon.lua')
dofile('QuestPanel.lua')
local Addon = WordHunterWoW_Addon
assert(type(rawget(Addon, 'HighlightEnglishForWord')) == 'function',
  'the base addon must publish HighlightEnglishForWord: that is the function that paints its own English column')

WordHunterWoWDB = {
  settings = { targetLocale = 'deDE', integratedLayout = true, frames = {} },
  wordsByLocale = {},
}
Addon.initializeDatabase()

-- One sentence per paragraph on both sides, so a sentence number means the same
-- thing in either language and the mapping is not what is under test. Each is
-- over thirty characters, which is what makes the voiceover give it a clip of
-- its own -- below that the generator joins it to its neighbour.
local german = 'Der erste Satz steht hier ganz allein.'
  .. '\n\nDer zweite Satz steht dort drüben.'
  .. '\n\nDer dritte Satz ist schon vergangen.'
local english = 'The first sentence stands here alone.'
  .. '\n\nThe second sentence stands over there.'
  .. '\n\nThe third sentence is already gone.'
WordHunterWoW_QuestEN = { [1] = { title = 'Three Sentences', description = english } }

Addon.createPanel()
local panel = Addon.panel
panel:Show()
Addon.ApplyIntegratedLayout()
assert(Addon.GetIntegratedLayout(), 'this test is about the integrated layout, which is the default one')
Addon.lastQuest = { id = 1, text = german, passage = 'offer' }
Addon.refreshPanel()

-- How many words of each English sentence the column is currently lighting, and
-- in which of the two colours.
local function litInColumn()
  local sentence, word = {}, {}
  for _, f in ipairs(frames) do
    if f.parent == panel.enContent and f:IsShown() then
      local c = rawget(f.text, 'color')
      local index = rawget(f, 'sentenceIndex')
      if c and index then
        if c[1] == Addon.COLORS.enWordHighlight[1] and c[2] == Addon.COLORS.enWordHighlight[2] then
          word[index] = (word[index] or 0) + 1
        elseif c[1] == Addon.COLORS.enHighlight[1] and c[2] == Addon.COLORS.enHighlight[2] then
          sentence[index] = (sentence[index] or 0) + 1
        end
      end
    end
  end
  return sentence, word
end

local function onlySentenceLit(want, words, why)
  local sentence, word = litInColumn()
  assert(next(word) == nil, why .. ': a word was picked out, but the voiceover has no clicked word to pick out')
  for index in pairs(sentence) do
    assert(index == want, why .. ': English sentence ' .. index .. ' lit up instead of ' .. want)
  end
  assert(sentence[want] == words,
    why .. ': ' .. tostring(sentence[want] or 0) .. ' of the ' .. words
      .. ' words of English sentence ' .. want .. ' lit up')
end

-- The base panel's own column, asked directly. A sentence number with no word
-- is the whole of what the voiceover has to give it.
Addon.HighlightEnglishForWord(nil, 2, nil, true)
onlySentenceLit(2, 6, 'the integrated English column ignored a sentence index with no word')

-- The separate English window, so the notification can be counted arriving.
WordHunterWoWENPanelDB = {}
GetQuestID = function() return 1 end
QuestFrame:Show()
-- The siblings are separate repositories and a clone of this one alone does not
-- have them. Skipped rather than failed in that case, and said out loud rather
-- than skipped in silence: a check that quietly stops running is how coverage
-- disappears, and this suite has paid for that lesson once already.
local function beside(path, what)
  local f = io.open(path, "r")
  if f then f:close() return true end
  print("  SKIPPED: " .. what .. " is not beside this repository, so the "
    .. "cross-addon half of this file did not run")
  return false
end

if not beside("../WordHunterWoW-ENPanel/ENPanel.lua", "WordHunterWoW-ENPanel") then print("voice-sentence-highlight: skipped") os.exit(0) end
if not beside("../WordHunterWoW-Voice-DE/Voice.lua", "WordHunterWoW-Voice-DE") then print("voice-sentence-highlight: skipped") os.exit(0) end
assert(loadfile('../WordHunterWoW-ENPanel/ENPanel.lua'))('WordHunterWoW-ENPanel')
local enEvents = frames[#frames]
enEvents.scripts.OnEvent(nil, 'ADDON_LOADED', 'WordHunterWoW-ENPanel')
local relay = assert(rawget(Addon, 'OnHighlightEnglishForWord'),
  'the English window did not register itself with the base addon')
local relayed = 0
Addon.OnHighlightEnglishForWord = function(...)
  relayed = relayed + 1
  return relay(...)
end

-- The voiceover itself, not a stand-in for it.
PlaySoundFile = function() return true, 1 end
StopSound = function() end
dofile('../WordHunterWoW-Voice-DE/Naming.lua')
dofile('../WordHunterWoW-Voice-DE/Voice.lua')
local Voice = WordHunterWoW_Voice
assert(type(rawget(Voice, 'PlayQuest')) == 'function', 'the voice engine did not load')
WordHunterWoW_Voice_Parts['WordHunterWoW-Voice-DE-Classic'] = { quests = { 1, 100 } }
Voice.ForgetParts()
local spans = Voice.ClipSpans(german)
assert(#spans == 3 and spans[1].first == 1 and spans[2].first == 2 and spans[3].first == 3,
  'these three sentences did not become three clips, so the rest of this would measure the grouping and not the highlight')

Addon.HighlightEnglishForWord(nil, nil, nil, nil)
assert(next((litInColumn())) == nil, 'the column did not clear between the two halves of this test')
relayed = 0
assert(Voice.PlayQuest(1, 'description', 2), 'the clip refused to play, so nothing was ever highlighted')
onlySentenceLit(2, 6, 'reading the quest aloud left the integrated English column dark')
assert(relayed == 1,
  'the separate English window was told about the sentence ' .. relayed .. ' times, and it must be exactly one')

-- And the arrangement that already worked must go on working, once and no more.
WordHunterWoWDB.settings.integratedLayout = false
Addon.ApplyIntegratedLayout()
enEvents.scripts.OnEvent(nil, 'QUEST_DETAIL')
local enPanel = Addon.enPanel
assert(enPanel and enPanel.text:GetText() == english,
  'the separate English window is not showing this quest: ' .. tostring(enPanel and enPanel.text:GetText()))
relayed = 0
assert(Voice.PlayQuest(1, 'description', 3), 'the clip refused to play in the separate-window layout')
assert(relayed == 1,
  'the separate English window was told about the sentence ' .. relayed .. ' times, and it must be exactly one')
local hl = Addon.ColorHex('enHighlight')
local expected = 'The first sentence stands here alone.'
  .. '\n\nThe second sentence stands over there.\n\n'
  .. hl .. 'The|r ' .. hl .. 'third|r ' .. hl .. 'sentence|r '
  .. hl .. 'is|r ' .. hl .. 'already|r ' .. hl .. 'gone.|r'
assert(enPanel.text:GetText() == expected,
  'the separate English window did not follow the voiceover: ' .. tostring(enPanel.text:GetText()))

print('voice-sentence-highlight: ok')
