-- Reproduce Forever's real startup error captured by !BugGrabber.
local function startup(supportsLegacyQuery, hasEventValidation)
  dofile('tests/wowstub.lua')
  C_EventUtils = hasEventValidation and {
    IsEventValid = function(event)
      return event ~= 'QUEST_QUERY_COMPLETE' or supportsLegacyQuery
    end,
  } or nil
  local create = CreateFrame
  local initFrame
  local registered = {}
  local rejected = 0
  CreateFrame = function(...)
    local frame = create(...)
    local register = frame.RegisterEvent
    frame.RegisterEvent = function(self, event)
      if event == 'QUEST_QUERY_COMPLETE' and not supportsLegacyQuery then
        rejected = rejected + 1
        error('Frame:RegisterEvent(): Frame:RegisterEvent(): Attempt to register unknown event "QUEST_QUERY_COMPLETE"')
      end
      registered[event] = true
      if event == 'QUEST_DETAIL' then initFrame = self end
      return register(self, event)
    end
    return frame
  end
  for line in io.lines('WordHunterWoW_Mainline.toc') do
    local file = line:match('^(%S+%.lua)%s*$')
    if file then
      local chunk = assert(loadfile(file))
      local ok, err = pcall(chunk, 'WordHunterWoW')
      assert(ok, 'unsupported legacy quest-query event must not abort addon startup: ' .. file .. ': ' .. tostring(err))
    end
  end
  local A = WordHunterWoW_Addon
  local onEvent = initFrame and initFrame:GetScript('OnEvent')
  assert(type(onEvent) == 'function', 'startup must install the event handler')
  local slash = SlashCmdList.WORDHUNTERWOW or SlashCmdList.WHW
  assert(type(slash) == 'function', 'startup must register /whw')
  onEvent(initFrame, 'ADDON_LOADED', 'WordHunterWoW')
  assert(A.panel and A.editor, 'the actual ADDON_LOADED route must initialize the reader and editor')
  slash('quests')
  assert(A.questsFrame and A.questsFrame:IsShown(), '/whw quests must work after initialization')
  for _, event in ipairs({'ADDON_LOADED', 'PLAYER_LOGIN', 'QUEST_DETAIL', 'QUEST_ACCEPTED', 'QUEST_LOG_UPDATE', 'GOSSIP_SHOW'}) do
    assert(registered[event], 'required event must still register: ' .. event)
  end
  if supportsLegacyQuery then
    assert(registered.QUEST_QUERY_COMPLETE, 'a legacy client must retain its completion-query subscription')
    onEvent(initFrame, 'QUEST_QUERY_COMPLETE')
    assert(rejected == 0)
  else
    assert(not registered.QUEST_QUERY_COMPLETE, 'unsupported optional event must not register')
    assert(rejected == (hasEventValidation and 0 or 1), 'validate supported events first; safely catch rejection only on clients without validation')
  end
end
startup(false, false)
startup(true, false)
startup(false, true)
startup(true, true)
print('quest startup: unsupported query event is safe; reader/editor/slash commands initialize; legacy subscription retained: ok')
