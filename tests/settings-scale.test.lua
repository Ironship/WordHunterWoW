-- Run from the addon root:  lua tests/settings-scale.test.lua
--
-- The settings page followed none of the five size sliders. Every other surface
-- in the suite is answered one of two ways -- the quest panel sizes its letters,
-- the editor, list and stats windows are SetScale'd whole -- and this one did
-- neither, so with every slider at the same number it came up at a size of its
-- own next to the windows it governs.
--
-- It is the one page that cannot be answered by scaling the window. It is
-- parented into Blizzard's options canvas, so it already carries that canvas's
-- effective scale and SetScale would multiply with it rather than replace it; a
-- page scaled up inside a fixed canvas also keeps its screen rectangle, so the
-- right-hand end of every slider would be clipped away. So the page sizes its
-- contents: roles for its own strings, RoleButtonHeight for its one button, and
-- every vertical offset multiplied by the same number, because letters that
-- grow inside offsets that do not are letters that land on the line below.
--
-- What this file holds, and why each part is here rather than taken on trust:
--
--   * that the page is never itself scaled, which is the decision above;
--   * that every string on it is at its role's size for the current setting,
--     read back as a real number and compared against the size at 100% as well
--     as against the role, so a page that quietly stopped scaling cannot pass;
--   * that every offset moved with them, including the Blizzard composites,
--     which are scaled rather than re-fonted and so have to be given their
--     offsets back in their own units -- getting that wrong applies the scale
--     twice and pulls the page apart, and it is invisible at 100%;
--   * that nothing changed colour. A Blizzard font object carries a colour as
--     well as a size, so a size fixed by swapping objects recolours the page
--     silently. tests/font-roles.test.lua holds the same line for the windows;
--   * and that the page and the quest panel ask for the same size at the same
--     setting, which is the complaint itself.

local node = dofile("tests/wowstub.lua")

dofile("Core.lua")
dofile("Compat.lua")
dofile("UICommon.lua")
dofile("Harvest.lua")
-- Before Settings.lua, the order the .toc loads them in: the page is a set of
-- controls over other files' settings and builds its quest-log switch against a
-- getter that lives with the behaviour it governs.
dofile("QuestPanel.lua")
dofile("Settings.lua")
local Addon = WordHunterWoW_Addon

WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, words = {}, wordsByLocale = {} }
-- A real table: the harvest counter the page's note reads walks this one, and a
-- manufactured stub node would hand it its own methods to count.
WordHunterWoWCorpus = { version = 1, byLocale = {} }
Addon.initializeDatabase()

local function eq(what, got, want)
  assert(got == want, ("%s: expected %s, got %s"):format(what, tostring(want), tostring(got)))
end

-- Every message below is built before the assertion is judged, so a %d with a
-- fraction in it raises in Lua 5.4 whatever the page did -- 0.8 of an offset is
-- not an integer and 0.8 of 100 is not 80. Both figures are only ever read by a
-- person, so they are rounded for the reading.
local function at(y) return string.format("%.0f", tonumber(y) or 0) end
local function pct(scale) return string.format("%.0f%%", (tonumber(scale) or 0) * 100) end

local page = Addon.CreateSettingsPanel()
local box = _G.WordHunterWoWSettingsContent
assert(page.rows and #page.rows > 0, "the page kept no record of what it draws")

-- ---------------------------------------------------------------------------
-- Everything on the page is answered one way or the other. A control with
-- neither a role nor a scale of its own is a control no size setting reaches,
-- which is the bug in one line -- and the way it would come back is somebody
-- adding a row and forgetting.
-- Three ways a row can be reached, not two: a string carries a font role, one
-- of Blizzard's composites carries its own scale, and one of this addon's
-- buttons is resized in both directions. A row with none of the three is a
-- control no size setting reaches, which is the bug in one line -- and the way
-- it would come back is somebody adding a row and forgetting.
local strings, composites = {}, {}
for _, row in ipairs(page.rows) do
  assert(row.role or row.own or row.button,
    "a control on the page has neither a font role nor a scale, so no slider reaches it")
  if row.role then strings[#strings + 1] = row
  elseif row.own then composites[#composites + 1] = row end
end
assert(#strings >= 10, "only " .. #strings .. " strings on the page carry a role")
assert(#composites >= 10, "only " .. #composites .. " of Blizzard's widgets are scaled")

-- The size slider the page follows, driven the way a player drives it rather
-- than by calling the setter: the wiring from the slider to the layout is half
-- of what broke, and a test that calls the layout itself would not see it.
local textSlider = _G.WordHunterWoWTextScaleSlider
assert(rawget(_G, "WordHunterWoWTextScaleSlider"), "the text size slider is not on the page")
local function dragTo(value)
  textSlider:GetScript("OnValueChanged")(textSlider, value)
end

local function readPage()
  local seen = {}
  for index, row in ipairs(page.rows) do
    local _, y = row.frame:GetAnchor("TOPLEFT")
    local r, g, b = row.frame:GetTextColor()
    local w, h = row.frame:GetWidth(), row.frame:GetHeight()
    seen[index] = {
      y = y,
      w = w,
      h = h,
      scale = row.frame:GetScale(),
      size = row.frame.GetFontSize and row.frame:GetFontSize() or nil,
      color = { r, g, b },
    }
  end
  return seen
end

dragTo(1.0)
local base = readPage()
local baseBox = rawget(box, "h")
assert(type(baseBox) == "number", "the scroll box has no height of its own")

-- Read at 100% first, so everything below is compared against what the page
-- actually drew rather than against a number written here that could agree with
-- a page that never moved.
for index, row in ipairs(page.rows) do
  local was = base[index]
  assert(type(was.y) == "number", "a control on the page was never anchored")
  if row.role then
    assert(type(was.size) == "number",
      ("the %s string at %s has no size of its own"):format(row.role, at(was.y)))
    eq(("the %s string at %s starts at its role"):format(row.role, at(was.y)),
      was.size, Addon.RoleSize(row.role))
  else
    eq(("a widget at %s starts unscaled"):format(at(was.y)), was.scale, 1)
  end
end

-- ---------------------------------------------------------------------------
-- And now at the sizes either side of it. 0.8 and 2.0 are the ends of the
-- slider, so the page is checked over the whole range it can be put to rather
-- than at one convenient multiple.
for _, scale in ipairs({ 0.8, 1.5, 2.0 }) do
  dragTo(scale)
  eq("the slider stored the size", Addon.GetTextScale(), scale)
  local now = readPage()

  for index, row in ipairs(page.rows) do
    local was, is = base[index], now[index]
    if row.role then
      -- Both ways round: against the role, so the page and the windows are one
      -- set of sizes, and against its own size at 100%, so a role that had
      -- quietly stopped taking the multiplier cannot agree with itself.
      eq(("the %s string at %s follows its role at %s"):format(row.role, at(was.y), pct(scale)),
        is.size, Addon.RoleSize(row.role, scale))
      eq(("the %s string at %s grew by the setting"):format(row.role, at(was.y)),
        is.size, was.size * scale)
      assert(is.size ~= was.size or scale == 1,
        ("the %s string at %s did not move at all"):format(row.role, at(was.y)))
      -- The trap this whole size effort has hit before: a font object carries a
      -- colour, so a string re-pointed at another object to fix its size comes
      -- back a different colour with every size assertion still green.
      assert(is.color[1] == was.color[1] and is.color[2] == was.color[2]
        and is.color[3] == was.color[3],
        ("the %s string at %s changed colour when it was re-sized"):format(row.role, at(was.y)))
      eq(("the %s string at %s moved with its letters"):format(row.role, at(was.y)),
        is.y, was.y * scale)
    elseif row.button then
      -- This addon's own buttons are not scaled, they are re-sized, so the
      -- question is whether the box grew in both directions and moved with the
      -- page. Asking for a scale here would pass on a button that never moved.
      eq(("the button at %s grew with the setting"):format(at(was.y)),
        is.h, Addon.RoleButtonHeight(scale))
      eq(("the button at %s moved with the page"):format(at(was.y)),
        is.y, was.y * scale)
    else
      eq(("the widget at %s carries the setting"):format(at(was.y)), is.scale, scale)
      -- The offsets of a scaled frame are read in that frame's own units, so
      -- this is where the scale gets applied twice if it is handed over raw.
      -- On screen the widget has to land exactly where the strings around it
      -- did, and at 100% both spellings agree -- which is why it is worth an
      -- assertion of its own.
      eq(("the widget at %s lands where its caption does"):format(at(was.y)),
        is.y * is.scale, was.y * scale)
    end
  end

  -- The one button on the page. Its height was written here as 24, a fourth
  -- height in an addon that draws one, and no slider ever reached it.
  local button = page.harvestExport
  assert(type(rawget(button, "h")) == "number", "the export button has no height of its own")
  eq(("the export button at %s"):format(pct(scale)),
    button:GetHeight(), Addon.RoleButtonHeight(scale))

  -- The page is never scaled itself, which is the decision the rest of this
  -- rests on: it is parented into Blizzard's canvas, and a scale set here would
  -- multiply with the canvas's rather than replace it.
  eq("the settings page is never SetScale'd", page:GetScale(), 1)
  eq("nor is the frame its controls hang on", box:GetScale(), 1)

  -- The scroll box has to grow with the page, or the last control cannot be
  -- scrolled to -- a page whose letters grow inside a box that does not is the
  -- same overlap one step out.
  eq(("the scroll box at %s"):format(pct(scale)), rawget(box, "h"), baseBox * scale)
  local deepest = 0
  for index, row in ipairs(page.rows) do
    deepest = math.max(deepest, -now[index].y * now[index].scale + (row.h or 0) * scale)
  end
  assert(deepest <= rawget(box, "h"),
    ("the page reaches %s, past the %s-high scroll box"):format(at(deepest), at(rawget(box, "h"))))
end

-- ---------------------------------------------------------------------------
-- Blizzard's own route in -- Esc, Options, AddOns -- never touches the page's
-- controls, and /whw reset changes the size with the page closed. So refresh
-- has to put the page down again too, not only the slider.
dragTo(1.0)
Addon.SetTextScale(1.6)
page.refresh()
eq("refresh followed a size changed elsewhere", page.title:GetFontSize(), Addon.RoleSize("heading", 1.6))

-- ---------------------------------------------------------------------------
-- The complaint itself: the page and the window it governs, at one setting.
-- Sizes are what each surface asks for, and the page is not scaled on top of
-- them -- held two assertions above -- so on a canvas of its own scale the two
-- are the same letters on screen.
Addon.createPanel()
local quest = Addon.panel
for _, scale in ipairs({ 1.0, 1.5 }) do
  dragTo(scale)
  Addon.ApplyIntegratedLayout()
  eq(("the page's heading against the quest panel's, at %s"):format(pct(scale)),
    page.title:GetFontSize(), quest.title:GetFontSize())
  eq("and the quest panel is still the one that is never scaled", quest:GetScale(), 1)
end

print(string.format("settings-scale: %d strings by role, %d widgets by scale, over 0.8-2.0",
  #strings, #composites))
