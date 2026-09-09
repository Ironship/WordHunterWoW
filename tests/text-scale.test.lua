-- Run from the addon root:  lua tests/text-scale.test.lua
--
-- Quest text was sometimes simply too small to read. The addon draws that text
-- itself rather than through a Blizzard font object, so the game's own UI scale
-- never reaches it and there was nothing the player could do about it.
--
-- The part that is easy to get wrong is not the font. It is that the rows have
-- to grow with it: scale the letters alone and the second line lands on top of
-- the first.

local node = dofile("tests/wowstub.lua")

dofile("Core.lua")
dofile("Compat.lua")
dofile("UICommon.lua")
dofile("QuestPanel.lua")
local Addon = WordHunterWoW_Addon
assert(Addon.GetTextScale and Addon.SetTextScale, "Core.lua must provide both")

WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, words = {}, wordsByLocale = {} }
Addon.initializeDatabase()

-- Unset means unchanged, so an existing install looks exactly as it did.
assert(Addon.GetTextScale() == 1.0, "the default has to be life-size, got " .. Addon.GetTextScale())

Addon.SetTextScale(1.5)
assert(Addon.GetTextScale() == 1.5, "a chosen size should stick")

-- Bounded at both ends. Below the floor the words stop being clickable targets;
-- above the ceiling a long quest no longer fits a window you can drag onto the
-- screen. Out-of-range input is clamped, never rejected silently.
Addon.SetTextScale(99)
assert(Addon.GetTextScale() == Addon.TEXT_SCALE_MAX, "too large should clamp to the ceiling")
Addon.SetTextScale(0.1)
assert(Addon.GetTextScale() == Addon.TEXT_SCALE_MIN, "too small should clamp to the floor")
Addon.SetTextScale("nonsense")
assert(Addon.GetTextScale() == 1.0, "something that is not a number falls back to life-size")

-- A stored value outside the range is not trusted either: the file can be edited
-- by hand, and a 40x quest panel is not recoverable from inside the game.
WordHunterWoWDB.settings.textScale = 25
assert(Addon.GetTextScale() == 1.0, "an impossible stored value is ignored")
WordHunterWoWDB.settings.textScale = 1.25

-- Now the part that matters on screen. Render the same quest at two sizes and
-- compare what the panel actually laid out.
Addon.createPanel()
local panel = Addon.panel
-- Long enough to wrap, which is what makes the row height observable.
GetQuestText = function() return "Bringt acht Stuecke zaehes Wolfsfleisch zurueck und bringt sie zu mir zurueck damit wir sie verwenden koennen" end
GetObjectiveText = function() return "" end
QuestFrame:Show()

local function render(scale)
  Addon.SetTextScale(scale)
  Addon.readCurrentQuest()
  return panel.content:GetHeight()
end

local small = render(1.0)
local large = render(2.0)
assert(large > small,
  ("doubling the size must give the text more room, got %s then %s"):format(small, large))

-- And it has to grow about fourfold, not twofold. Doubling the size doubles how
-- wide each word is, so the text wraps onto twice as many lines -- and each of
-- those lines has to be twice as tall. Scaling the font while leaving the rows
-- at their old height gives exactly half this, and puts every line on top of
-- the one above it. That bug reads fine in a screenshot of a one-line quest.
local PADDING = 28
local grew = (large - PADDING) / (small - PADDING)
assert(grew > 3,
  ("the rows have to scale with the font: the text area grew %.1fx, expected about 4x"):format(grew))

-- The letters themselves have to grow, not just the spacing around them.
local fontAt = {}
for _, scale in ipairs({ 1.0, 2.0 }) do
  LAST_FONT_SIZE = nil
  Addon.SetTextScale(scale)
  Addon.readCurrentQuest()
  fontAt[scale] = LAST_FONT_SIZE
end
assert(fontAt[1.0] and fontAt[2.0], "the panel should have set a font size on its words")
assert(math.abs(fontAt[2.0] - fontAt[1.0] * 2) < 0.001,
  ("doubling the setting must double the font, got %s then %s"):format(fontAt[1.0], fontAt[2.0]))

-- And back down again: the panel must not keep the larger layout.
local again = render(1.0)
assert(again == small, ("returning to life-size should restore the old layout, got %s vs %s")
  :format(again, small))

-- The slider has to be bounded by the same numbers the code clamps to, or the
-- two disagree at the edges.
local settings = io.open("Settings.lua"):read("*a")
assert(settings:find("TEXT_SCALE_MIN", 1, true) and settings:find("TEXT_SCALE_MAX", 1, true),
  "the slider's ends must come from the same bounds the setter clamps to")

-- One size per window, and setting one must not move the others.
Addon.SetTextScale(1.0)
for _, w in ipairs(Addon.SCALED_WINDOWS) do
  Addon["Set" .. w.key:sub(1,1):upper() .. w.key:sub(2)](1.0)
end
Addon.SetEditorScale(1.8)
assert(Addon.GetEditorScale() == 1.8, "the editor size should stick")
assert(Addon.GetTextScale() == 1.0, "and must not drag the quest text with it")
assert(Addon.GetListScale() == 1.0, "nor the word list")

-- Every one of them is bounded the same way; none may be set to something the
-- player cannot undo from inside the game.
for _, w in ipairs(Addon.SCALED_WINDOWS) do
  local set = Addon["Set" .. w.key:sub(1,1):upper() .. w.key:sub(2)]
  local get = Addon["Get" .. w.key:sub(1,1):upper() .. w.key:sub(2)]
  assert(set and get, w.key .. " needs a getter and a setter")
  set(99); assert(get() == Addon.TEXT_SCALE_MAX, w.key .. " clamps at the ceiling")
  set(0);  assert(get() == Addon.TEXT_SCALE_MIN, w.key .. " clamps at the floor")
  set(1.0)
end

-- The windows are scaled whole rather than field by field. That is the point:
-- an earlier attempt resized font strings one at a time and missed the meaning
-- box outright, because nothing listed which fields there were.
local editor = { scale = 1, SetScale = function(self, v) self.scale = v end }
Addon.editor = editor
Addon.SetEditorScale(1.5)
assert(editor.scale == 1.5,
  "setting the size must reach the window itself, got " .. tostring(editor.scale))
Addon.SetEditorScale(1.0)
assert(editor.scale == 1.0, "and back again")

-- A stored value out of range must not reach the window either: the file can be
-- edited by hand, and a 40x window cannot be fixed from inside the game.
WordHunterWoWDB.settings.editorScale = 25
Addon.ApplyWindowScale("editorScale")
assert(editor.scale == 1.0, "an impossible stored value falls back to life-size")

-- The English panel is the other addon's window, so it is asked to scale itself
-- rather than reached into: it also runs without this addon, off its own
-- remembered size, and there is no load order between the two.
local enPanel = { asked = 0, scale = 1, SetScale = function(self, v) self.scale = v end }
enPanel.ApplyTextScale = function() enPanel.asked = enPanel.asked + 1 end
Addon.enPanel = enPanel
Addon.SetEnPanelTextScale(1.4)
assert(enPanel.asked == 1, "the English panel has to be asked to scale itself")
assert(enPanel.scale == 1, "and not have a scale pushed onto it from here")
Addon.SetEnPanelTextScale(1.0)

-- Every size the addon stores has to belong to exactly one group, because the
-- group is what decides the heading a player reads it under and the unit it is
-- shown in. A key in neither has no control at all; a key in both gets two
-- sliders writing to one setting.
local grouped = {}
for _, group in ipairs(Addon.SIZE_GROUPS) do
  assert(Addon.LABELS[group.heading] and Addon.LABELS[group.note],
    "a group without a heading and a note is a group that explains nothing")
  assert(group.unit == "points" or group.unit == "percent", "unknown unit " .. tostring(group.unit))
  for _, entry in ipairs(group.entries) do
    assert(not grouped[entry.key], entry.key .. " is in two groups")
    assert(Addon.LABELS[entry.label], entry.key .. " has no label")
    grouped[entry.key] = group.unit
  end
end
for _, key in ipairs(Addon.TEXT_SCALE_KEYS) do
  assert(grouped[key], key .. " is stored but has no slider")
end
for _, w in ipairs(Addon.SCALED_WINDOWS) do
  assert(grouped[w.key] == "percent" or w.key == "enPanelTextScale",
    w.key .. " is scaled whole, so it belongs under the window heading")
end

-- The two families must not read as the same measurement. This is the whole
-- answer to "the editor and the panel are both at 150% and the editor is
-- bigger": at equal settings they genuinely do not look equal, because the
-- surfaces start from different fonts, so the panel must stop offering two
-- numbers that invite the comparison.
assert(grouped.textScale == "points", "quest text is a font size and has to be shown as one")
assert(grouped.editorScale == "percent", "the editor is scaled whole and has to be shown as one")
for step = 16, 40 do
  local v = step / 20
  assert(Addon.FormatSizeValue("points", v) ~= Addon.FormatSizeValue("percent", v),
    ("the two units read the same at %s, so the numbers can still be compared"):format(v))
end

-- The point figure has to be the size the panel will actually draw with, not a
-- stock 12 -- a player who has turned the game's own font up would otherwise be
-- told the wrong number by every step of the slider.
assert(Addon.FormatSizeValue("points", 1.5) == "18pt",
  "12pt at 150% is 18pt, got " .. Addon.FormatSizeValue("points", 1.5))
assert(Addon.FormatSizeValue("percent", 1.5) == "150%",
  "a window scale is still a percentage, got " .. Addon.FormatSizeValue("percent", 1.5))
local realFont = GameFontHighlight
GameFontHighlight = { GetFont = function() return "FRIZQT__.TTF", 16, "" end }
assert(Addon.TextScalePoints(1.5) == 24,
  "the figure must follow the game's font, got " .. Addon.TextScalePoints(1.5))
GameFontHighlight = realFont

print("text-scale: ok")
