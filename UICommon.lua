local Addon = WordHunterWoW_Addon
local LABELS = Addon.LABELS

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

function Addon.styleFlatButton(button, color, active)
  if active then
    button:SetBackdropColor(color[1] * 0.65, color[2] * 0.65, color[3] * 0.65, 0.98)
    button:SetBackdropBorderColor(color[1], color[2], color[3], 1)
  else
    button:SetBackdropColor(0, 0, 0, 0.35)
    button:SetBackdropBorderColor(color[1] * 0.55, color[2] * 0.55, color[3] * 0.55, 0.9)
  end
  if active then
    button.label:SetTextColor(1, 1, 1)
  else
    button.label:SetTextColor(color[1], color[2], color[3])
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

function Addon.showCopyText(title, value)
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

    local hint = copyDialog:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 20, -52)
    hint:SetText(LABELS.copyHint)

    copyDialog.scroll = CreateFrame("ScrollFrame", nil, copyDialog, "InputScrollFrameTemplate")
    copyDialog.scroll:SetPoint("TOPLEFT", 20, -74)
    copyDialog.scroll:SetPoint("BOTTOMRIGHT", -20, 24)
    copyDialog.scroll.hideCharCount = true
    InputScrollFrame_OnLoad(copyDialog.scroll)
    copyDialog.text = copyDialog.scroll.EditBox
    copyDialog.text:SetFontObject("ChatFontNormal")
    copyDialog.text:SetMultiLine(true)
    copyDialog.text:SetAutoFocus(false)
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
  copyDialog.text:SetText(value or "")
  copyDialog:Show()
  copyDialog:Raise()
  copyDialog.text:SetFocus()
  copyDialog.text:SetCursorPosition(0)
  copyDialog.text:HighlightText()
  copyDialog.scroll:SetVerticalScroll(0)
end
