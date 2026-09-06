-- Run from WordHunterWoW: lua tests/english-title-only.test.lua
--
-- The integrated English column carries the same three notices the separate
-- English window does, and had the same hole in them. Two of the three name the
-- passage being shown in place of the one that is missing -- the opening text,
-- or the objective -- and a record that is a title and nothing else has
-- neither, so whichever notice ran was pointing at an empty column. Nearly ten
-- thousand of the shipped Retail records are that shape, and they read as real
-- quests rather than as leftovers.

local node = dofile('tests/wowstub.lua')
local frames = {}
local create = CreateFrame
CreateFrame = function(kind, name, parent, template)
  local f = create(kind, name, parent, template)
  f.parent = parent
  function f:CreateTexture()
    local texture = node()
    function texture:SetColorTexture(...) self.color = {...} end
    return texture
  end
  function f:GetHeight() return rawget(self, 'h') or 240 end
  function f:GetWidth() return rawget(self, 'w') or 430 end
  function f:CreateFontString()
    local fs = node()
    function fs:SetTextColor(r, g, b) self.color = { r, g, b } end
    return fs
  end
  frames[#frames + 1] = f
  return f
end

-- Assigned rather than left to Core.lua to invent, so that a stub which
-- manufactures a table for an unknown global cannot answer for a label that is
-- not there.
WordHunterWoW_Addon = {}
dofile('Core.lua')
dofile('Compat.lua')
dofile('UICommon.lua')
dofile('QuestPanel.lua')
local Addon = WordHunterWoW_Addon
local LABELS = Addon.LABELS
for _, key in ipairs({ 'enOfferOnly', 'enNoOffer', 'enNoText' }) do
  assert(type(rawget(LABELS, key)) == 'string', 'LABELS.' .. key .. ' is missing')
end
-- What the wording has to be, rather than what it happens to say: the notice
-- for a record with nothing in it must not send the reader looking for a
-- passage, which is the whole of the complaint.
assert(not LABELS.enNoText:lower():find('objective'),
  'the notice for a quest with no English text promises an objective: ' .. LABELS.enNoText)
assert(not LABELS.enNoText:lower():find('opening text'),
  'the notice for a quest with no English text promises opening text: ' .. LABELS.enNoText)

WordHunterWoWDB = {
  settings = { targetLocale = 'deDE', integratedLayout = true, frames = {} },
  wordsByLocale = {},
}
Addon.initializeDatabase()

WordHunterWoW_QuestEN = {
  [1] = { title = 'Complete', description = 'The captain wants a word with you.' },
  [2] = { title = 'Objective Only', description = '', objectives = 'Speak with Chef Grual.' },
  [3] = { title = 'Waking Naralex', description = '', objectives = '' },
}

Addon.createPanel()
local panel = Addon.panel
panel:Show()
Addon.ApplyIntegratedLayout()
assert(Addon.GetIntegratedLayout(), 'this is about the column inside the quest panel, which is the default layout')

-- The column, split into the text it is showing and the notice under it. They
-- are the same pooled frames, told apart by the flag the layout sets.
local function column()
  local body, notice = {}, {}
  for _, f in ipairs(frames) do
    if f.parent == panel.enContent and f:IsShown() then
      local into = rawget(f, 'caveat') and notice or body
      into[#into + 1] = tostring(f.text:GetText())
    end
  end
  return table.concat(body, ' '), table.concat(notice, ' ')
end

local function render(questId, passage)
  Addon.lastQuest = { id = questId, text = 'Ein deutscher Satz steht hier.', passage = passage or 'offer' }
  Addon.refreshPanel()
  return column()
end

local body, notice = render(1)
assert(notice == '', 'a complete record was given a notice about missing text: ' .. notice)
assert(body:find('captain', 1, true), 'the English text itself went missing: ' .. body)

body, notice = render(2)
assert(notice == LABELS.enNoOffer, 'a record with only an objective lost its own notice: ' .. notice)
assert(body:find('Grual', 1, true), 'the objective went missing: ' .. body)

body, notice = render(3)
assert(body == '', 'a record that is a title and nothing else showed something anyway: ' .. body)
assert(notice ~= LABELS.enNoOffer,
  'a quest with no English text at all still promises an objective it does not have: ' .. notice)
assert(notice == LABELS.enNoText, 'wrong notice for a quest with no English text at all: ' .. notice)

-- The progress and hand-in frames reach the same record by a different branch,
-- and that one used to offer the opening text instead.
for _, passage in ipairs({ 'progress', 'reward' }) do
  body, notice = render(3, passage)
  assert(notice ~= LABELS.enOfferOnly,
    passage .. ' on a record with no English text offers opening text that does not exist: ' .. notice)
  assert(notice == LABELS.enNoText, passage .. ': wrong notice for a quest with no English text: ' .. notice)
end

-- And a record that does have an opening text still says the right thing when
-- the passage on screen is one Blizzard publishes nothing for.
body, notice = render(1, 'reward')
assert(notice == LABELS.enOfferOnly, 'the missing-passage notice was lost: ' .. notice)

print('english-title-only: ok')
