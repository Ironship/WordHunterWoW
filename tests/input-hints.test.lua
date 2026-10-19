-- Run from the addon root: lua tests/input-hints.test.lua
dofile("tests/wowstub.lua")
local padEnabled, combat, focus, shift = false, false, nil, false
local bindings, keyActions = {}, {}
C_GamePad = { IsEnabled = function() return padEnabled end }
InCombatLockdown = function() return combat end
GetCurrentKeyBoardFocus = function() return focus end
IsShiftKeyDown = function() return shift end
GetBindingKey = function(action) return unpack(bindings[action] or {}) end
GetBindingAction = function(key) return keyActions[key] or "" end
local style = "Xbox"
GetBindingText = function(key)
  if key:match("PAD") and not key:match("NUMPAD") then return style .. ":" .. key end
  return ({ LEFT = "Left", RIGHT = "Right", ESCAPE = "Esc", ENTER = "Enter" })[key] or key
end

for line in io.lines("WordHunterWoW_Mainline.toc") do
  local file = line:match("^(%S+%.lua)%s*$")
  if file then assert(loadfile(file))("WordHunterWoW") end
end
local Addon = WordHunterWoW_Addon
Addon.initializeDatabase()
Addon.createPanel()
Addon.createEditor()
local panel, editor = Addon.panel, Addon.editor
local event = Addon.inputHintsEvents:GetScript("OnEvent")
local function refresh() event(Addon.inputHintsEvents, "UPDATE_BINDINGS") end

assert(editor.prevWord.shortcutHint:GetText() == "Left")
assert(editor.cancel.shortcutHint:GetText() == "Esc")
assert(editor.save.shortcutHint:GetText() == "", "an unbound action must not invent a shortcut")
bindings.WORDHUNTERWOW_SAVE = { "CTRL-S", "SHIFT-F2" }
keyActions["CTRL-S"] = "WORDHUNTERWOW_SAVE"
bindings.WORDHUNTERWOW_WORDS = { "CTRL-W" }
refresh()
assert(editor.save.shortcutHint:GetText() == "CTRL-S / SHIFT-F2", "both bindings are read from the client")
assert(panel.inputHint:GetText():find("CTRL%-W: words"))
local previousHeight = Addon.PanelInputHintHeight(panel)
assert(previousHeight > 0, "the footer reserves space for its visible hints")
bindings.WORDHUNTERWOW_SAVE = { "ALT-S" }
refresh()
assert(editor.save.shortcutHint:GetText() == "ALT-S", "rebinding replaces the old hint")
bindings.WORDHUNTERWOW_SAVE = { "NUMPAD1", "CTRL-NUMPAD2" }
refresh()
assert(editor.save.shortcutHint:GetText() == "NUMPAD1 / CTRL-NUMPAD2", "numpad keys are keyboard bindings")
bindings.WORDHUNTERWOW_SAVE = { "ALT-S" }

padEnabled = true
event(Addon.inputHintsEvents, "CVAR_UPDATE", "GamePadEnable")
assert(editor.save.shortcutHint:GetText() == "Xbox:PAD1")
assert(editor.prevWord.shortcutHint:GetText() == "Xbox:PADLSHOULDER")
assert(panel.inputHint:GetText():find("Xbox:PAD4: reading mode", 1, true))
style = "PlayStation"
event(Addon.inputHintsEvents, "GAME_PAD_ACTIVE_CHANGED")
assert(editor.save.shortcutHint:GetText() == "PlayStation:PAD1", "glyphs follow the client's label style")
assert(not Addon.ControllerHelpText():find("Xbox", 1, true))
Addon.OpenSettings("controller")
assert(Addon.settingsPanel.gamepadNote:GetText():find("PlayStation", 1, true))
Addon.settingsPanel:Hide()

editor:Show()
Addon.selected = { recallPending = true }
refresh()
assert(editor.save.shortcutHint:GetText() == "", "PAD1 rates instead of saving during recall")
assert(editor.prevWord.shortcutHint:GetText() == "", "shoulders do not navigate during recall")
assert(editor.cancel.shortcutHint:GetText() == "", "PAD2 skips the question rather than closing the editor")
assert(editor.cover.prompt:GetText():find("PlayStation:PAD1: rate", 1, true))
Addon.selected.recallPending = false
refresh()

local saved, closed = 0, 0
editor.save:SetScript("OnClick", function() saved = saved + 1 end)
Addon.CloseAll = function() closed = closed + 1; return true end
keyActions.PAD4 = "WORDHUNTERWOW_SAVE"
bindings.WORDHUNTERWOW_SAVE = { "PAD4", "ALT-S" }
refresh()
assert(editor.save.shortcutHint:GetText() == "PlayStation:PAD4 / PlayStation:PAD1")
assert(Addon.ShortcutHint("READING", nil, "PAD4") == "", "a remapped pad button no longer advertises its old action")
assert(Addon.GamePadButton(editor, "PAD4") == true and saved == 1, "the remapped pad action runs once")
keyActions.PAD1 = "WORDHUNTERWOW_CLOSE"
refresh()
assert(editor.save.shortcutHint:GetText() == "PlayStation:PAD4", "an overridden fallback is removed")
assert(Addon.GamePadButton(editor, "PAD1") == true and closed == 1)

Addon.SetGamePadEnabled(false)
assert(editor.save.shortcutHint:GetText() == "ALT-S", "turning off pad controls restores keyboard hints")
assert(Addon.GamePadButton(editor, "PAD4") == false and saved == 1)
assert(not panel.inputHint:GetText():find("PlayStation", 1, true))
Addon.SetGamePadEnabled(true)
padEnabled = false
focus = editor.translation
refresh()
assert(editor.save.shortcutHint:GetText() == "Enter", "the translation field's Enter saves")
assert(editor.prevWord.shortcutHint:GetText() == "", "arrow keys edit text while typing")
assert(Addon.HandleShortcutKey("S") == false, "typing cannot trigger a shortcut")
focus = nil
combat = true
refresh()
assert(editor.prevWord.shortcutHint:GetText() == "", "frame-local keyboard controls are disabled in combat")
assert(editor.save.shortcutHint:GetText() == "ALT-S", "ordinary bindings remain available")
assert(not Addon.HandleShortcutKey("K"), "frame handlers leave native bindings to the game in combat")
local beforeCombat = saved
assert(not Addon.GamePadButton(editor, "PAD4") and saved == beforeCombat,
  "in combat the game runs an explicit pad binding, without a second execution in the frame handler")
combat = false
keyActions["SHIFT-K"] = "WORDHUNTERWOW_SAVE"
shift = true
assert(Addon.HandleShortcutKey("K") == true and saved == 2, "modified keyboard bindings reach the same button")
shift = false
keyActions.K = "WORDHUNTERWOW_SAVE"
editor:GetScript("OnKeyDown")(editor, "K")
assert(saved == 3, "the editor keyboard handler dispatches configured shortcuts")
keyActions.ESCAPE = "WORDHUNTERWOW_SAVE"
editor:GetScript("OnKeyDown")(editor, "ESCAPE")
assert(saved == 4 and closed == 1, "explicit remapping takes priority over the local Escape action")

-- Bindings.xml is loaded separately by WoW; execute its bodies to catch drift.
local xml = assert(io.open("Bindings.xml")):read("*a")
local count = 0
for name, code in xml:gmatch('<Binding name="([^"]+)"[^>]*>(.-)</Binding>') do
  assert(_G["BINDING_NAME_" .. name], "binding has no label: " .. name)
  local action = code:match('RunShortcut%("([^"]+)"%)')
  assert(action, "binding has no dispatcher action")
  local run = Addon.RunShortcut
  Addon.RunShortcut = function(actual) assert(actual == action); count = count + 1 end
  assert((loadstring or load)(code))()
  Addon.RunShortcut = run
end
assert(count == 10, "every user-facing action has a native binding")

C_GamePad = nil
GetCVarBool = function(name) assert(name == "GamePadEnable"); return true end
refresh()
assert(Addon.GamePadHintsEnabled(), "older controller clients use their GamePadEnable CVar")
C_GamePad, GetCVarBool, GetBindingKey, GetBindingText, GetBindingAction = nil, nil, nil, nil, nil
refresh()
assert(not Addon.GamePadHintsEnabled(), "clients without a controller API remain keyboard-only")
assert(editor.prevWord.shortcutHint:GetText() == "LEFT")
assert(editor.save.shortcutHint:GetText() == "")
print("input-hints: ok")
