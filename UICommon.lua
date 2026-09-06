local Addon = WordHunterWoW_Addon
local LABELS = Addon.LABELS
local unpack = unpack or table.unpack

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

function Addon.createActionButton(parent, text)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetText(text)
  return button
end

function Addon.createEditBox(parent)
  local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  box:SetFontObject("ChatFontNormal")
  box:SetAutoFocus(false)
  box:SetHeight(28)
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
    confirmDialog = CreateFrame("Frame", "WordHunterWoWConfirmDialog", UIParent, "BackdropTemplate")
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
    confirmDialog.cancel:SetSize(120, 26)
    confirmDialog.cancel:SetPoint("BOTTOMRIGHT", -20, 20)
    confirmDialog.cancel:SetScript("OnClick", function() confirmDialog:Hide() end)

    confirmDialog.action = Addon.createActionButton(confirmDialog, LABELS.confirmAction)
    confirmDialog.action:SetSize(120, 26)
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

  confirmDialog.title:SetText(title or "")
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
    copyDialog = CreateFrame("Frame", "WordHunterWoWCopyDialog", UIParent, "BackdropTemplate")
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

    copyDialog.scroll = CreateFrame("ScrollFrame", nil, copyDialog, "InputScrollFrameTemplate")
    -- Under the hint rather than at a fixed offset, so a hint that wraps pushes
    -- the box down instead of being covered by it. The export's hint is three
    -- times the length of the generic one and only just fits on a line.
    copyDialog.scroll:SetPoint("TOPLEFT", copyDialog.hint, "BOTTOMLEFT", 0, -10)
    copyDialog.scroll:SetPoint("BOTTOMRIGHT", -20, 24)
    copyDialog.scroll.hideCharCount = true
    InputScrollFrame_OnLoad(copyDialog.scroll)
    copyDialog.text = copyDialog.scroll.EditBox
    copyDialog.text:SetFontObject("ChatFontNormal")
    copyDialog.text:SetMultiLine(true)
    copyDialog.text:SetAutoFocus(false)
    -- 0 means "no letters" on some clients, not "unlimited". A harvest blob is
    -- tens of kilobytes; the default cap is 255 and the box looks empty.
    if copyDialog.text.SetMaxLetters then copyDialog.text:SetMaxLetters(1024 * 1024) end
    copyDialog.text:SetScript("OnEscapePressed", function()
      Addon.CloseAll()
    end)

    local close = CreateFrame("Button", nil, copyDialog, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
      copyDialog.text:ClearFocus()
      copyDialog:Hide()
    end)
  end

  copyDialog.title:SetText(title)
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
