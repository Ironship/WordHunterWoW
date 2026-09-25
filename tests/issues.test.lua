-- Run from the addon root:  lua tests/issues.test.lua
--
-- The two faults an audit raised against this repository that a test could
-- have caught and none did. Both are the same shape: a correct pattern exists
-- in the very file that gets it wrong, a few lines away, and nothing compared
-- the two.
--
--   #2  Three settings writers index WordHunterWoWDB without checking it is
--       there, while their neighbours guard. Slash commands are registered as
--       Init.lua loads; the saved variables only exist after ADDON_LOADED. The
--       window between is small and real, and a player who types /whw in it
--       gets a Lua error instead of a setting.
--
--   #3  The word-list search rebuilds the whole list on every keystroke, while
--       the resize handler in the same file debounces the identical rebuild.
--       A rebuild walks every word the player has plus the dictionary behind
--       it -- a hundred thousand entries -- so "Schwert" paid for it seven
--       times.
--
-- The debounce is the reason this file replaces C_Timer rather than using the
-- stub's. The stub fires a timer the moment it is made, which is convenient
-- everywhere else and useless here: a debounced rebuild and an undebounced one
-- both come out as "it rebuilt", and the test would pass against the bug.

local node = dofile("tests/wowstub.lua")

dofile("Core.lua")
dofile("Compat.lua")
dofile("UICommon.lua")
dofile("QuestPanel.lua")
dofile("Editor.lua")
dofile("WordList.lua")
-- Harvest before Settings: the page builds a checkbox against the harvest
-- getter, and Settings.lua is only a set of controls over other files'
-- settings. Recall too, for the switch 1.19.0 added.
dofile("Harvest.lua")
dofile("Recall.lua")
dofile("Settings.lua")
local Addon = WordHunterWoW_Addon

-- ---------------------------------------------------------------------------
-- #2: the settings writers, called before the saved variables exist.
--
-- nil rather than an empty table, because nil is the state the client is
-- actually in: the variable does not exist until the client creates it at
-- ADDON_LOADED, and `{}` would pass against the bug.
local SETTERS = {
  { "SetTargetLocale", "deDE", "targetLocale" },
  { "SetOpacity", 0.5, "opacity" },
  { "SetBackgroundStyle", nil, "background" },
}
-- The background key has to be one the addon accepts or the setter refuses
-- before it ever touches the database, and the test would pass on the refusal.
for key in pairs(Addon.BACKGROUNDS or {}) do SETTERS[3][2] = key break end
assert(SETTERS[3][2], "no background style to test with")

for _, case in ipairs(SETTERS) do
  local name, value, settingKey = case[1], case[2], case[3]
  WordHunterWoWDB = nil
  local fn = Addon[name]
  assert(type(fn) == "function", name .. " is missing")
  local ok, err = pcall(fn, value)
  assert(ok, name .. " crashed with no saved variables: " .. tostring(err))
  assert(type(WordHunterWoWDB) == "table" and type(WordHunterWoWDB.settings) == "table",
    name .. " left the database unusable")
  assert(WordHunterWoWDB.settings[settingKey] ~= nil,
    name .. " did not store " .. settingKey)
end

-- And the value survives, rather than the guard quietly swallowing the call.
WordHunterWoWDB = nil
Addon.SetOpacity(0.5)
assert(WordHunterWoWDB.settings.opacity == 0.5,
  "the opacity is stored, not just survived, got " .. tostring(WordHunterWoWDB.settings.opacity))

-- ---------------------------------------------------------------------------
-- #3: the search box waits before it rebuilds.
WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, words = {}, wordsByLocale = {} }
Addon.initializeDatabase()

local walks = 0
local realForEach = Addon.ForEachEffectiveWord
Addon.ForEachEffectiveWord = function(...)
  walks = walks + 1
  return realForEach(...)
end

-- A timer that is made and remembered rather than made and run, which is what
-- a real one does and what the debounce is built on.
local pending, cancelled = nil, 0
C_Timer.NewTimer = function(_, fn)
  local timer = { fn = fn }
  function timer:Cancel() cancelled = cancelled + 1 end
  pending = timer
  return timer
end

Addon.toggleWordList()
local list = Addon.listFrame
assert(list and list.search, "the word list and its search box have to exist")
assert(list:IsShown(), "and the list has to be open, or the rebuild declines to run")

pending, cancelled, walks = nil, 0, 0
local onText = list.search:GetScript("OnTextChanged")
assert(onText, "the search box has no OnTextChanged")

onText(list.search)
assert(walks == 0, "the first keystroke rebuilt the list instead of waiting, walked " .. walks)
assert(pending, "and set no timer to rebuild later")

-- Typing on: each keystroke replaces the one before it, so seven letters cost
-- one rebuild rather than seven.
for _ = 1, 6 do onText(list.search) end
assert(walks == 0, "typing rebuilt the list " .. walks .. " times before the pause")
assert(cancelled == 6, "each keystroke has to cancel the one before it, cancelled " .. cancelled)

pending.fn()
assert(walks == 1, "the pause has to rebuild exactly once, walked " .. walks)

-- Closed before the timer fires -- the list is a window, and the player can
-- shut it mid-word. The rebuild declines rather than working on nothing.
walks = 0
onText(list.search)
list:Hide()
pending.fn()
assert(walks == 0, "a rebuild fired at a closed list, walked " .. walks)


-- ---------------------------------------------------------------------------
-- The options page, and the category is Blizzard's.
--
-- Found in the voiceover addon and present here word for word: the page wrote
-- its own name over category.ID so a later read would find something, and that
-- broke the read it was serving. Settings.OpenToCategory takes the number the
-- client put there; handed a string it opens nothing, and /whw options did
-- nothing at all. Writing into a table the client created taints it besides.
--
-- The category is modelled the way the client builds one -- a numeric ID, a
-- GetID that returns it, and a metatable that records writes rather than
-- allowing them -- because a plain table would accept the overwrite and the
-- test would pass against the bug.
--
-- The first half is unchanged since the page moved into a window of its own in
-- 1.20: Options > AddOns still lists the addon, through a short page, and that
-- page still must not write into the category. The second half used to hold
-- that OpenSettings called OpenToCategory with the number. It calls it with
-- nothing now -- the settings are the addon's own window, which opens in
-- combat and has no category id to get wrong -- so this holds that instead,
-- which also means a string id cannot come back.
local writes, opened = {}, nil
local realSettings = Settings
local category = setmetatable({}, {
  __index = { ID = 4711, GetID = function(self) return rawget(self, "ID") or 4711 end },
  __newindex = function(_, key, value) writes[#writes + 1] = key .. "=" .. tostring(value) end,
})
local registered
Settings = {
  RegisterCanvasLayoutCategory = function(frame) registered = frame return category end,
  RegisterAddOnCategory = function() end,
  OpenToCategory = function(id) opened = id or "nothing" end,
}
-- The harvest counter walks this one, and the stub's stand-in would hand it
-- its own methods to count.
WordHunterWoWCorpus = { version = 1, byLocale = {} }
Addon.settingsPanel, Addon.settingsCategoryPage = nil, nil
Addon.settingsCategory, Addon.settingsCategoryName = nil, nil
Addon.CreateSettingsPanel()

assert(#writes == 0,
  "the page wrote " .. table.concat(writes, ", ") ..
  " into the category the client handed back; that table is Blizzard's and its ID is a number")
assert(registered == Addon.settingsCategoryPage and registered ~= nil,
  "Options > AddOns has to be given the short page, not the window")
assert(Addon.settingsCategory == category and Addon.settingsCategoryName == "WordHunterWoW",
  "and the category is recorded where the addon keeps it")

local window = Addon.settingsPanel
assert(not window:IsShown(), "the window must not be open before anybody asks for it")
Addon.OpenSettings()
assert(window:IsShown(), "OpenSettings did not show the window")
assert(opened == nil, "OpenSettings still went through Settings.OpenToCategory, handed " .. tostring(opened))
window:Hide()

-- The page's own button opens the window too, and closes Blizzard's options
-- first so the window is not opened behind them.
local hidden
local realHide = HideUIPanel
SettingsPanel = CreateFrame("Frame")
SettingsPanel:Show()
HideUIPanel = function(frame) hidden = frame frame:Hide() end
local open = rawget(Addon.settingsCategoryPage, "openButton")
assert(open, "the options page has no button")
open:GetScript("OnClick")(open)
assert(window:IsShown(), "the options page's button did not open the window")
assert(hidden == SettingsPanel, "and it left Blizzard's options open over it")
assert(opened == nil, "the button went through Settings.OpenToCategory")
-- Shown, never toggled: a second press must not close what the first opened.
open:GetScript("OnClick")(open)
assert(window:IsShown(), "a second press of the button closed the window")
window:Hide()
SettingsPanel, HideUIPanel = nil, realHide
Settings = realSettings

-- Where the client has no Settings API at all -- the old interface options --
-- the page goes to InterfaceOptions_AddCategory instead, and still opens the
-- same window.
local added
InterfaceOptions_AddCategory = function(frame) added = frame end
Addon.settingsPanel, Addon.settingsCategoryPage = nil, nil
Addon.settingsCategory, Addon.settingsCategoryName = nil, nil
Addon.CreateSettingsPanel()
assert(added == Addon.settingsCategoryPage and added ~= nil,
  "without the Settings API the page has to be added to the old interface options")
assert(Addon.settingsCategory == nil, "and there is no category to record")
open = rawget(Addon.settingsCategoryPage, "openButton")
open:GetScript("OnClick")(open)
assert(Addon.settingsPanel:IsShown(), "and its button still opens the window")
InterfaceOptions_AddCategory = nil

print("issues: settings writers guarded, search debounced, options page registers and opens the window")
