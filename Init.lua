local Addon = WordHunterWoW_Addon
local LABELS = Addon.LABELS
local addonName = ...

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("QUEST_DETAIL")
events:RegisterEvent("QUEST_PROGRESS")
events:RegisterEvent("QUEST_COMPLETE")
events:RegisterEvent("QUEST_FINISHED")
events:RegisterEvent("GOSSIP_SHOW")
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
    elseif loadedAddon == "Blizzard_UIPanels_Game" or loadedAddon == "Blizzard_WorldMap"
        or loadedAddon == "Blizzard_QuestLog" then
      -- Classic's quest log is a load-on-demand addon of its own, so the names
      -- worth hooking may not exist until the player first opens it.
      Addon.hookQuestUi()
    end
  elseif event == "PLAYER_LOGIN" then
    -- The season only answers reliably once the player is in the world, and
    -- Classic's quest log may have loaded since ADDON_LOADED.
    Addon.Compat.Refresh()
    Addon.hookQuestUi()
  elseif event == "GOSSIP_SHOW" then
    if Addon.HarvestGossip then Addon.HarvestGossip() end
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
  elseif command:match("^harvest") then
    local arg = strtrim(command:match("^%S+%s*(.*)$") or "")
    if arg == "on" or arg == "off" then
      Addon.SetHarvestEnabled(arg == "on")
      print("|cff66ccffWordHunterWoW:|r Text collection " .. arg .. ".")
    elseif arg == "clear" then
      Addon.ClearHarvest()
      print("|cff66ccffWordHunterWoW:|r Collected text cleared.")
    elseif arg == "export" then
      local n = Addon.rebuildHarvestExport()
      print(string.format("|cff66ccffWordHunterWoW:|r %d passages written to SavedVariables. Reload or log out first, then import.", n))
    else
      print(string.format("|cff66ccffWordHunterWoW:|r Text collection %s, %d passages and %d unglossed words for %s.  •  /whw harvest <on|off|export|clear>",
        Addon.GetHarvestEnabled() and "on" or "off", Addon.HarvestCount() - Addon.HarvestWordCount(),
        Addon.HarvestWordCount(), Addon.GetTargetLocale()))
    end
  elseif command == "reset" or command == "resetlayout" then
    -- A way back from a window dragged off the screen or shrunk to nothing.
    -- Without one the only remedy is deleting the saved file, which takes the
    -- player's whole word list with it.
    Addon.ResetLayout()
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
        local matches = {}
        for _, loc in ipairs(Addon.SUPPORTED_LOCALE_LIST) do
          if strlower(loc):sub(1, #norm) == norm then matches[#matches + 1] = loc end
        end
        -- "es" matches esES and esMX; only a unique prefix is safe to guess.
        if #matches == 1 then found = matches[1] end
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
