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

print("issues: settings writers guarded, search debounced")
