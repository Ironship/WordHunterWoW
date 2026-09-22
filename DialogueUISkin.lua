-- The quest panel, wearing DialogueUI's parchment.
--
-- On the licence: nothing of DialogueUI's is copied into this addon. Its
-- textures are named by path and only ever drawn when the player has that
-- addon installed, which is why the style says so in its own name and why it
-- falls back to Blizzard's own dialog parchment when it is not there. Nothing
-- of theirs is redistributed.
--
-- The numbers below are read out of DialogueUI's own code so the seams land
-- where its do. Parchment.png is a 1024x2048 atlas drawn in three pieces --
-- its DialogueUI.lua sizes the caps 546.13 wide by 136.53 tall, which is a
-- quarter of the width, and anchors each one centred on the frame's edge so
-- half of it overhangs. That overhang is what makes it read as a scroll
-- rather than a box.

local Addon = WordHunterWoW_Addon

-- WoW runs Lua 5.1, where unpack is a global; the tests run on a newer one,
-- where it moved into table. Same code either way.
local unpack = unpack or table.unpack

local ART = "Interface\\AddOns\\DialogueUI\\Art\\"
-- How tall the torn ends are. DialogueUI draws them 546.13 wide by 136.53
-- tall, and both numbers come off the same multiplier as its own window, so
-- there they always keep that shape. Here they cannot: this panel is wide and
-- short where its window is narrow and tall, and taking the height from the
-- width the way it does gives a 950-wide panel two 240-tall ends that eat it
-- whole. So the height is the one DialogueUI actually draws, and the two
-- limits below only ever shrink it -- by the frame's height, so a short panel
-- still has a body between its ends, and by its width, so a narrow one keeps
-- the true proportions.
local CAP_HEIGHT = 136.53
local CAP_OF_WIDTH = 0.25
local CAP_OF_HEIGHT = 0.4

local TOP_PIECE    = {0, 1, 0,          256 / 2048}
local BODY_PIECE   = {0, 1, 256 / 2048, 896 / 2048}
local BOTTOM_PIECE = {0, 1, 896 / 2048, 1152 / 2048}

local function installed()
  if type(C_AddOns) == "table" and C_AddOns.IsAddOnLoaded then
    return C_AddOns.IsAddOnLoaded("DialogueUI") and true or false
  end
  if type(IsAddOnLoaded) == "function" then
    return IsAddOnLoaded("DialogueUI") and true or false
  end
  return false
end
Addon.DialogueUIInstalled = installed

local function themeFile(name)
  -- 1 is its brown theme and 2 its dark one. Absent means the player has never
  -- opened its settings, and brown is what it starts on.
  local theme = type(DialogueUI_DB) == "table" and DialogueUI_DB.Theme
  return ART .. (theme == 2 and "Theme_Dark" or "Theme_Brown") .. "\\" .. name
end

local function texturePath()
  return themeFile("Parchment.png")
end

-- Always three pieces, counted rather than walked with ipairs. A frame field
-- is not necessarily a list this file made: the test stub answers any unknown
-- field with a fabricated object whose every index is truthy, and ipairs over
-- that never ends.
local PIECES = 3

local function eachPiece(frame, fn)
  local pieces = frame.whwParchment
  if type(pieces) ~= "table" then return end
  for i = 1, PIECES do
    local piece = pieces[i]
    if type(piece) == "table" then fn(piece) end
  end
end

local function hide(frame)
  eachPiece(frame, function(piece) piece:Hide() end)
  return false
end

-- The three-strip parchment above is cut for DialogueUI's own window, which is
-- always 546 wide. Stretched across a panel twice that, the rolled ends go
-- flat and wide and the whole thing reads as smeared. For windows that can be
-- any size DialogueUI uses a different texture and so does this: one
-- nine-sliced image whose corners keep their shape at any width, the same file
-- and the same 80px margins its own settings windows use.
--
-- SetTextureSliceMargins is not on every client -- DialogueUI carries its own
-- stand-in for the ones without it -- so when it is missing this says so and
-- the strips are used instead.
local SLICE_FILE = "GenericFrame-Tiled-Large.png"
local SLICE_MARGIN = 80
-- How far the paper reaches past the frame, so the text keeps clear of the
-- torn border. DialogueUI uses 16 for its own; the panel's text starts 18
-- inside, and its longest German words need a little more than that.
local OVERHANG = 24

-- Is the parchment style the one the player has chosen? Declared here because
-- the chrome below asks it and Lua only sees locals declared above.
local function parchmentChosen()
  if not Addon.GetBackgroundStyle or not Addon.BACKGROUNDS then return false end
  local style = Addon.BACKGROUNDS[Addon.GetBackgroundStyle()]
  return (style and style.parchment) and true or false
end

-- The overhang has to be a share of the window, not a fixed number. 24px past
-- a 950x330 panel is the margin its text needed; the same 24px past the
-- reader's 300x96 window adds half again to its height and it arrives looking
-- enormous. So it is capped by both dimensions and only ever gets smaller.
local function overhangFor(frame)
  local width = frame.GetWidth and frame:GetWidth()
  local height = frame.GetHeight and frame:GetHeight()
  local value = OVERHANG
  if type(width) == "number" and width > 0 then
    value = math.min(value, width * 0.04)
  end
  if type(height) == "number" and height > 0 then
    value = math.min(value, height * 0.08)
  end
  return value
end

local function applySlice(frame)
  local slice = frame.whwSlice
  if type(slice) ~= "table" then
    if type(frame.CreateTexture) ~= "function" then return false end
    slice = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    frame.whwSlice = slice
  end
  if type(slice.SetTextureSliceMargins) ~= "function" then return false end
  slice:SetTexture(themeFile(SLICE_FILE))
  slice:SetTextureSliceMargins(SLICE_MARGIN, SLICE_MARGIN, SLICE_MARGIN, SLICE_MARGIN)
  -- Drawn larger than the frame, the way DialogueUI draws its own: its
  -- GenericFrame sets the background to -offset/+offset on the corners. The
  -- panel's text sits a fixed 18px inside the frame, and the parchment's torn
  -- border is wider than that, so without the overhang the words end up lying
  -- on the decoration. Pushing the paper outwards fixes the margin without
  -- touching a single one of the panel's own anchors.
  local over = overhangFor(frame)
  slice:ClearAllPoints()
  slice:SetPoint("TOPLEFT", frame, "TOPLEFT", -over, over)
  slice:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", over, -over)
  slice:Show()
  return true
end

-- Chrome that belongs to Blizzard's look and has no counterpart in
-- DialogueUI's: the close cross, the scrollbars with their little square
-- arrows, the action buttons. Hidden while this skin is on and put straight
-- back when it is not, so nothing is lost by trying the style out.
local chrome = {}

-- Hiding these once is not enough. The panel shows its buttons again on every
-- render, and UIPanelScrollFrameTemplate shows its bar again whenever the
-- content grows past the frame -- so a widget hidden at creation is back a
-- moment later. Each one is hooked to put itself away again, which is the only
-- thing that outlasts whoever shows it.
function Addon.HideUnderParchment(widget)
  if type(widget) ~= "table" or type(widget.Hide) ~= "function" then return end
  if not chrome[widget] then
    chrome[widget] = true
    if type(widget.HookScript) == "function" then
      widget:HookScript("OnShow", function(self)
        if installed() and parchmentChosen() then self:Hide() end
      end)
    end
  end
  if installed() and parchmentChosen() then
    widget:Hide()
  elseif type(widget.Show) == "function" then
    widget:Show()
  end
end

-- True when the English is already on screen somewhere else -- which, with
-- this skin on, it is: DialogueUI draws it inside its own window.
function Addon.EnglishShownElsewhere()
  return installed() and parchmentChosen()
end

function Addon.RefreshChrome()
  local on = installed() and parchmentChosen()
  for widget in pairs(chrome) do
    if on then
      if type(widget.Hide) == "function" then widget:Hide() end
    elseif type(widget.Show) == "function" then
      widget:Show()
    end
  end
end

local function hideSlice(frame)
  local slice = frame.whwSlice
  if type(slice) == "table" and slice.Hide then slice:Hide() end
end

-- Lays the parchment over a frame. Returns true when it did, so the caller
-- knows to take its own flat colours back off.
function Addon.ApplyParchment(frame, style)
  if not (frame and style and style.parchment and installed()) then
    if frame then hideSlice(frame) end
    return frame and hide(frame) or false
  end
  if not frame.CreateTexture then return false end

  -- One nine-sliced image where the client can do it, and only otherwise the
  -- three strips cut for a fixed width.
  if applySlice(frame) then
    hide(frame)
    frame.whwParchmentStyle = style
    if not frame.whwHooked then
      frame.whwHooked = true
      frame:HookScript("OnShow", function(self)
        if self.whwParchmentStyle and self.whwParchmentStyle.parchment then
          Addon.FadeInPanel(self)
        end
      end)
    end
    return true
  end

  local pieces = frame.whwParchment
  if not pieces then
    pieces = {}
    for i = 1, PIECES do
      -- Sublevel 0: above the backdrop, below the reading surface at 1 and
      -- below every line of text.
      pieces[i] = frame:CreateTexture(nil, "BACKGROUND", nil, 0)
    end
    frame.whwParchment = pieces
    -- The caps are sized from the width, so they have to be redone whenever
    -- the player drags the panel wider. Hooked once; a hook cannot be undone.
    frame:HookScript("OnSizeChanged", function(self)
      if self.whwParchmentStyle then
        Addon.ApplyParchment(self, self.whwParchmentStyle)
      end
    end)
    frame:HookScript("OnShow", function(self)
      if self.whwParchmentStyle and self.whwParchmentStyle.parchment then
        Addon.FadeInPanel(self)
      end
    end)
  end
  frame.whwParchmentStyle = style

  -- Before the first layout a frame can answer with nothing at all, and under
  -- the test stub it answers with a fabricated object. Either way there is no
  -- width to cut the caps from yet, and OnSizeChanged will bring one.
  local width = frame:GetWidth()
  if type(width) ~= "number" or width <= 0 then return true end
  local height = frame.GetHeight and frame:GetHeight()
  local cap = math.min(CAP_HEIGHT, width * CAP_OF_WIDTH)
  if type(height) == "number" and height > 0 then
    cap = math.min(cap, height * CAP_OF_HEIGHT)
  end
  local file = texturePath()

  local top, body, bottom = pieces[1], pieces[2], pieces[3]
  eachPiece(frame, function(piece)
    piece:SetTexture(file)
    piece:Show()
  end)

  top:SetTexCoord(unpack(TOP_PIECE))
  top:SetSize(width, cap)
  top:ClearAllPoints()
  top:SetPoint("CENTER", frame, "TOP", 0, 0)

  bottom:SetTexCoord(unpack(BOTTOM_PIECE))
  bottom:SetSize(width, cap)
  bottom:ClearAllPoints()
  bottom:SetPoint("CENTER", frame, "BOTTOM", 0, 0)

  body:SetTexCoord(unpack(BODY_PIECE))
  body:ClearAllPoints()
  body:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, 0)
  body:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT", 0, 0)

  return true
end

-- The way its window arrives: the contents fade up over a third of a second
-- while the frame itself is already there. Taken from its FadeInContentFrame,
-- which runs FadeFrame(ContentFrame, 0.35, 1, 0) and plays the quest-list
-- sound. The sound is left to DialogueUI -- two of them at once is one too
-- many -- so this is the fade alone.
local FADE_SECONDS = 0.35

-- The buttons. DialogueUI dresses the one you are meant to press in
-- OptionBackground-Common.png and the one you are not in
-- OptionBackground-Hollow.png -- the red Annehmen and the grey Ablehnen on its
-- quest window. Ours are all "press me", so they get the red one.
local BUTTON_ART = {
  primary = "OptionBackground-Common.png",
  secondary = "OptionBackground-Hollow.png",
}

-- UIPanelButtonTemplate is three sliced textures on Classic and a single atlas
-- on Retail. Both are taken off rather than working out which this client has.
local TEMPLATE_PIECES = {"Left", "Middle", "Right"}
local PIECE_COUNT = 3

local skinned = {}


function Addon.SkinActionButton(button, kind)
  if type(button) ~= "table" or type(button.CreateTexture) ~= "function" then
    return false
  end
  if not skinned[button] then
    skinned[button] = kind or "primary"
  end

  local on = installed() and parchmentChosen()
  local slab = button.whwSlab

  for i = 1, PIECE_COUNT do
    local piece = button[TEMPLATE_PIECES[i]]
    if type(piece) == "table" and piece.SetShown then piece:SetShown(not on) end
  end

  if not on then
    if type(slab) == "table" and slab.Hide then slab:Hide() end
    if button.whwStripped and button.SetNormalTexture then
      button.whwStripped = nil
    end
    return false
  end

  if button.SetNormalTexture and not button.whwStripped then
    button.whwStripped = true
    button:SetNormalTexture("")
    if button.SetPushedTexture then button:SetPushedTexture("") end
  end

  if type(slab) ~= "table" then
    slab = button:CreateTexture(nil, "BACKGROUND")
    button.whwSlab = slab
    if slab.SetAllPoints then slab:SetAllPoints(button) end
  end
  slab:SetTexture(themeFile(BUTTON_ART[skinned[button]] or BUTTON_ART.primary))
  slab:Show()
  return true
end

-- Called when the style changes, since every button has to follow it.
function Addon.RefreshActionButtons()
  for button, kind in pairs(skinned) do
    Addon.SkinActionButton(button, kind)
  end
end

function Addon.FadeInPanel(frame)
  if not (frame and frame.SetAlpha) then return end
  if not installed() then return end
  if type(UIFrameFadeIn) ~= "function" then
    frame:SetAlpha(1)
    return
  end
  frame:SetAlpha(0)
  UIFrameFadeIn(frame, FADE_SECONDS, 0, 1)
end
