-- Enough of the game's globals to load the addon's UI files outside it.
--
-- Frames answer to anything, and make a child frame for any field they are
-- asked for, so layout code runs unchanged. Two things are modelled rather than
-- waved through, because tests turn on them: whether a frame is shown, and how
-- big it is.

strlower = string.lower
strtrim = function(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
time = os.time
date = os.date
GetLocale = function() return "deDE" end
UISpecialFrames = {}
tContains = function(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
tinsert = table.insert
InputScrollFrame_OnLoad = function() end
hooksecurefunc = function() end
-- Timers run at once: the tests are about what the code does, not when.
C_Timer = {
  After = function(_, fn) if fn then fn() end end,
  NewTimer = function(_, fn) if fn then fn() end return { Cancel = function() end } end,
}

local function node()
  local t = { scripts = {}, shown = false }
  function t:SetScript(name, fn) self.scripts[name] = fn end
  function t:HookScript(name, fn) self.scripts[name] = fn end
  function t:GetScript(name) return self.scripts[name] end
  function t:Show() self.shown = true end
  function t:Hide() self.shown = false end
  function t:IsShown() return self.shown end
  -- Size is real: layout code compares it against thresholds and resizes.
  -- Text is remembered so tests can read back what the UI displays.
  -- Stored under a private name: `text` is already a field the panel puts
  -- its font strings in.
  function t:SetText(v) self._text = v end
  function t:GetText() return self._text end
  function t:SetSize(w, h) self.w, self.h = w, h end
  function t:SetWidth(w) self.w = w end
  function t:SetHeight(h) self.h = h end
  function t:GetWidth() return self.w or 430 end
  function t:GetHeight() return self.h or 240 end
  function t:GetSize() return self:GetWidth(), self:GetHeight() end
  -- Measurements have to be numbers; the values do not matter.
  function t:GetStringWidth() return 40 end
  function t:GetStringHeight() return 10 end
  function t:GetNumPoints() return 0 end
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
GameFontHighlight = { GetFont = function() return "FRIZQT__.TTF", 12, "" end }
GameFontNormal, GameFontNormalSmall, GameFontDisableSmall = GameFontHighlight, GameFontHighlight, GameFontHighlight

-- The quest windows. Whether they are open decides whether the panel opens.
QuestFrame, QuestMapFrame, WorldMapFrame = node(), node(), node()
GetQuestID = function() return 184 end
GetTitleText = function() return "Sten Stoutarm" end
GetQuestText = function() return "Was haben wir denn hier?" end
GetObjectiveText = function() return "Bringt 8 Stücke zähes Wolfsfleisch." end
GetProgressText = function() return "" end
GetRewardText = function() return "" end

return node
