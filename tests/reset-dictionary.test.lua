-- Run from the addon root:  lua tests/reset-dictionary.test.lua
--
-- "Reset to dictionary" used to be offered whenever the word was in a
-- dictionary at all, whether or not there was anything to reset. That makes the
-- one question a player actually has -- have I changed this word, or is it
-- still the pack's own wording? -- answerable only by pressing the button and
-- seeing what happens, which is exactly the thing that destroys the answer.
--
-- So: hidden when the word is in no dictionary, greyed when the boxes already
-- hold the dictionary's wording, live as they type, and a confirmation showing
-- what it would put back before it overwrites anything.
--
-- This drives the addon's own functions. The first version of this test
-- restated them here instead, and three of four deliberate breakages sailed
-- straight through it.

strlower = string.lower
strtrim = function(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
time = os.time
date = os.date
GetLocale = function() return "deDE" end
UISpecialFrames = {}
tContains = function(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
tinsert = table.insert
InputScrollFrame_OnLoad = function() end

-- Every frame is a table that answers any call with a no-op and any field with
-- another such table, so the editor can build itself without the game.
local function node()
  local t = { scripts = {} }
  -- Scripts are kept rather than dropped: the test presses the real button.
  function t:SetScript(name, fn) self.scripts[name] = fn end
  function t:HookScript(name, fn) self.scripts[name] = fn end
  function t:GetScript(name) return self.scripts[name] end
  return setmetatable(t, {
    __index = function(self, key)
      local made = node()
      rawset(self, key, made)
      return made
    end,
    __call = function(self) return self end,
  })
end
CreateFrame = function() return node() end

dofile("Core.lua")
dofile("UICommon.lua")
dofile("Editor.lua")
local Addon = WordHunterWoW_Addon
assert(Addon.createEditor and Addon.updateResetDictionary,
  "Editor.lua must provide the editor and the button's state")

Addon.createEditor()
local editor = Addon.editor
assert(editor, "createEditor should expose the editor")

-- The three widgets under test are the addon's own, kept as they are so the
-- button's real OnClick still fires. Only the calls this test observes are
-- given behaviour; everything else stays a no-op.
local button = editor.resetDictionary
function button:SetShown(v) self.shown = v end
function button:Enable() self.enabled = true end
function button:Disable() self.enabled = false end

local function speak(b)
  function b:GetText() return self.value end
  function b:SetText(v) self.value = v end
  return b
end
speak(editor.translation)
speak(editor.note)

local function open(dict, translation, note)
  Addon.selected = { dictionaryEntry = dict }
  editor.translation:SetText(translation or "")
  editor.note:SetText(note or "")
  button.shown, button.enabled = nil, nil
  Addon.updateResetDictionary()
end

local DICT = { translation = "blade", note = "from Old High German" }

-- no dictionary entry: nothing to reset to, so the button is not there at all
open(nil, "my own guess", "my own note")
assert(button.shown == false, "with no dictionary entry the button should be hidden")

-- the pack's own wording, untouched: present, but there is nothing to undo
open(DICT, "blade", "from Old High German")
assert(button.shown == true, "with a dictionary entry the button belongs on screen")
assert(button.enabled == false, "unchanged text means nothing to reset")

open(DICT, "sword", "from Old High German")
assert(button.enabled == true, "a different meaning is a change")

-- a changed note with the meaning left alone. This is the case that matters to
-- someone auditing their own edits, and the easiest one to miss.
open(DICT, "blade", "my own note")
assert(button.enabled == true, "a different note is a change too")

open(DICT, "sword", "my own note")
assert(button.enabled == true)

-- typing the dictionary's wording back greys it again: the button follows the
-- boxes, it is not decided once when the word opened
editor.translation:SetText("blade")
editor.note:SetText("from Old High German")
Addon.updateResetDictionary()
assert(button.enabled == false, "typing the original back means there is nothing to reset")

-- whitespace is not an edit worth offering to undo
open(DICT, "  blade  ", "from Old High German\n")
assert(button.enabled == false, "trailing space is not a change")

open({ translation = "blade", note = "" }, "blade", "")
assert(button.enabled == false)
open({ translation = "blade", note = "" }, "blade", "mine")
assert(button.enabled == true, "adding a note where the dictionary has none is a change")

-- Pressing it must ask first, and the question must say what it would put back.
local asked
Addon.showConfirm = function(title, body, action, onConfirm)
  asked = { title = title, body = body, action = action, run = onConfirm }
end

open(DICT, "sword", "my own note")
editor.resetDictionary:GetScript("OnClick")()
assert(asked, "pressing reset must ask before overwriting what someone wrote")
assert(asked.body:find("blade", 1, true), "the question must show the meaning it would restore")
assert(asked.body:find("Old High German", 1, true), "and the note it would restore")
assert(asked.run, "and it must be possible to go through with it")

-- cancelling changes nothing
assert(editor.translation:GetText() == "sword", "the boxes must be untouched until confirmed")
assert(editor.note:GetText() == "my own note")

-- confirming restores both fields and greys the button again
asked.run()
assert(editor.translation:GetText() == "blade", "confirming should restore the meaning")
assert(editor.note:GetText() == "from Old High German", "and the note")
assert(button.enabled == false, "after a reset there is nothing left to reset")

-- and a greyed button does nothing even if something clicks it
open(DICT, "blade", "from Old High German")
asked = nil
editor.resetDictionary:GetScript("OnClick")()
assert(not asked, "with nothing to reset it must not even ask")

print("reset-dictionary: ok")
