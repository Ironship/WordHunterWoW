local Addon = WordHunterWoW_Addon
local LABELS = Addon.LABELS
local unpack = unpack or table.unpack

-- Shared native chrome; clients without these atlases keep the existing skin.
local function hasAtlas(name)
  return C_Texture and type(C_Texture.GetAtlasInfo) == "function"
    and C_Texture.GetAtlasInfo(name) ~= nil
end
Addon.HasUIAtlas = hasAtlas

function Addon.CreateNativeWindow(name, kind, title, parent)
  parent = parent or UIParent
  local atlas = kind == "reader" and "QuestDetailsBackgrounds" or "collections-background-tile"
  if hasAtlas(atlas) then
    -- ButtonFrameTemplate for both kinds, the reader included. It is the one
    -- template on this client that brings a close button and draws it: the word
    -- editor is built from it, asks for no close button at all, and its cross is
    -- the only one in this addon that has ever shown. The flat reader template
    -- the reader used to wear brings none, and every attempt to supply one
    -- instead came out clickable and invisible. `kind` still decides how the
    -- window is painted, below and everywhere else.
    local template = "ButtonFrameTemplate"
    local ok, frame = pcall(CreateFrame, "Frame", name, parent, template .. ",BackdropTemplate")
    if ok and frame and type(frame.SetTitle) == "function" then
      frame.whwNativeStyle = kind
      if type(ButtonFrameTemplate_HidePortrait) == "function" then
        ButtonFrameTemplate_HidePortrait(frame)
      end
      local inset = rawget(frame, "Inset")
      if inset then inset:Hide() end
      frame:SetTitle(title)
      return frame
    end
    -- A partially supported template must not leave an orphaned visible window.
    if ok and frame then frame:Hide() end
  end
  return CreateFrame("Frame", name, parent, "BackdropTemplate")
end

-- Where the fill of a native window goes, which is the rectangle of Blizzard's
-- own Bg in ButtonFrameBaseTemplate (2,-21 / -2,2 in the Retail and Forever
-- templates) with one correction on the left. Any larger and the fill pokes out
-- past the frame's art, any smaller and the game shows through the gap; the
-- first try here used 8,-30 / -8,8 and left a strip along the top, right and
-- bottom, the second used Bg's own numbers and stuck out on the left.
--
-- The left is 5, not 2, because the frame art is not symmetrical: this layout
-- (ButtonFrameTemplateNoPortrait) puts its left corners 8 outside the frame and
-- its right ones only 4, so the metal line runs at about 5.7 from the left edge
-- but at about 1.7 inside the right one (measured off a screenshot at a scale
-- of 2.0). 5 puts the edge of the fill under the soft shadow that starts the
-- art; the right already meets the line, and the top and bottom were right.
--
-- Anything else drawn under the fill (the settings preview's checkerboard) has
-- to use this too, or it shows in exactly that gap.
local FILL_LEFT, FILL_TOP, FILL_RIGHT, FILL_BOTTOM = 5, 21, 2, 2

function Addon.AnchorNativeFill(region, frame)
  region:ClearAllPoints()
  region:SetPoint("TOPLEFT", frame, "TOPLEFT", FILL_LEFT, -FILL_TOP)
  region:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -FILL_RIGHT, FILL_BOTTOM)
end

-- The size of that rectangle for a window of the given size.
function Addon.NativeFillSize(width, height)
  return width - FILL_LEFT - FILL_RIGHT, height - FILL_TOP - FILL_BOTTOM
end

function Addon.PaintNativeWindow(frame, alpha)
  if not rawget(frame, "whwNativeStyle") then return false end
  -- Blizzard owns the border; full-frame backdrops bleed past its inset corners.
  frame:SetBackdrop(nil)
  for _, name in ipairs({ "Bg", "TopTileStreaks" }) do
    local region = rawget(frame, name)
    if region then region:Hide() end
  end
  local styleKey = Addon.GetBackgroundStyle()
  local native = styleKey == "native"
  local parchment = frame.whwNativeStyle == "reader" and native
  local atlas = parchment and "QuestDetailsBackgrounds" or "collections-background-tile"
  if not rawget(frame, "whwReadingBackground") then
    frame.whwReadingBackground = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
  end
  local bg = frame.whwReadingBackground
  Addon.AnchorNativeFill(bg, frame)
  if native and hasAtlas(atlas) then
    bg:SetAtlas(atlas)
    bg:SetHorizTile(not parchment); bg:SetVertTile(not parchment)
    local tint = parchment and 1 or .32
    bg:SetVertexColor(tint, tint, tint, 1)
  else
    local style = Addon.BACKGROUNDS[styleKey] or Addon.BACKGROUNDS.midnight
    local c = style.readingColor or Addon.BACKGROUNDS.midnight.readingColor
    if native then c = parchment and { .90, .77, .55 } or { .10, .08, .06 } end
    bg:SetColorTexture(c[1], c[2], c[3], 1)
    bg:SetVertexColor(1, 1, 1, 1)
  end
  bg:SetAlpha(alpha or Addon.GetOpacity())
  frame:SetToplevel(true)
  return true
end

-- True when this frame is drawn as the game's own quest parchment: a native
-- reader window under the Native (Blizzard) theme. That is the one surface in
-- this addon whose text is dark on light, so every colour on it comes from
-- Addon.COLORS_ON_LIGHT rather than from Addon.COLORS -- the two are the same
-- meanings at opposite brightnesses, and picking the wrong one is either
-- invisible text or a panel that looks lit from within.
--
-- The pair of conditions is the whole answer and is deliberately not
-- simplified: a window is built with whwNativeStyle once, at creation, and
-- keeps it when the player changes to one of the dark themes, where it is
-- painted dark and must wear the dark palette. Conversely a reader window
-- built before this addon knew about native chrome has neither.
function Addon.UsesLightSurface(frame)
  return frame ~= nil
    and rawget(frame, "whwNativeStyle") == "reader"
    and Addon.GetBackgroundStyle() == "native"
end

function Addon.ReaderInk(frame)
  return Addon.PaletteFor(Addon.UsesLightSurface(frame)).text
end

function Addon.EnglishHighlightColors(frame)
  local palette = Addon.PaletteFor(Addon.UsesLightSurface(frame))
  return palette.enHighlight, palette.enWordHighlight, palette.enHighlightBackground
end
function Addon.NativeCloseButton(frame)
  -- The template's own button, and nothing else. It is the only kind that has
  -- ever drawn here: the word editor is built from ButtonFrameTemplate and never
  -- asks for a close button at all, and its cross is the one that shows. Two
  -- attempts at supplying one instead -- a bare UIPanelCloseButton, then one
  -- with the Classic bitmap's texture coordinates put right -- both came out
  -- clickable and invisible in every window that asked. At fault was the
  -- replacing, not the button being replaced, so nothing is replaced now.
  local close = rawget(frame, "CloseButton")
  if close then
    rawset(frame, "closeButton", close)
    if Addon.ButtonShortcut then Addon.ButtonShortcut(close, "CLOSE", "ESCAPE", "PAD2") end
    return close
  end
  -- A frame with no inherited button still has to have a way out. Sized, since
  -- a template-less button has no size of its own.
  close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetSize(24, 24)
  rawset(frame, "closeButton", close)
  if Addon.ButtonShortcut then Addon.ButtonShortcut(close, "CLOSE", "ESCAPE", "PAD2") end
  return close
end

-- A window's heading, in whichever place its chrome keeps one. A native window
-- has a title bar of its own and the frame's own font string would sit over it
-- twice; a plain one has nothing but the font string. The copy and confirm
-- dialogs are pooled and rename themselves on every use, so this has to be
-- callable after creation, not only at it.
function Addon.SetWindowTitle(frame, title, fontString)
  if rawget(frame, "whwNativeStyle") and type(frame.SetTitle) == "function" then
    frame:SetTitle(title)
    if fontString then fontString:Hide() end
  elseif fontString then
    fontString:SetText(title)
    if fontString.Show then fontString:Show() end
  end
end

function Addon.CreateSearchBox(parent)
  if not hasAtlas("common-search-magnifyingglass") then return Addon.createEditBox(parent) end
  local ok, box = pcall(CreateFrame, "EditBox", nil, parent, "SearchBoxTemplate")
  if not ok then return Addon.createEditBox(parent) end
  box.whwNativeSearch = true
  box:SetAutoFocus(false); box:SetHeight(28)
  Addon.ApplyFontRole(box, "body")
  return box
end

function Addon.SetSearchChanged(box, handler)
  if rawget(box, 'whwNativeSearch') then box:HookScript('OnTextChanged', handler)
  else box:SetScript('OnTextChanged', handler) end
end

-- `parent` is what the inset belongs to and is hidden with, `scroll` is what it
-- frames, and `native` is the window whose chrome decides whether there is an
-- inset at all. Three frames rather than one because the library's word view is
-- a plain container inside a native window: the inset has to go away with the
-- container, and the container has no chrome of its own to ask.
function Addon.CreateContentInset(parent, scroll, native)
  native = native or parent
  if not rawget(native, "whwNativeStyle") then return end
  local ok, inset = pcall(CreateFrame, "Frame", nil, parent, "InsetFrameTemplate")
  if not ok then return end
  inset:SetPoint("TOPLEFT", scroll, "TOPLEFT", -6, 6)
  -- Flush with the scroll's own bottom rather than six pixels below it.
  -- InsetFrameTemplate's border is thick enough to draw inward from there, and
  -- anything that sits under the scroll -- the word list's page controls,
  -- the library's pagination row -- had a rule drawn straight
  -- through it. Every caller would otherwise have to leave room for an overhang
  -- it cannot see, and two of them did not.
  inset:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 14, 0)
  -- The window's level, not the container's: this draws *behind* the scroll it
  -- frames, and a level of the container's own would put it over the content.
  inset:SetFrameLevel(native:GetFrameLevel())
  inset:EnableMouse(false)
  local bg = rawget(inset, "Bg")
  if bg then bg:Hide() end
  return inset
end

function Addon.CreateStyledScrollFrame(parent)
  local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
  local bar = rawget(scroll, "ScrollBar")
  if not bar or not hasAtlas("minimal-scrollbar-track-top") then return scroll end
  bar:SetWidth(8)
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
  bar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
  for _, name in ipairs({ "ScrollUpButton", "ScrollDownButton", "Top", "Bottom", "Middle" }) do
    local region = rawget(bar, name)
    if region then
      region:Hide()
      -- The template shows its two arrows again every time the scroll range
      -- changes, which is whenever the text overflows -- so the column with
      -- more text than room grew arrows and the one that fitted did not. Hiding
      -- them once was never going to last; they are hidden whenever shown.
      if name:find("Button", 1, true) and region.HookScript then
        region:HookScript("OnShow", function(self) self:Hide() end)
      end
    end
  end
  local function threePieces(anchor, layer, names)
    local top = bar:CreateTexture(nil, layer)
    local mid = bar:CreateTexture(nil, layer)
    local bottom = bar:CreateTexture(nil, layer)
    top:SetAtlas(names[1]); mid:SetAtlas(names[2]); bottom:SetAtlas(names[3])
    top:SetSize(8, 8); bottom:SetSize(8, 8)
    top:SetPoint("TOPLEFT", anchor, "TOPLEFT"); top:SetPoint("TOPRIGHT", anchor, "TOPRIGHT")
    bottom:SetPoint("BOTTOMLEFT", anchor, "BOTTOMLEFT"); bottom:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT")
    mid:SetPoint("TOPLEFT", top, "BOTTOMLEFT"); mid:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT")
    return { top, mid, bottom }
  end
  threePieces(bar, "BACKGROUND", { "minimal-scrollbar-track-top", "!minimal-scrollbar-track-middle", "minimal-scrollbar-track-bottom" })
  local thumb = bar:GetThumbTexture()
  if thumb and hasAtlas("minimal-scrollbar-small-thumb-top") then
    thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
    thumb:SetVertexColor(1, 1, 1, 0)
    thumb:SetSize(8, 24)
    threePieces(thumb, "ARTWORK", { "minimal-scrollbar-small-thumb-top", "minimal-scrollbar-small-thumb-middle", "minimal-scrollbar-small-thumb-bottom" })
  end
  return scroll
end

function Addon.setBackdrop(frame, alpha)
  if Addon.ApplyBackground then
    Addon.ApplyBackground(frame, alpha)
    return
  end
  frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  frame:SetBackdropColor(0.04, 0.06, 0.10, alpha or 0.94)
  frame:SetToplevel(true)
end

-- Which of the four a word is set to, said three ways at once.
--
-- It used to be said in one and a half. The chosen button was tinted its own
-- colour at a fifth strength, which against a background of 0.06 is two shades
-- of black; its border went from 55% of the colour to 100%, a step you can find
-- if you already know which button to look at. And the label -- the brightest
-- thing on the button and the first thing an eye lands on -- was the same
-- colour in both states, so the strongest signal available carried no
-- information at all. Four buttons in a row, one of them chosen, and a player
-- could not tell which.
--
-- Now the chosen one is lit and the others are dimmed: a background that is
-- visibly its colour rather than a hint of it, a border at full strength
-- against a third, and a label in full white against a grey. Any one of the
-- three would do on its own, which is the point -- none of them has to be
-- noticed for the button to read as chosen.
--
-- The numbers are picked against the contrast floor rather than by eye.
-- tests/readability.test.lua holds every state of every status at 4.5:1, and
-- the tint is what threatens it: the brighter the chosen background, the closer
-- the white label gets to it. 0.38 measures 7.64:1 at worst -- that is `known`,
-- the palest of the four -- and the dimmed label measures 6.05:1 on black.
function Addon.styleFlatButton(button, color, active)
  if active then
    button:SetBackdropColor(color[1] * 0.38, color[2] * 0.38, color[3] * 0.38, 1)
    button:SetBackdropBorderColor(color[1], color[2], color[3], 1)
    button.label:SetTextColor(unpack(Addon.COLORS.text))
  else
    button:SetBackdropColor(0.06, 0.07, 0.09, 1)
    button:SetBackdropBorderColor(color[1] * 0.30, color[2] * 0.30, color[3] * 0.30, 0.6)
    local muted = Addon.COLORS.muted
    button.label:SetTextColor(muted[1] * 0.72, muted[2] * 0.72, muted[3] * 0.72)
  end
end

function Addon.createFlatButton(parent, text, color)
  local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
  button:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  button:SetHeight(Addon.RoleButtonHeight())
  button.label:SetPoint("CENTER")
  button.label:SetText(text)
  button.color = color
  Addon.styleFlatButton(button, color, false)
  button:SetScript("OnEnter", function(self)
    self:SetBackdropBorderColor(self.color[1], self.color[2], self.color[3], 1)
  end)
  button:SetScript("OnLeave", function(self)
    local active = self.status ~= nil and Addon.selected ~= nil and self.status == Addon.selected.status
    Addon.styleFlatButton(self, self.color, active)
  end)
  return button
end

local WHITE = "Interface\\Buttons\\WHITE8X8"

function Addon.createActionButton(parent, text)
  -- SharedButtonTemplate uses Blizzard's 128RedButton art and scales its caps.
  local template = hasAtlas("128-RedButton-Left") and "SharedButtonTemplate" or "UIPanelButtonTemplate"
  local button = CreateFrame("Button", nil, parent, template)
  button:SetText(text)
  return button
end

-- Matching text fields in place of the game's bevelled InputBoxTemplate art.
-- The editor's two fields did not even match each other:
-- one carried the single-line frame and the other the thicker scroll-box frame.
-- Done only when the frame can carry a backdrop; otherwise the template's own
-- border is left exactly as it was, because a field with neither is invisible.
local FIELD_FILL, FIELD_EDGE, FIELD_FOCUS = { 0.10, 0.12, 0.17, 1 }, { 0.45, 0.49, 0.57, 1 }, { 1, 0.82, 0, 1 }

function Addon.StyleInputField(frame, editBox)
  if not frame.SetBackdrop then return false end
  -- Hide template art before creating the backdrop, or its new textures vanish too.
  for _, region in ipairs({ frame:GetRegions() }) do
    if region.GetObjectType and region:GetObjectType() == "Texture" then region:Hide() end
  end
  frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  if NineSliceUtil and NineSliceUtil.ShowLayout then NineSliceUtil.ShowLayout(frame) end
  frame:SetBackdropColor(FIELD_FILL[1], FIELD_FILL[2], FIELD_FILL[3], FIELD_FILL[4])
  frame:SetBackdropBorderColor(FIELD_EDGE[1], FIELD_EDGE[2], FIELD_EDGE[3], FIELD_EDGE[4])
  editBox:HookScript("OnEditFocusGained", function()
    frame:SetBackdropBorderColor(FIELD_FOCUS[1], FIELD_FOCUS[2], FIELD_FOCUS[3], FIELD_FOCUS[4])
  end)
  editBox:HookScript("OnEditFocusLost", function()
    frame:SetBackdropBorderColor(FIELD_EDGE[1], FIELD_EDGE[2], FIELD_EDGE[3], FIELD_EDGE[4])
  end)
  return true
end

-- Equal-width buttons across a window's width, `margin` in from both sides. The
-- status row was laid out at a fixed 95 pixels a step, which is
-- exactly the width of an editor nobody has resized: stretch the window and the
-- fields beside them grew while the row stayed put against the left edge.
function Addon.SpreadButtons(frame, buttons, y, margin, gap)
  local count = #buttons
  if count == 0 then return end
  local width = (frame:GetWidth() - 2 * margin - gap * (count - 1)) / count
  if width < 1 then return end
  for index, button in ipairs(buttons) do
    button:ClearAllPoints()
    button:SetWidth(width)
    button:SetPoint("TOPLEFT", frame, "TOPLEFT", margin + (index - 1) * (width + gap), y)
  end
end

function Addon.createEditBox(parent)
  local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate,BackdropTemplate")
  box:SetFontObject("ChatFontNormal")
  -- For the family and the colour only. ChatFontNormal's size is whatever the
  -- player set for their chat window, which is not a decision anybody made
  -- about this addon and is an odd thing to size a translation field by; the
  -- body role puts it back on the same footing as every other line of text
  -- here. This box is in the editor and in the word list's search field, so it
  -- was two surfaces disagreeing, not one.
  Addon.ApplyFontRole(box, "body")
  box:SetAutoFocus(false)
  box:SetHeight(28)
  -- The template drew its text against its own bevel; with a flat edge the
  -- letters need the room back.
  if Addon.StyleInputField(box, box) then box:SetTextInsets(7, 7, 0, 0) end
  return box
end

local copyDialog

local confirmDialog

-- A themed yes/no rather than the game's StaticPopup, so it matches the window
-- it is asked from. It exists because overwriting what someone typed is not
-- something to do on a single click: the body says what the new value will be,
-- and cancelling is the wider of the two buttons.
-- Without an `onConfirm` there is nothing to confirm, so the action button is
-- taken away and Cancel is the only way out. The alternative -- leaving it up
-- with some harmless caption -- is what the empty-export dialog used to do, and
-- it put two buttons on screen that did exactly the same thing.
-- A dialog is a part of the window that opened it, so it is the size that
-- window is.
--
-- These two are pooled and parented to UIParent rather than to a caller, which
-- is what let them fall out of every scale: SCALED_WINDOWS names four frames
-- and neither of these is among them, so an editor dragged to 150% opened a
-- confirmation still at 100% and the pair looked like two addons. Tying them to
-- the editor's own setting would only move the fault: they are opened from the
-- editor, from the quest panel, from the settings page and from a slash command
-- with no window at all, and a "Copy quest" box wearing the editor's size is
-- still the wrong size.
--
-- Taking the opener's scale answers all four at once, including the quest
-- panel, which is deliberately never scaled and so hands over 1. Nothing to
-- open from -- the slash command -- is also 1, which is what UIParent gives.
local function matchOpener(dialog, opener)
  local scale = 1
  if opener and opener.GetScale then scale = opener:GetScale() or 1 end
  dialog:SetScale(scale)
end

function Addon.showConfirm(title, body, actionText, onConfirm, opener)
  if not confirmDialog then
    confirmDialog = Addon.CreateNativeWindow("WordHunterWoWConfirmDialog", "library", "")
    Addon.confirmDialog = confirmDialog
    confirmDialog:SetSize(460, 260)
    confirmDialog:SetPoint("CENTER")
    -- Above the editor it is asked from, which already sits high.
    confirmDialog:SetFrameStrata("TOOLTIP")
    confirmDialog:SetFrameLevel(400)
    confirmDialog:SetClampedToScreen(true)
    confirmDialog:EnableMouse(true)
    Addon.setBackdrop(confirmDialog, 1)

    confirmDialog.title = confirmDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    confirmDialog.title:SetPoint("TOPLEFT", 20, -22)
    confirmDialog.title:SetPoint("TOPRIGHT", -20, -22)
    confirmDialog.title:SetJustifyH("LEFT")

    confirmDialog.body = confirmDialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    confirmDialog.body:SetPoint("TOPLEFT", 20, -56)
    confirmDialog.body:SetPoint("TOPRIGHT", -20, -56)
    confirmDialog.body:SetJustifyH("LEFT")
    confirmDialog.body:SetJustifyV("TOP")
    confirmDialog.body:SetSpacing(3)

    confirmDialog.cancel = Addon.createActionButton(confirmDialog, LABELS.confirmCancel)
    confirmDialog.cancel:SetSize(120, Addon.RoleButtonHeight())
    confirmDialog.cancel:SetPoint("BOTTOMRIGHT", -20, 20)
    confirmDialog.cancel:SetScript("OnClick", function() confirmDialog:Hide() end)

    confirmDialog.action = Addon.createActionButton(confirmDialog, LABELS.confirmAction)
    confirmDialog.action:SetSize(120, Addon.RoleButtonHeight())
    confirmDialog.action:SetPoint("RIGHT", confirmDialog.cancel, "LEFT", -8, 0)
    confirmDialog.action:SetScript("OnClick", function()
      local run = confirmDialog.onConfirm
      confirmDialog:Hide()
      -- Cleared before running, so a handler that reopens this dialog cannot
      -- inherit the previous one's action.
      confirmDialog.onConfirm = nil
      if run then run() end
    end)

    -- Escape is cancel — the safe way out should be the easy one. Uses the same
    -- helper as every other window here, which lets every other key through
    -- rather than swallowing the keyboard while the dialog is up.
    Addon.SetupEscapeClose(confirmDialog)
  end

  Addon.SetWindowTitle(confirmDialog, title or "", confirmDialog.title)
  confirmDialog.body:SetText(body or "")
  confirmDialog.action:SetText(actionText or LABELS.confirmAction)
  confirmDialog.onConfirm = onConfirm
  -- The dialog is pooled, so this has to be set both ways every time.
  if onConfirm then confirmDialog.action:Show() else confirmDialog.action:Hide() end
  matchOpener(confirmDialog, opener)
  Addon.ApplyBackground(confirmDialog)
  confirmDialog:Show()
  confirmDialog:Raise()
end

-- `hint` replaces the generic line above the box. Copying a word or a quest
-- needs no explanation -- the player asked for it and knows why -- but the
-- harvest export does, so that one caller passes its own.
function Addon.showCopyText(title, value, hint, opener)
  if not copyDialog then
    copyDialog = Addon.CreateNativeWindow("WordHunterWoWCopyDialog", "library", "")
    Addon.copyDialog = copyDialog
    copyDialog:SetSize(520, 330)
    copyDialog:SetPoint("CENTER")
    copyDialog:SetFrameStrata("TOOLTIP")
    copyDialog:SetFrameLevel(200)
    copyDialog:SetClampedToScreen(true)
    copyDialog:EnableMouse(true)
    Addon.setBackdrop(copyDialog, 1)
    Addon.SetupEscapeClose(copyDialog)

    copyDialog.title = copyDialog:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    copyDialog.title:SetPoint("TOPLEFT", 20, -24)
    copyDialog.title:SetPoint("TOPRIGHT", -20, -24)
    copyDialog.title:SetHeight(24)
    copyDialog.title:SetJustifyH("LEFT")
    copyDialog.title:SetMaxLines(1)
    copyDialog.title:SetWordWrap(false)

    -- Kept on the dialog rather than local: the window is pooled, so a hint one
    -- caller set would otherwise still be up for the next one.
    copyDialog.hint = copyDialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    copyDialog.hint:SetTextColor(unpack(Addon.COLORS.muted))
    copyDialog.hint:SetPoint("TOPLEFT", 20, -52)
    copyDialog.hint:SetPoint("TOPRIGHT", -20, -52)
    copyDialog.hint:SetJustifyH("LEFT")

    copyDialog.scroll = CreateFrame("ScrollFrame", nil, copyDialog, "InputScrollFrameTemplate,BackdropTemplate")
    -- Under the hint rather than at a fixed offset, so a hint that wraps pushes
    -- the box down instead of being covered by it. The export's hint is three
    -- times the length of the generic one and only just fits on a line.
    copyDialog.scroll:SetPoint("TOPLEFT", copyDialog.hint, "BOTTOMLEFT", 0, -10)
    copyDialog.scroll:SetPoint("BOTTOMRIGHT", -20, 24)
    copyDialog.scroll.hideCharCount = true
    InputScrollFrame_OnLoad(copyDialog.scroll)
    copyDialog.text = copyDialog.scroll.EditBox
    copyDialog.text:SetFontObject("ChatFontNormal")
    -- Same reason as createEditBox: the family from the chat font, the size
    -- from the role. A dialog takes its opener's scale, so the frame does the
    -- multiplying and the role passes none.
    Addon.ApplyFontRole(copyDialog.text, "body")
    copyDialog.text:SetMultiLine(true)
    copyDialog.text:SetAutoFocus(false)
    Addon.StyleInputField(copyDialog.scroll, copyDialog.text)
    -- 0 means "no letters" on some clients, not "unlimited". A harvest blob is
    -- tens of kilobytes; the default cap is 255 and the box looks empty.
    if copyDialog.text.SetMaxLetters then copyDialog.text:SetMaxLetters(1024 * 1024) end
    copyDialog.text:SetScript("OnEscapePressed", function()
      Addon.CloseAll()
    end)

    local close = Addon.NativeCloseButton(copyDialog)
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
      copyDialog.text:ClearFocus()
      copyDialog:Hide()
    end)
  end

  Addon.SetWindowTitle(copyDialog, title, copyDialog.title)
  copyDialog.hint:SetText(hint or LABELS.copyHint)
  -- A lone "|" is a UI escape (colours, links). The harvest blob is full of
  -- them, so SetText ate the string and the box came up empty. Doubling is
  -- how every export box in the game shows a pipe; GetText/Ctrl+C give one.
  copyDialog.text:SetText((value or ""):gsub("|", "||"))
  matchOpener(copyDialog, opener)
  copyDialog:Show()
  copyDialog:Raise()
  copyDialog.text:SetFocus()
  copyDialog.text:SetCursorPosition(0)
  copyDialog.text:HighlightText()
  copyDialog.scroll:SetVerticalScroll(0)
end
