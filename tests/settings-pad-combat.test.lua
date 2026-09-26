-- Run from the addon root:  lua tests/settings-pad-combat.test.lua
--
-- B hides the settings window with its pass-through flag at "keep" (Gamepad.lua
-- sets the flag after the press), and in a fight SafePropagate cannot set it
-- back. Opened again with /whw settings in a fight, the window must not keep
-- the buttons it does not use.

dofile("tests/wowstub.lua")
dofile("Core.lua")
dofile("Compat.lua")
dofile("Gamepad.lua")
dofile("Recall.lua")
dofile("UICommon.lua")
dofile("Editor.lua")
dofile("QuestPanel.lua")
dofile("WordList.lua")
dofile("Harvest.lua")
dofile("Settings.lua")
local Addon = WordHunterWoW_Addon

WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, wordsByLocale = {} }
WordHunterWoWCorpus = { version = 1, byLocale = {} }
Addon.initializeDatabase()
Addon.createPanel()
Addon.createEditor()

local combat = false
InCombatLockdown = function() return combat end
local window = Addon.CreateSettingsPanel()
-- The client refuses the call in combat; SafePropagate must never make it then.
local flag = true
window.SetPropagateKeyboardInput = function(_, v)
  assert(not combat, "SetPropagateKeyboardInput called in combat")
  flag = v
end
local press = window:GetScript("OnGamePadButtonDown")

Addon.OpenSettings()
press(window, "PAD2")
assert(not window:IsShown(), "B did not close the window")
-- The fight starts: the client fires PLAYER_REGEN_DISABLED, then locks down.
local onEvent = window:GetScript("OnEvent")
if onEvent then onEvent(window, "PLAYER_REGEN_DISABLED") end
combat = true
Addon.OpenSettings()
assert(window:IsShown(), "/whw settings did not open the window in combat")
press(window, "PAD1")
assert(flag == true, "the window went into the fight keeping A, the D-pad, X and Y from the game")
print("settings-pad-combat: ok")
