local Addon = WordHunterWoW_Addon

-- The pieces the game itself is built from, for the statistics window.
--
-- A window made only of coloured rectangles and one-pixel lines is a web page
-- dressed in a game's colours. The game's windows are made of stone and metal:
-- a dark stone ground with a bevelled inner frame round it, a plate with a
-- bronze rim behind a heading, tabs that are shaped like tabs, a gloss on a bar
-- so it reads as a thing with volume, an icon in a rim for anything that is an
-- item. All of that is art the client already carries, drawn here by name, so
-- nothing is shipped and nothing is copied: this file only says which piece goes
-- where. The same atlases My Forever Recipe Book and ForeverMats draw their
-- frames from (ForeverMats' own Style.lua is where the inset layout and the tab
-- pieces were first put together, and its author is the author of this addon).
--
-- Every function checks that the piece exists first and answers false when it
-- does not -- the Era client has hardly any of these atlases -- and the caller
-- then draws its flat version, which is the whole of what that client gets.

local Kit = {}
Addon.Kit = Kit

local known = {}
local function has(name)
  if known[name] == nil then
    known[name] = C_Texture ~= nil and type(C_Texture.GetAtlasInfo) == "function"
      and C_Texture.GetAtlasInfo(name) ~= nil
  end
  return known[name]
end
Kit.Has = has

local function all(names)
  for _, name in ipairs(names) do
    if not has(name) then return false end
  end
  return true
end

-- The inner frame the game puts round the content of a panel.
local INSET_ATLASES = {
  "UI-Frame-InnerTopLeft", "UI-Frame-InnerTopRight", "UI-Frame-InnerBotLeftCorner", "UI-Frame-InnerBotRight",
  "_UI-Frame-InnerTopTile", "_UI-Frame-InnerBotTile", "!UI-Frame-InnerLeftTile", "!UI-Frame-InnerRightTile",
}
local INSET_LAYOUT = {
  TopLeftCorner = { atlas = "UI-Frame-InnerTopLeft" }, TopRightCorner = { atlas = "UI-Frame-InnerTopRight" },
  BottomLeftCorner = { atlas = "UI-Frame-InnerBotLeftCorner", y = -1 },
  BottomRightCorner = { atlas = "UI-Frame-InnerBotRight", y = -1 },
  TopEdge = { atlas = "_UI-Frame-InnerTopTile" }, BottomEdge = { atlas = "_UI-Frame-InnerBotTile" },
  LeftEdge = { atlas = "!UI-Frame-InnerLeftTile" }, RightEdge = { atlas = "!UI-Frame-InnerRightTile" },
}

local STONE, STONE_CARD, PLATE = "UI-Character-Info-Stat-BG", "UI-Character-Info-Stat-StoneBG3", "UI-Character-Info-Title"
local TABS = {
  active = { "uiframe-activetab-left", "_uiframe-activetab-center", "uiframe-activetab-right" },
  inactive = { "uiframe-tab-left", "_uiframe-tab-center", "uiframe-tab-right" },
}

function Kit.CanInset()
  return NineSliceUtil ~= nil and NineSliceUtil.ApplyLayout ~= nil and all(INSET_ATLASES)
end

-- The dark stone of the Forever and Era character sheet is not in the Retail
-- client, which keeps the same dark tiled ground in its Collections frame and
-- its Dungeon Journal. That tile is what Retail gets: the same idea of a window
-- made of stone, from the art the client does carry.
local TILE = "collections-background-tile"

function Kit.CanStone()
  return (has(STONE) and has(STONE_CARD)) or has(TILE)
end

function Kit.CanPlate()
  return has(PLATE)
end

function Kit.CanTabs()
  return all(TABS.active) and all(TABS.inactive)
end

-- A border round a frame: the bevelled inner frame, the tooltip's rim, or none.
-- Both are built the first time they are wanted and shown or hidden after that,
-- so a change of theme costs two Show calls. Answers whether a border is drawn,
-- which is how the caller knows whether to draw its own flat line instead.
function Kit.SetBorder(frame, mode, color)
  local inset, rim = rawget(frame, "whwKitInset"), rawget(frame, "whwKitRim")
  local drawn = false
  if mode == "inset" and Kit.CanInset() then
    if not inset then
      inset = CreateFrame("Frame", nil, frame)
      inset:SetAllPoints(frame)
      inset:EnableMouse(false)
      inset:SetFrameLevel(frame:GetFrameLevel() + 3)
      local layout = NineSliceUtil.GetLayout and NineSliceUtil.GetLayout("InsetFrameTemplate") or INSET_LAYOUT
      NineSliceUtil.ApplyLayout(inset, layout)
      frame.whwKitInset = inset
    end
    inset:Show()
    drawn = true
  elseif inset then
    inset:Hide()
  end
  if mode == "rim" then
    if not rim then
      rim = CreateFrame("Frame", nil, frame, "BackdropTemplate")
      rim:SetAllPoints(frame)
      rim:EnableMouse(false)
      rim:SetFrameLevel(frame:GetFrameLevel() + 3)
      rim:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
      frame.whwKitRim = rim
    end
    local c = color or { 0.8, 0.82, 0.9, 0.9 }
    rim:SetBackdropBorderColor(c[1], c[2], c[3], c[4] or 1)
    rim:Show()
    drawn = true
  elseif rim then
    rim:Hide()
  end
  return drawn
end

-- The ground of a chart or a card: dark stone under the stone themes, the
-- theme's own flat colour under the others. `role` is "plot" or "card".
function Kit.Ground(texture, theme, role)
  if theme.kit == "stone" and Kit.CanStone() then
    local t = theme.tint or { 1, 1, 1 }
    if has(STONE) and has(STONE_CARD) then
      texture:SetAtlas(role == "card" and STONE_CARD or STONE)
      texture:SetHorizTile(false); texture:SetVertTile(false)
      texture:SetVertexColor(t[1], t[2], t[3], role == "card" and 0.95 or 0.92)
    else
      -- The tile is far brighter than the stone it stands in for, and the window
      -- behind it is already the same tile at a third of its brightness.
      local lift = role == "card" and 0.42 or 0.50
      texture:SetAtlas(TILE)
      texture:SetHorizTile(true); texture:SetVertTile(true)
      texture:SetVertexColor(t[1] * lift, t[2] * lift, t[3] * lift, 0.95)
    end
    return true
  end
  if texture.SetHorizTile then texture:SetHorizTile(false); texture:SetVertTile(false) end
  local c = theme[role]
  texture:SetColorTexture(c[1], c[2], c[3], c[4] or 1)
  texture:SetVertexColor(1, 1, 1, 1)
  return false
end

-- The plate behind a heading: a bar with a bronze rim, where the theme has one.
-- The plate is a bar with a flourish at each end. Stretched across a whole
-- window the flourishes stretch with it, so it is drawn in three pieces: the two
-- ends at the size they were made, and between them the plain middle, which is
-- the only part that grows. `texture` keeps the plate's place on the page; the
-- pieces are drawn on it.
local PLATE_CAP = 0.30

local function platePieces(texture)
  local pieces = rawget(texture, "whwPlate")
  if pieces then return pieces end
  local info = C_Texture.GetAtlasInfo(PLATE)
  local file = info and (info.file or info.filename)
  -- Without the file and the coordinates it sits at there is nothing to cut.
  if not (file and type(info.leftTexCoord) == "number" and type(info.rightTexCoord) == "number"
      and type(info.topTexCoord) == "number" and type(info.bottomTexCoord) == "number"
      and type(info.width) == "number" and type(info.height) == "number" and info.height > 0) then
    return nil
  end
  local parent = texture:GetParent()
  pieces = { left = parent:CreateTexture(nil, "BACKGROUND", nil, 1), right = parent:CreateTexture(nil, "BACKGROUND", nil, 1),
    mid = parent:CreateTexture(nil, "BACKGROUND", nil, 1) }
  local u0, u1 = info.leftTexCoord, info.rightTexCoord
  local v0, v1 = info.topTexCoord, info.bottomTexCoord
  local cap = (u1 - u0) * PLATE_CAP
  for _, piece in pairs(pieces) do piece:SetTexture(file) end
  pieces.left:SetTexCoord(u0, u0 + cap, v0, v1)
  pieces.right:SetTexCoord(u1 - cap, u1, v0, v1)
  pieces.mid:SetTexCoord(u0 + cap, u1 - cap, v0, v1)
  -- Each end as wide as the art is, scaled to the plate's height.
  local ratio = (info.width * PLATE_CAP) / info.height
  texture.whwPlateRatio = ratio
  pieces.left:SetPoint("TOPLEFT", texture, "TOPLEFT")
  pieces.left:SetPoint("BOTTOMLEFT", texture, "BOTTOMLEFT")
  pieces.right:SetPoint("TOPRIGHT", texture, "TOPRIGHT")
  pieces.right:SetPoint("BOTTOMRIGHT", texture, "BOTTOMRIGHT")
  pieces.mid:SetPoint("TOPLEFT", pieces.left, "TOPRIGHT")
  pieces.mid:SetPoint("BOTTOMRIGHT", pieces.right, "BOTTOMLEFT")
  texture.whwPlate = pieces
  return pieces
end

function Kit.PaintPlate(texture, theme)
  local pieces = rawget(texture, "whwPlate")
  if theme.kit == "stone" and Kit.CanPlate() then
    pieces = platePieces(texture)
    if pieces then
      local t = theme.tint or { 1, 1, 1 }
      local height = texture:GetHeight() > 0 and texture:GetHeight() or 24
      local capWidth = math.floor(height * rawget(texture, "whwPlateRatio") + 0.5)
      for _, piece in pairs(pieces) do
        piece:SetVertexColor(t[1], t[2], t[3], 1)
        piece:Show()
      end
      pieces.left:SetWidth(capWidth)
      pieces.right:SetWidth(capWidth)
      texture:SetColorTexture(0, 0, 0, 0)
      texture:Show()
      return true
    end
    -- No coordinates to cut it by: the whole plate, stretched, is the next best.
    local t = theme.tint or { 1, 1, 1 }
    texture:SetAtlas(PLATE)
    texture:SetVertexColor(t[1], t[2], t[3], 1)
    texture:Show()
    return true
  end
  if pieces then for _, piece in pairs(pieces) do piece:Hide() end end
  texture:Hide()
  return false
end

-- A colour that is lit on its left and dim on its right, which is all it takes
-- to make a flat bar look like it has a body. The client's gradient call takes
-- colour objects; an older one takes numbers, and the pcall lets either
-- through without a branch on the version.
local function clamp(v) return v > 1 and 1 or v end

-- A status bar's colour is exactly the status colour. Volume comes from layers
-- laid over it (the stone's grain and a lit edge along the top, as on the chart
-- columns), never from a gradient: a gradient is multiplied into the texture's
-- colour on some clients, and a bar that is the same colour as its legend on one
-- client and a darker one on another was the whole of the complaint.
function Kit.Gloss(texture, c, alpha, theme)
  texture:SetColorTexture(c[1], c[2], c[3], alpha)
  local layers = rawget(texture, "whwGloss")
  if theme and theme.kit ~= "flat" then
    if not layers then
      layers = { lip = texture:GetParent():CreateTexture(nil, "ARTWORK", nil, 2) }
      texture.whwGloss = layers
    end
    Kit.Speckle(texture, theme)
    layers.lip:SetColorTexture(1, 0.95, 0.8, 0.30)
    layers.lip:ClearAllPoints()
    layers.lip:SetPoint("TOPLEFT", texture, "TOPLEFT")
    layers.lip:SetPoint("TOPRIGHT", texture, "TOPRIGHT")
    layers.lip:SetHeight(1)
    layers.lip:Show()
  else
    if layers then layers.lip:Hide() end
    Kit.Speckle(texture, theme)
  end
end

-- Those layers follow the texture they are on when it is hidden.
function Kit.GlossShown(texture, shown)
  local layers = rawget(texture, "whwGloss")
  local lit = shown and rawget(texture, "whwGrainOn") == true
  if layers then layers.lip:SetShown(lit) end
  local grain = rawget(texture, "whwGrain")
  if grain then grain:SetShown(lit) end
end

-- An icon in a rim, the way the game draws an item: the rim is white art and
-- takes whatever colour it is given, so a quality colour here is a status colour.
function Kit.IconFrame(parent, size)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetSize(size, size)
  frame.icon = frame:CreateTexture(nil, "ARTWORK")
  frame.icon:SetPoint("TOPLEFT", 3, -3)
  frame.icon:SetPoint("BOTTOMRIGHT", -3, 3)
  frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  frame.rim = frame:CreateTexture(nil, "OVERLAY")
  frame.rim:SetAllPoints()
  frame.rim:SetTexture("Interface\\Common\\WhiteIconFrame")
  return frame
end

function Kit.SetIcon(frame, path, rim)
  frame.icon:SetTexture("Interface\\Icons\\" .. path)
  rim = rim or { 0.7, 0.7, 0.7 }
  frame.rim:SetVertexColor(rim[1], rim[2], rim[3], 0.95)
end

-- The game's own tab, built as ForeverMats builds it: a left piece, a right
-- piece and a middle that tiles, once lit and once not. Added to an existing
-- button, whose own look is then switched off while these are in use.
function Kit.AttachTabArt(button)
  local made = rawget(button, "whwTabArt")
  if made then return made end
  if not Kit.CanTabs() then return nil end
  local art = {}
  for state, names in pairs(TABS) do
    local pieces = {}
    for index, name in ipairs(names) do
      -- The lit set sits above the dim one, so it can be laid over it on hover.
      local piece = button:CreateTexture(nil, "BACKGROUND", nil, state == "active" and 0 or -1)
      piece:SetAtlas(name, true)
      piece:SetHeight(32)
      pieces[index] = piece
    end
    pieces[1]:SetPoint("TOPLEFT", 0, 0)
    pieces[3]:SetPoint("TOPRIGHT", 0, 0)
    pieces[2]:SetPoint("TOPLEFT", pieces[1], "TOPRIGHT")
    pieces[2]:SetPoint("TOPRIGHT", pieces[3], "TOPLEFT")
    pieces[2]:SetHorizTile(true)
    art[state] = pieces
  end
  -- Under the pointer an unchosen tab shows the lit tab's art over its own, which
  -- fits the tab exactly: any highlight texture of the button's is a rectangle,
  -- and the art does not fill its rectangle.
  button:HookScript("OnEnter", function(self) Kit.HoverTabArt(self, true) end)
  button:HookScript("OnLeave", function(self) Kit.HoverTabArt(self, false) end)
  button.whwTabArt = art
  return art
end

-- Which of the two sets shows, or neither (`state` nil) when the theme draws
-- its tabs some other way.
function Kit.ShowTabArt(button, state)
  local art = rawget(button, "whwTabArt")
  if not art then return end
  button.whwTabState = state
  for name, pieces in pairs(art) do
    for _, piece in ipairs(pieces) do
      piece:SetAlpha(1)
      piece:SetShown(name == state)
    end
  end
end

-- The lit tab drawn faintly over an unchosen one, while the pointer is on it.
function Kit.HoverTabArt(button, on)
  local art = rawget(button, "whwTabArt")
  if not art or rawget(button, "whwTabState") ~= "inactive" then return end
  if button.IsEnabled and not button:IsEnabled() then return end
  for _, piece in ipairs(art.active) do
    piece:SetAlpha(0.45)
    piece:SetShown(on)
  end
end

-- The height the tab art is drawn at, for a tab that is not the usual 32.
function Kit.SizeTabArt(button, height)
  local art = rawget(button, "whwTabArt")
  if not art then return end
  for _, pieces in pairs(art) do
    for _, piece in ipairs(pieces) do piece:SetHeight(height) end
  end
end

-- Both sets of the art in one colour. The art is bronze and takes a tint the way
-- the quality rim does, which is how a tab can say "this one is Known".
function Kit.TintTabArt(button, r, g, b)
  local art = rawget(button, "whwTabArt")
  if not art then return end
  for _, pieces in pairs(art) do
    for _, piece in ipairs(pieces) do piece:SetVertexColor(r, g, b, 1) end
  end
end

-- ---------------------------------------------------------------------------
-- The pieces every window shares.
--
-- Whatever a window is made of, its fields, its drop-downs and its toggle
-- buttons come from here, so they change with the background style together
-- and a player who picks a style gets one addon, not a styled statistics window
-- among plain ones.
-- ---------------------------------------------------------------------------

-- Callbacks that redraw something when the style changes, called once at the
-- moment they are registered and again by Kit.Refresh. Held weakly by owner
-- would buy nothing: every one of them belongs to a window that lives as long
-- as the session.
local painters = {}

function Kit.OnRefresh(fn)
  painters[#painters + 1] = fn
  -- Charts.lua, which owns the themes, loads after this file.
  if Addon.ChartTheme then fn(Addon.ChartTheme()) end
end

function Kit.Refresh()
  local theme = Addon.ChartTheme()
  for _, fn in ipairs(painters) do fn(theme) end
end

local WHITE = "Interface\\Buttons\\WHITE8X8"
local TOOLTIP_RIM = "Interface\\Tooltips\\UI-Tooltip-Border"
local GOLD = { 1, 0.82, 0 }

-- A text field or a drop-down: sunk into the window, with the border the game
-- gives a field. The stone styles use the tooltip's rim in bronze, the tooltip
-- style the same rim in steel, and the flat styles a one pixel line.
local function paintField(frame)
  local theme = Addon.ChartTheme()
  local focus = rawget(frame, "whwFocus")
  local fill, edge
  if theme.kit == "flat" then
    fill, edge = theme.card, theme.rule
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  else
    fill = theme.kit == "stone" and { 0.05, 0.045, 0.04, 1 } or { 0.02, 0.03, 0.07, 1 }
    edge = theme.kit == "stone" and { 0.85, 0.72, 0.48, 1 } or { 0.80, 0.82, 0.90, 1 }
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = TOOLTIP_RIM, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  end
  frame:SetBackdropColor(fill[1], fill[2], fill[3], 1)
  if focus then
    frame:SetBackdropBorderColor(GOLD[1], GOLD[2], GOLD[3], 1)
  else
    frame:SetBackdropBorderColor(edge[1], edge[2], edge[3], edge[4] or 1)
  end
end

Kit.PaintField = paintField

function Kit.SkinField(frame, editBox)
  if not frame.SetBackdrop then return false end
  painters[#painters + 1] = function() paintField(frame) end
  paintField(frame)
  if editBox then
    editBox:HookScript("OnEditFocusGained", function()
      frame.whwFocus = true
      paintField(frame)
    end)
    editBox:HookScript("OnEditFocusLost", function()
      frame.whwFocus = nil
      paintField(frame)
    end)
  end
  return true
end

-- A toggle that is one of several (the four statuses, the filters of a list):
-- the game's tab art in the status colour, lit when it is the chosen one. Answers
-- false when the style or the client has no such art, and the caller paints its
-- flat version. `hover` brightens an unchosen one.
function Kit.PaintToggle(button, color, active, hover)
  local theme = Addon.ChartTheme()
  if theme.kit ~= "stone" or not Kit.AttachTabArt(button) then
    Kit.ShowTabArt(button, nil)
    return false
  end
  Kit.SizeTabArt(button, button:GetHeight() > 0 and button:GetHeight() or 24)
  button:SetBackdropColor(0, 0, 0, 0)
  button:SetBackdropBorderColor(0, 0, 0, 0)
  Kit.ShowTabArt(button, active and "active" or "inactive")
  -- Half the status colour over the art's own bronze: enough to tell the four
  -- apart across a row, not so much that the cream label loses its ground.
  local k = active and 0.60 or (hover and 0.50 or 0.40)
  local base = active and 1 or 0.78
  Kit.TintTabArt(button, base * (1 - k) + color[1] * k, base * (1 - k) + color[2] * k, base * (1 - k) + color[3] * k)
  button.label:SetTextColor(1, active and 0.94 or 0.82, active and 0.77 or 0.62)
  button.label:ClearAllPoints()
  button.label:SetPoint("CENTER", 0, 1)
  button.whwKitLabel = true
  return true
end

-- The toggle buttons of every window, painted again when the style changes.
Kit.OnRefresh(function()
  for _, button in ipairs(Addon.flatButtons or {}) do
    Addon.styleFlatButton(button, button.color, button.whwActive)
  end
end)

-- A command button: lit bronze tab art under the stone styles, the tooltip's rim
-- on navy under the rim style, a one pixel line on the theme's card colour under
-- the flat ones. Brighter under the pointer, darker pressed, dim when disabled.
function Kit.PaintAction(button)
  local theme = Addon.ChartTheme()
  local label = rawget(button, "label")
  if not label then return end
  local enabled = button:IsEnabled()
  -- The game's red button, drawn by its template: show that art and take ours
  -- away. Only the label's colour is put back by hand, since the game sets it
  -- through font objects that a colour set here would have overridden.
  local matched = Addon.GetButtonStyle and Addon.GetButtonStyle() == "match"
  for _, region in ipairs(rawget(button, "whwTemplateArt") or {}) do region:SetAlpha(matched and 0 or 1) end
  if not matched then
    if rawget(button, "whwTabArt") then Kit.ShowTabArt(button, nil) end
    if rawget(button, "whwPainted") then
      button.whwPainted = nil
      button:SetBackdrop(nil)
      if enabled then label:SetTextColor(1, 0.82, 0) else label:SetTextColor(0.5, 0.5, 0.5) end
    end
    return
  end
  button.whwPainted = true
  local hover, pressed = rawget(button, "whwHover"), rawget(button, "whwPressed")
  local lr, lg, lb
  if theme.kit == "stone" and Kit.AttachTabArt(button) then
    Kit.SizeTabArt(button, button:GetHeight() > 0 and button:GetHeight() or 24)
    button:SetBackdrop(nil)
    Kit.ShowTabArt(button, enabled and "active" or "inactive")
    local t = theme.tint or { 1, 1, 1 }
    local k = not enabled and 0.55 or (pressed and 0.60 or (hover and 1 or 0.80))
    Kit.TintTabArt(button, t[1] * k, t[2] * k, t[3] * k)
    if enabled then lr, lg, lb = 1, 0.94, 0.77 else lr, lg, lb = 0.55, 0.50, 0.42 end
  else
    Kit.ShowTabArt(button, nil)
    local fill, edge
    if theme.kit == "rim" then
      button:SetBackdrop({ bgFile = WHITE, edgeFile = TOOLTIP_RIM, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      fill = not enabled and { 0.05, 0.06, 0.09 } or (pressed and { 0.03, 0.05, 0.09 })
        or (hover and { 0.11, 0.15, 0.24 }) or { 0.07, 0.10, 0.17 }
      edge = hover and enabled and { 1, 1, 1 } or { 0.80, 0.82, 0.90 }
      if enabled then lr, lg, lb = 0.95, 0.97, 1 else lr, lg, lb = 0.50, 0.53, 0.60 end
    else
      button:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
      fill = not enabled and theme.plot or (pressed and theme.plot) or (hover and theme.track) or theme.card
      edge = hover and enabled and theme.accent or theme.rule
      local text, muted = Addon.COLORS.text, Addon.COLORS.muted
      if enabled then lr, lg, lb = text[1], text[2], text[3]
      else lr, lg, lb = muted[1] * 0.72, muted[2] * 0.72, muted[3] * 0.72 end
    end
    button:SetBackdropColor(fill[1], fill[2], fill[3], 1)
    button:SetBackdropBorderColor(edge[1], edge[2], edge[3], 1)
  end
  label:SetTextColor(lr, lg, lb)
  -- A button carrying a shortcut line has its label placed by the layout code.
  if not rawget(button, "shortcutHint") then
    label:ClearAllPoints()
    label:SetPoint("CENTER", 0, pressed and 0 or 1)
  end
end

Kit.OnRefresh(function()
  for _, button in ipairs(Addon.actionButtons or {}) do Kit.PaintAction(button) end
end)

-- The colour a bar is painted. It is the status colour exactly as the palette
-- (and the player) set it: the bar, the legend that names it, the word in the
-- quest text and the figure beside it are one colour, and a colour the player
-- chose is not second-guessed. The softening the stone styles once did here now
-- lives in the default palette itself.
function Kit.Tone(c)
  return c[1], c[2], c[3]
end

-- The mottling of the stone laid over a bar's colour, so a column reads as a
-- slab of something and not as a coloured rectangle. Answers false (and hides
-- the texture) where the style or the client has no such tile.
function Kit.Grain(texture, theme, alpha)
  if theme.kit ~= "flat" and has(TILE) then
    texture:SetAtlas(TILE)
    texture:SetHorizTile(true); texture:SetVertTile(true)
    texture:SetVertexColor(1, 1, 1, alpha or 0.3)
    texture:Show()
    return true
  end
  texture:Hide()
  return false
end

-- How much of the stone shows through a colour. It darkens what it is laid on,
-- so it is kept faint, and it is laid on everything that names a status colour
-- (bars, legend swatches, dots) alike, so they are one shade.
Kit.GRAIN = 0.16

-- The grain over a texture that is a patch of colour, as a layer of its own on
-- the texture's parent. Hidden where the style has none.
function Kit.Speckle(texture, theme)
  local layer = rawget(texture, "whwGrain")
  if not layer then
    layer = texture:GetParent():CreateTexture(nil, "ARTWORK", nil, 1)
    texture.whwGrain = layer
  end
  local on = Kit.Grain(layer, theme, Kit.GRAIN)
  texture.whwGrainOn = on
  if on then
    layer:ClearAllPoints()
    layer:SetAllPoints(texture)
    layer:SetShown(texture:IsShown())
  end
  return on
end

-- A colour paler and a little duller, for what is estimated rather than known.
-- Opaque, like everything else drawn in stone: the difference is in the colour.
function Kit.Pale(r, g, b)
  local m = 0.30
  return r * (1 - m) + 0.82 * m, g * (1 - m) + 0.78 * m, b * (1 - m) + 0.64 * m
end
