-- Run from the addon root:  lua tests/recall-hover.test.lua
--
-- The other place a meaning shows: pointing at a German word lights its
-- English equivalent in the column beside it, and clicking it does the same
-- before the editor even opens. With the recall check on, a word that is about
-- to ask for a rating must light only its sentence, and light the word only
-- once the editor has shown the meaning.
--
-- Built on english-highlight-ui.test.lua's frame recording, which is the one
-- way here to read a colour back off the English column.

local node = dofile('tests/wowstub.lua')
local frames = {}
local create = CreateFrame
CreateFrame = function(kind, name, parent, template)
  local f = create(kind, name, parent, template)
  f.parent = parent
  f.glow, f.whwReadingBackground = false, false
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
WordHunterWoW_Addon = {}
dofile('Core.lua')
dofile('Compat.lua')
dofile('Recall.lua')
dofile('UICommon.lua')
dofile('QuestPanel.lua')
local Addon = WordHunterWoW_Addon

local DAY = 24 * 60 * 60
local now = 1700000000
time = function() return now end

WordHunterWoWDB = { settings = { targetLocale = 'deDE', frames = {}, recallCheck = true }, wordsByLocale = { deDE = {
  zuflucht = { word = 'Zuflucht', status = 'learning', translation = 'refuge', statusChangedAt = now - 2 * DAY, updatedAt = now - 2 * DAY },
} } }
Addon.initializeDatabase()
WordHunterWoW_QuestEN = {
  [1] = { title = 'Refuge', description = 'Wait... "Yes!"\n\nFind  the refuge.\n\nFind  the refuge.',
    completion = 'You made it.' },
}
Addon.createPanel()
local panel = Addon.panel
panel:Show()
Addon.lastQuest = { id = 1, text = 'Wartet... "Ja!"\n\nSucht die Zuflucht.\n\nSucht die Zuflucht.', passage = 'offer' }
Addon.refreshPanel()

local function buttons(word)
  local result = {}
  for _, f in ipairs(frames) do
    if f.parent == panel.content and f:IsShown() and rawget(f, 'word') == word then result[#result + 1] = f end
  end
  return result
end
local function highlighted()
  local red, yellow = 0, 0
  for _, f in ipairs(frames) do
    if f.parent == panel.enContent and f:IsShown() then
      local c = f.text.color
      if c[1] == Addon.COLORS.enWordHighlight[1] and c[2] == Addon.COLORS.enWordHighlight[2] then red = red + 1
      elseif c[1] == Addon.COLORS.enHighlight[1] and c[2] == Addon.COLORS.enHighlight[2] then yellow = yellow + 1 end
    end
  end
  return red, yellow
end
-- The companion English window is told the same thing, through the hook it
-- listens on; it is a separate addon and cannot be driven here, so what it
-- is told is what is checked.
local told
Addon.OnHighlightEnglishForWord = function(word, quest, sentenceIndex, occurrence, sentenceOnly)
  told = { word = word, sentenceOnly = sentenceOnly }
end

local button = buttons('Zuflucht')[1]
assert(button and button.key == 'zuflucht', 'the word button knows its key')

-- With the check off: the word lights, which is the behaviour every earlier
-- version had.
Addon.SetRecallCheck(false)
button.scripts.OnEnter(button)
local redOff, yellowOff = highlighted()
assert(redOff == 1, 'with the check off the English word lights, got ' .. redOff)
assert(told and told.word == 'Zuflucht' and not told.sentenceOnly, 'and the companion is told the word')

-- With it on: the sentence only, on hover and on click alike.
Addon.SetRecallCheck(true)
button.scripts.OnLeave(button)
button.scripts.OnEnter(button)
local red, yellow = highlighted()
assert(red == 0, 'a word about to be asked must not have its English lit, got ' .. red)
assert(yellow == redOff + yellowOff, 'the sentence still lights, every token of it: ' .. yellow)
assert(told.sentenceOnly == true, 'and the companion window is told sentence only')

local opened
Addon.openEditor = function(word, context, questId, questTitle, opts)
  opened = { word = word, context = context, questId = questId, questTitle = questTitle, opts = opts }
end
button.scripts.OnClick(button)
assert(opened and opened.word == 'Zuflucht' and opened.context == 'Sucht die Zuflucht.' and opened.questId == 1,
  'the click opens the editor with the sentence the word sits in')
assert(opened.opts and opened.opts.origin == 'panel', 'and says it came from the quest panel')
red = highlighted()
assert(red == 0, 'the click lit the English word before the question was answered')
button.scripts.OnLeave(button)
red = highlighted()
assert(red == 0, 'and leaving the word keeps the selection sentence-only')

-- The editor, once it has shown the meaning, asks for the word to be lit.
Addon.RevealSelectedHighlight()
red = highlighted()
assert(red == 1, 'after the reveal the English word lights as for any click')
assert(not told.sentenceOnly, 'and the companion is told so')

-- Rated a moment ago: not gated any more, and nothing was redrawn to know it.
button.scripts.OnLeave(button)
Addon.RecordRating('zuflucht', 4, now)
button.scripts.OnEnter(button)
red = highlighted()
assert(red == 1, 'a rating given a moment ago counts at once on hover, got ' .. red)

-- A word with no entry of its own is never gated, however the pack marks it.
Addon.RegisterDictionaryProvider('deDE', 'test', { sucht = { translation = 'seek', status = 'learning' } })
Addon.refreshPanel()
local sucht = buttons('Sucht')[1]
assert(sucht, 'the dictionary word is on the panel')
sucht.scripts.OnEnter(sucht)
assert(told.word == 'Sucht' and not told.sentenceOnly, 'a dictionary Learning word is not gated')

print('recall-hover: ok')
