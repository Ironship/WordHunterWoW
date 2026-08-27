local Addon = WordHunterWoW_Addon
local LABELS = Addon.LABELS
local addonName = ...

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("QUEST_DETAIL")
events:RegisterEvent("QUEST_PROGRESS")
events:RegisterEvent("QUEST_COMPLETE")
events:RegisterEvent("QUEST_FINISHED")
events:SetScript("OnEvent", function(_, event, loadedAddon)
  if event == "ADDON_LOADED" then
    if loadedAddon == addonName then
      Addon.initializeDatabase()
      Addon.createPanel()
      Addon.createEditor()
      Addon.hookQuestUi()
      if Addon.CreateSettingsPanel then Addon.CreateSettingsPanel() end
      local target = Addon.GetTargetLocale()
      local client = GetLocale and GetLocale() or "enUS"
      if client ~= target then
        local name = Addon.SUPPORTED_LOCALES[target] or target
        print(string.format("|cff66ccffWordHunterWoW:|r " .. LABELS.german, name, name))
      end
    elseif loadedAddon == "Blizzard_UIPanels_Game" or loadedAddon == "Blizzard_WorldMap" then
      Addon.hookQuestUi()
    end
  elseif event == "QUEST_FINISHED" then
    if Addon.panel then Addon.panel:Hide() end
    if Addon.editor then Addon.editor:Hide() end
  else
    C_Timer.After(0, Addon.readCurrentQuest)
  end
end)

SLASH_WORDHUNTERWOW1 = "/whw"
SlashCmdList.WORDHUNTERWOW = function(message)
  local raw = strtrim(tostring(message or ""))
  local command = strlower(raw)
  if command == "reload" or command == "export" then
    Addon.rebuildExport()
    print("|cff66ccffWordHunterWoW:|r /reload writes the import file to SavedVariables.")
  elseif command == "words" then
    Addon.toggleWordList()
  elseif command == "stats" then
    Addon.toggleStats()
  elseif command == "settings" or command == "config" or command == "options" then
    if Addon.OpenSettings then Addon.OpenSettings() end
  elseif command:match("^bg%s+") then
    local key = strlower(strtrim(command:match("^bg%s+(.+)$") or ""))
    if Addon.BACKGROUNDS[key] then
      Addon.SetBackgroundStyle(key)
      print("|cff66ccffWordHunterWoW:|r Background: " .. Addon.BACKGROUNDS[key].name)
    else
      print("|cff66ccffWordHunterWoW:|r /whw bg <tooltip|dialog|solid|midnight>  •  /whw settings")
    end
  elseif command:match("^opacity%s*") or command:match("^alpha%s*") then
    local valStr = strtrim(command:match("^%S+%s*(.*)$") or "")
    if valStr == "" then
      print(string.format("|cff66ccffWordHunterWoW:|r Opacity: %d%%  •  /whw opacity <0-100>", math.floor(Addon.GetOpacity() * 100 + 0.5)))
    else
      local val = tonumber(valStr)
      if val and val > 1 and val <= 100 then val = val / 100 end
      if val and val >= 0 and val <= 1.0 then
        Addon.SetOpacity(val)
        print(string.format("|cff66ccffWordHunterWoW:|r Opacity: %d%%", math.floor(val * 100 + 0.5)))
      else
        print("|cff66ccffWordHunterWoW:|r /whw opacity <0-100>  •  e.g. /whw opacity 85")
      end
    end
  elseif command:match("^lang") then
    local arg = strtrim(command:match("^%S+%s*(.*)$") or "")
    if arg == "" then
      local cur = Addon.GetTargetLocale()
      print(string.format("|cff66ccffWordHunterWoW:|r Language: %s (%s)  •  /whw lang <%s>", Addon.SUPPORTED_LOCALES[cur] or cur, cur, table.concat(Addon.SUPPORTED_LOCALE_LIST, "|")))
    else
      local norm = strlower(strtrim(arg))
      local found
      for _, loc in ipairs(Addon.SUPPORTED_LOCALE_LIST) do
        if strlower(loc) == norm then found = loc; break end
      end
      if not found then
        for _, loc in ipairs(Addon.SUPPORTED_LOCALE_LIST) do
          if strlower(loc):sub(1,2) == norm:sub(1,2) then found = loc; break end
        end
      end
      if found and Addon.SUPPORTED_LOCALES[found] then
        Addon.SetTargetLocale(found)
        print(string.format("|cff66ccffWordHunterWoW:|r Language: %s (%s)", Addon.SUPPORTED_LOCALES[found], found))
      else
        print("|cff66ccffWordHunterWoW:|r /whw lang <" .. table.concat(Addon.SUPPORTED_LOCALE_LIST, "|") .. ">")
      end
    end
  elseif Addon.listFrame and Addon.listFrame:IsShown() then
    Addon.listFrame:Hide()
  elseif Addon.statsFrame and Addon.statsFrame:IsShown() then
    Addon.statsFrame:Hide()
  elseif Addon.panel and Addon.panel:IsShown() then
    Addon.panel:Hide()
    if Addon.editor then Addon.editor:Hide() end
  elseif Addon.panel then
    if Addon.lastQuest then Addon.refreshPanel() else print("|cff66ccffWordHunterWoW:|r " .. LABELS.empty) end
    Addon.panel:Show()
  end
end
