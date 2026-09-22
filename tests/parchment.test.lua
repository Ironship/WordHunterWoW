-- Run from the addon root:  lua tests/parchment.test.lua
--
-- The parchment style borrows DialogueUI's texture by path. Two things have to
-- hold or it is either broken or a licensing problem:
--
--   * with that addon absent, nothing of its is touched and the style falls
--     back to the plain backdrop, so a player who picks it is not left with an
--     empty window;
--   * with it present, the three pieces are cut at the seams its own code
--     uses, or the scroll's ends land in the middle of the panel.

local Addon = {}
WordHunterWoW_Addon = Addon
dofile("DialogueUISkin.lua")
assert(Addon.ApplyParchment, "DialogueUISkin.lua did not attach ApplyParchment")

local loaded = false
C_AddOns = {IsAddOnLoaded = function(name)
  return name == "DialogueUI" and loaded
end}

local function texture()
  local t = {points = {}}
  function t:SetTexture(file) self.file = file end
  function t:SetTexCoord(a, b, c, d) self.coords = {a, b, c, d} end
  function t:SetSize(w, h) self.w, self.h = w, h end
  function t:ClearAllPoints() self.points = {} end
  function t:SetPoint(...) self.points[#self.points + 1] = {...} end
  function t:Show() self.shown = true end
  function t:Hide() self.shown = false end
  return t
end

local function panel(width, height)
  local f = {textures = {}, scripts = {}}
  function f:CreateTexture()
    local t = texture()
    self.textures[#self.textures + 1] = t
    return t
  end
  function f:GetWidth() return width end
  function f:GetHeight() return height or 800 end
  function f:HookScript(event, fn) self.scripts[event] = fn end
  return f
end

local STYLE = {parchment = true}

-- Without the addon -----------------------------------------------------------
loaded = false
local f = panel(600)
assert(Addon.ApplyParchment(f, STYLE) == false, "it claimed to draw with the addon absent")
assert(#f.textures == 0, "it created textures for an addon that is not installed")
print("parchment: with DialogueUI absent nothing of its is touched")

-- A style that is not the parchment one ----------------------------------------
loaded = true
f = panel(600)
assert(Addon.ApplyParchment(f, {}) == false, "an ordinary style was given parchment")
assert(#f.textures == 0, "an ordinary style created textures")

-- With the addon ---------------------------------------------------------------
f = panel(600)
assert(Addon.ApplyParchment(f, STYLE) == true, "it did not draw with the addon installed")
-- The strips, not every texture the frame owns: a client that can nine-slice
-- gets one image instead, and the probe for that leaves a texture behind here.
assert(type(f.whwParchment) == "table", "no strips were recorded on the frame")
assert(#f.whwParchment == 3, "expected three strips, got " .. #f.whwParchment)
local top, body, bottom = f.whwParchment[1], f.whwParchment[2], f.whwParchment[3]

-- The seams, from DialogueUI's own DialogueUI.lua.
local function coords(t) return table.concat(t.coords, ",") end
assert(coords(top) == table.concat({0, 1, 0, 256 / 2048}, ","), "top cut wrong: " .. coords(top))
assert(coords(body) == table.concat({0, 1, 256 / 2048, 896 / 2048}, ","), "body cut wrong: " .. coords(body))
assert(coords(bottom) == table.concat({0, 1, 896 / 2048, 1152 / 2048}, ","), "bottom cut wrong: " .. coords(bottom))

-- 600 wide against a tall frame: a quarter of the width is 150, but the ends
-- DialogueUI actually draws are 136.53 tall and never taller.
assert(top.w == 600 and math.abs(top.h - 136.53) < 0.01,
  "top cap is " .. top.w .. "x" .. top.h .. ", expected 600x136.53")
assert(bottom.w == 600 and math.abs(bottom.h - 136.53) < 0.01, "bottom cap is the wrong size")
assert(top.points[1][1] == "CENTER" and top.points[1][3] == "TOP",
  "the top cap must be centred on the frame's top edge so it overhangs")
assert(bottom.points[1][3] == "BOTTOM", "the bottom cap must sit on the bottom edge")
print("parchment: three pieces, cut and sized the way DialogueUI cuts them")

-- The panel this was first shipped against: wide and short. Taking the cap
-- height from the width, the way DialogueUI's own narrow window can afford to,
-- gave two 237-tall ends on a 330-tall panel -- they met in the middle and the
-- body between them collapsed. This is the shape that has to stay sane.
do
  local wide = panel(950, 330)
  Addon.ApplyParchment(wide, STYLE)
  local cap = wide.whwParchment[1].h
  assert(cap <= 330 * 0.4 + 0.01, "a short panel got ends " .. cap .. " tall")
  assert(cap * 2 < 330, "the two ends together are taller than the panel")
  assert(wide.whwParchment[1].w == 950, "the ends must still span the full width")
end

-- A narrow panel keeps the true proportions, because the width limit bites
-- before the fixed height does.
do
  local narrow = panel(200, 800)
  Addon.ApplyParchment(narrow, STYLE)
  assert(math.abs(narrow.whwParchment[1].h - 50) < 0.01,
    "a 200-wide panel should get 50-tall ends, got " .. narrow.whwParchment[1].h)
end
print("parchment: the ends stay sane on a wide short panel and a narrow one")

-- The theme decides which folder ------------------------------------------------
assert(top.file:find("Theme_Brown", 1, true), "brown is the default: " .. tostring(top.file))
DialogueUI_DB = {Theme = 2}
f = panel(600)
Addon.ApplyParchment(f, STYLE)
assert(f.whwParchment[1].file:find("Theme_Dark", 1, true), "dark mode was not followed")
DialogueUI_DB = nil
print("parchment: it follows DialogueUI's own light and dark theme")

-- A client that can nine-slice: one image stretched over the whole frame, with
-- the corners kept. This is the path that actually runs in the game, and the
-- strips are only there for clients without the call.
do
  local slicing = panel(950, 330)
  local made = {}
  function slicing:CreateTexture()
    local tex = texture()
    function tex:SetTextureSliceMargins(l, tp, r, b) self.margins = {l, tp, r, b} end
    function tex:SetAllPoints() end
    made[#made + 1] = tex
    self.textures[#self.textures + 1] = tex
    return tex
  end
  assert(Addon.ApplyParchment(slicing, STYLE) == true, "the nine-slice path refused")
  local slice = slicing.whwSlice
  assert(type(slice) == "table", "no sliced texture was made")
  assert(slice.file and slice.file:find("GenericFrame-Tiled-Large", 1, true),
    "the sliced path used the wrong file: " .. tostring(slice.file))
  assert(table.concat(slice.margins, ",") == "80,80,80,80",
    "wrong slice margins: " .. table.concat(slice.margins, ","))
  assert(slice.shown, "the sliced texture was not shown")
  -- and the strips must not be drawn over it
  if type(slicing.whwParchment) == "table" then
    for i = 1, 3 do
      local strip = slicing.whwParchment[i]
      assert(not (type(strip) == "table" and strip.shown), "a strip was left showing over the slice")
    end
  end
end
print("parchment: a client that can nine-slice gets one clean image instead")

-- A frame with no width yet ------------------------------------------------------
f = panel(0)
assert(Addon.ApplyParchment(f, STYLE) == true, "a frame awaiting layout was given up on")
assert(f.scripts.OnSizeChanged, "nothing was hooked to redo it once the size arrives")
print("parchment: ok")

-- The English column. DialogueUI shows the English inside its own window, so
-- the panel's second copy of it is redundant while that skin is on -- and the
-- German half, the one with the clickable words, should have the full width.
-- This is done by answering the addon's existing single-column question, not
-- by hiding widgets, so it goes through layout code that already works.
do
  assert(Addon.EnglishShownElsewhere, "the skin does not answer for the English column")
  loaded = true
  Addon.BACKGROUNDS = {parch = {parchment = true}, plain = {}}
  Addon.GetBackgroundStyle = function() return "parch" end
  assert(Addon.EnglishShownElsewhere() == true, "with the skin on the English is elsewhere")
  Addon.GetBackgroundStyle = function() return "plain" end
  assert(Addon.EnglishShownElsewhere() == false, "with another style it is not")
  Addon.GetBackgroundStyle = function() return "parch" end
  loaded = false
  assert(Addon.EnglishShownElsewhere() == false, "without DialogueUI it is not")
end
print("parchment: the English column steps aside only when DialogueUI shows it")

-- The paper is drawn past the frame's edge to keep text off the torn border,
-- and that overhang has to be a share of the window. A fixed 24 past the
-- reader's small 300x96 window added half again to its height and it arrived
-- looking enormous next to everything else.
do
  -- the block above left DialogueUI switched off
  loaded = true
  Addon.GetBackgroundStyle = function() return "parch" end
  local function slicingPanel(w, h)
    local f = panel(w, h)
    function f:CreateTexture()
      local tex = texture()
      function tex:SetTextureSliceMargins() end
      function tex:SetAllPoints() end
      self.textures[#self.textures + 1] = tex
      return tex
    end
    return f
  end
  local function overhangOf(f)
    local pt = f.whwSlice.points[1]
    return -pt[4]  -- TOPLEFT x offset is -overhang
  end

  local big = slicingPanel(950, 330)
  Addon.ApplyParchment(big, STYLE)
  assert(math.abs(overhangOf(big) - 24) < 0.01,
    "a large panel should keep the full 24, got " .. overhangOf(big))

  local small = slicingPanel(300, 96)
  Addon.ApplyParchment(small, STYLE)
  local over = overhangOf(small)
  assert(over < 12, "the reader's window got " .. over .. " of overhang, which is too much")
  assert(over * 2 < 96 * 0.2, "the overhang is still a big share of a small window's height")
end
print("parchment: the overhang shrinks with the window instead of swamping it")
