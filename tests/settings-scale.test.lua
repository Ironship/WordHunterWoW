-- Run from the addon root:  lua tests/settings-scale.test.lua
--
-- The settings followed none of the five size sliders once. Every other surface
-- in the suite is answered one of two ways -- the quest panel sizes its letters,
-- the editor, list and stats windows are SetScale'd whole -- and the settings
-- did neither, so with every slider at the same number they came up at a size
-- of their own next to the windows they govern.
--
-- Rewritten for 1.20, when the settings became a window of the addon's own. The
-- window is still not answered by scaling it whole, for a new reason: at 200%
-- an 860 x 580 window is 1160 units tall, which does not fit on the screen at
-- the default UI scale, and the slider that sets the size would move under the
-- cursor while it was dragged. So it sizes its contents: roles for its strings,
-- RoleButtonHeight for its buttons, and every vertical measure multiplied by
-- the same number, because letters that grow inside offsets that do not are
-- letters that land on the line below.
--
-- What this file holds, and why each part is here rather than taken on trust:
--
--   * that the window is never itself scaled, which is the decision above;
--   * that every string on it is at its role's size for the current setting,
--     read back as a real number and compared against the size at 100% as well
--     as against the role, so a window that quietly stopped scaling cannot pass;
--   * that every row moved with them, and that the check boxes and slider bars,
--     which used to be Blizzard composites scaled whole, now grow by the same
--     number. The old page's check that its composites "land where their
--     caption does" measured a SetScale this window no longer makes, and went
--     with it;
--   * that nothing changed colour. A Blizzard font object carries a colour as
--     well as a size, so a size fixed by swapping objects recolours the window
--     silently. tests/font-roles.test.lua holds the same line for the windows;
--   * and that the window and the quest panel ask for the same size at the
--     same setting, which is the complaint itself.

local node = dofile("tests/wowstub.lua")

dofile("Core.lua")
dofile("Compat.lua")
dofile("UICommon.lua")
dofile("Harvest.lua")
-- Before Settings.lua, the order the .toc loads them in: the window is a set of
-- controls over other files' settings and builds its quest-log switch against a
-- getter that lives with the behaviour it governs.
dofile("QuestPanel.lua")
dofile("Settings.lua")
local Addon = WordHunterWoW_Addon

WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, words = {}, wordsByLocale = {} }
-- A real table: the harvest counter the window's note reads walks this one, and
-- a manufactured stub node would hand it its own methods to count.
WordHunterWoWCorpus = { version = 1, byLocale = {} }
Addon.initializeDatabase()

local function eq(what, got, want)
  assert(got == want, ("%s: expected %s, got %s"):format(what, tostring(want), tostring(got)))
end
-- Offsets are sums of scaled measures, compared against the offset at 100%
-- times the scale: the same number reached by two roads, which floating point
-- may disagree about in the last digit and nothing on a screen can.
local function near(what, got, want)
  assert(type(got) == "number" and math.abs(got - want) < 1e-6,
    ("%s: expected %s, got %s"):format(what, tostring(want), tostring(got)))
end

-- Every message below is built before the assertion is judged, so a %d with a
-- fraction in it raises in Lua 5.4 whatever the window did. Both figures are
-- only ever read by a person, so they are rounded for the reading.
local function at(y) return string.format("%.0f", tonumber(y) or 0) end
local function pct(scale) return string.format("%.0f%%", (tonumber(scale) or 0) * 100) end

local window = Addon.CreateSettingsPanel()
assert(window.rows and #window.rows > 0, "the window kept no record of what it draws")

-- ---------------------------------------------------------------------------
-- Everything on the window is answered one way or another. A row with no
-- string at a role, no widget sized by the setting and none of this addon's
-- buttons is a control no size setting reaches, which is the bug in one line --
-- and the way it would come back is somebody adding a row and forgetting.
local strings, sized = {}, {}
for _, row in ipairs(window.rows) do
  assert(#row.strings > 0 or #row.sized > 0 or row.button,
    ("a %s row on the %s tab has neither a font role nor a size, so no slider reaches it"):format(row.kind, row.tab))
  for _, item in ipairs(row.strings) do strings[#strings + 1] = item end
  for _, item in ipairs(row.sized) do sized[#sized + 1] = item end
end
for _, item in ipairs(window.chrome) do strings[#strings + 1] = item end
assert(#strings >= 10, "only " .. #strings .. " strings on the window carry a role")
assert(#sized >= 10, "only " .. #sized .. " check boxes, bars and choices are sized by the setting")

-- The size slider the window follows, driven the way a player drives it rather
-- than by calling the setter: the wiring from the slider to the layout is half
-- of what broke, and a test that calls the layout itself would not see it.
local textSlider = _G.WordHunterWoWTextScaleSlider
assert(rawget(_G, "WordHunterWoWTextScaleSlider"), "the text size slider is not in the window")
local function dragTo(value)
  textSlider:GetScript("OnValueChanged")(textSlider, value)
end

local function read()
  local seen = { strings = {}, sized = {}, rows = {}, buttons = {}, boxes = {} }
  for index, item in ipairs(strings) do
    local r, g, b = item.fs:GetTextColor()
    seen.strings[index] = { size = item.fs:GetFontSize(), color = { r, g, b } }
  end
  for index, item in ipairs(sized) do
    seen.sized[index] = { w = rawget(item.frame, "w"), h = rawget(item.frame, "h") }
  end
  for index, row in ipairs(window.rows) do
    seen.rows[index] = { y = row.y, h = row.h }
    if row.button then seen.buttons[index] = rawget(row.button, "h") end
  end
  for index, tab in ipairs(window.tabs) do seen.boxes[index] = rawget(tab.content, "h") end
  return seen
end

dragTo(1.0)
local base = read()

-- Read at 100% first, so everything below is compared against what the window
-- actually drew rather than against a number written here that could agree
-- with a window that never moved.
for index, item in ipairs(strings) do
  local was = base.strings[index]
  assert(type(was.size) == "number", ("a %s string has no size of its own"):format(item.role))
  eq(("a %s string starts at its role"):format(item.role), was.size, Addon.RoleSize(item.role))
end
for index, item in ipairs(sized) do
  eq("a sized widget starts at its own height", base.sized[index].h, item.h)
end
for index in ipairs(window.tabs) do
  assert(type(base.boxes[index]) == "number", "a tab's scroll box has no height of its own")
end

-- ---------------------------------------------------------------------------
-- And now at the sizes either side of it. 0.8 and 2.0 are the ends of the
-- slider, so the window is checked over the whole range it can be put to rather
-- than at one convenient multiple.
for _, scale in ipairs({ 0.8, 1.5, 2.0 }) do
  dragTo(scale)
  eq("the slider stored the size", Addon.GetTextScale(), scale)
  local now = read()

  for index, item in ipairs(strings) do
    local was, is = base.strings[index], now.strings[index]
    -- Both ways round: against the role, so the window and the other windows
    -- are one set of sizes, and against its own size at 100%, so a role that
    -- had quietly stopped taking the multiplier cannot agree with itself.
    eq(("a %s string follows its role at %s"):format(item.role, pct(scale)),
      is.size, Addon.RoleSize(item.role, scale))
    near(("a %s string grew by the setting"):format(item.role), is.size, was.size * scale)
    -- The trap this whole size effort has hit before: a font object carries a
    -- colour, so a string re-pointed at another object to fix its size comes
    -- back a different colour with every size assertion still green.
    assert(is.color[1] == was.color[1] and is.color[2] == was.color[2]
      and is.color[3] == was.color[3],
      ("a %s string changed colour when it was re-sized"):format(item.role))
  end

  -- The check boxes, the slider bars and the choice buttons: drawn by this
  -- file now rather than by a template, so they are sized, not scaled.
  for index, item in ipairs(sized) do
    near(("a sized widget at %s"):format(pct(scale)), now.sized[index].h, item.h * scale)
    if item.w then near(("a sized widget's width at %s"):format(pct(scale)), now.sized[index].w, item.w * scale) end
  end

  for index, row in ipairs(window.rows) do
    local was, is = base.rows[index], now.rows[index]
    -- Every row moves with the letters above it, which is what keeps a grown
    -- line from landing on the row below.
    near(("the %s row at %s on %s moved with its letters"):format(row.kind, at(was.y), row.tab),
      is.y, was.y * scale)
    near(("the %s row at %s on %s grew with the setting"):format(row.kind, at(was.y), row.tab),
      is.h, was.h * scale)
    if row.button then
      -- This addon's own buttons are not scaled, they are re-sized, so the
      -- question is whether the box grew in both directions.
      eq(("the button at %s on %s grew with the setting"):format(at(was.y), row.tab),
        now.buttons[index], Addon.RoleButtonHeight(scale))
    end
  end

  -- The window is never scaled itself, which is the decision the rest of this
  -- rests on.
  eq("the settings window is never SetScale'd", window:GetScale(), 1)
  for _, tab in ipairs(window.tabs) do
    eq(tab.id .. ": nor is the frame its rows hang on", tab.content:GetScale(), 1)
  end
  eq("nor is the preview", window.preview:GetScale(), 1)

  -- Each tab's scroll box has to grow with its rows, or the last one cannot be
  -- scrolled to -- a tab whose letters grow inside a box that does not is the
  -- same overlap one step out.
  for index, tab in ipairs(window.tabs) do
    near(("%s's scroll box at %s"):format(tab.id, pct(scale)), now.boxes[index], base.boxes[index] * scale)
    local deepest = 0
    for _, row in ipairs(tab.rows) do deepest = math.max(deepest, -row.y + row.h) end
    assert(deepest <= now.boxes[index],
      ("%s reaches %s, past the %s-high scroll box"):format(tab.id, at(deepest), at(now.boxes[index])))
  end

  -- The Reset button is one of this addon's buttons too.
  eq(("the Reset button at %s"):format(pct(scale)), rawget(window.resetButton, "h"), Addon.RoleButtonHeight(scale))
end

-- ---------------------------------------------------------------------------
-- A size changed with the window closed -- /whw reset, or a slash command --
-- is picked up by refresh, which the window runs when it is shown.
dragTo(1.0)
Addon.SetTextScale(1.6)
window.refresh()
eq("refresh followed a size changed elsewhere", window.title:GetFontSize(), Addon.RoleSize("heading", 1.6))

-- ---------------------------------------------------------------------------
-- The complaint itself: the window and the panel it governs, at one setting.
-- Sizes are what each surface asks for, and the window is not scaled on top of
-- them -- held above -- so the two are the same letters on screen.
Addon.createPanel()
local quest = Addon.panel
for _, scale in ipairs({ 1.0, 1.5 }) do
  dragTo(scale)
  Addon.ApplyIntegratedLayout()
  eq(("the window's heading against the quest panel's, at %s"):format(pct(scale)),
    window.title:GetFontSize(), quest.title:GetFontSize())
  eq("and the quest panel is still the one that is never scaled", quest:GetScale(), 1)
end

print(string.format("settings-scale: %d strings by role, %d widgets sized, %d rows over 0.8-2.0",
  #strings, #sized, #window.rows))
