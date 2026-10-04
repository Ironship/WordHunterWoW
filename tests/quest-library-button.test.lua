-- Run from the addon root:  lua tests/quest-library-button.test.lua
--
-- The quest library's side tab opens /whw quests from the
-- main quest-log LIST, even with no quest selected. The reader's own button
-- hangs on the details pane (Retail) or the Classic window and needs a
-- selected quest; the library is a list of quests and must be reachable from
-- the list itself.
--
-- Three homes, one rule -- probe the frames, never the flavour: Retail keeps
-- the list at QuestMapFrame.QuestsFrame, Forever hosts the same map list
-- while answering Classic to every flavour question, and standalone Classic
-- keeps its own QuestLogFrame window. Checked through a host chooser rather
-- than by attaching three times, because the button is built once per session
-- (the reader's test does the same for the same reason).
--
-- Frame fields are read with rawget throughout: the stub manufactures any
-- field a test merely looks at, so looking at QuestMapFrame.QuestsFrame to ask
-- whether it exists creates it and the answer is always yes.

local node = dofile("tests/wowstub.lua")
UIParent = node()

dofile("Core.lua")
dofile("Compat.lua")
dofile("UICommon.lua")
dofile("QuestPanel.lua")
dofile("QuestBrowser.lua")
local Addon = WordHunterWoW_Addon

WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, words = {}, wordsByLocale = {} }
Addon.initializeDatabase()
Addon.createPanel()

local function setRetail()
  WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
  GetBuildInfo = function() return "12.1.0", "69814", "2026-09-01", 120100 end
  C_AddOns, GetAddOnMetadata, C_Seasons, Enum = nil, nil, nil, nil
  Addon.Compat.Refresh()
end

local function setForever()
  WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
  GetBuildInfo = function() return "1.60.1", "69893", "2026-09-01", nil end
  C_AddOns, GetAddOnMetadata, C_Seasons, Enum = nil, nil, nil, nil
  Addon.Compat.Refresh()
end

local function setClassic()
  WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 2, 1
  GetBuildInfo = function() return "1.15.9", "62222", "2026-09-01", 11509 end
  C_AddOns, GetAddOnMetadata, C_Seasons, Enum = nil, nil, nil, nil
  Addon.Compat.Refresh()
end

-- No quest selected anywhere: the library must not need one.
QuestMapFrame_GetDetailQuestID = function() return nil end
GetQuestLogSelection = nil
C_QuestLog = nil

assert(Addon.QuestsLogButtonHost, "the library button needs its own list host chooser")
local listHost = Addon.QuestsLogButtonHost

-- Before any log exists at all, which is every login: both Blizzard addons are
-- load-on-demand. Nothing to hang the button on is a reason to come back
-- later, not an error and not a button hung on nothing.
setRetail()
QuestMapFrame = node()
rawset(QuestMapFrame, "QuestsFrame", nil)
rawset(QuestMapFrame, "DetailsFrame", nil)
QuestLogFrame = nil
assert(rawget(QuestMapFrame, "QuestsFrame") == nil, "the setup must really lack a list, not a fabricated one")
assert(listHost() == nil, "no quest list yet means no library host")
assert(Addon.AttachQuestsLogButton() == nil, "and no library button until there is one")
assert(Addon.questsLogButton == nil, "attaching with no host must not leave a button behind")

-- Retail: the list, not the reader's details pane. The details pane only
-- exists while a quest is picked; hung there, the library would vanish exactly
-- when the player is browsing the list with nothing selected.
local mapList = node()
local details = node()
rawset(QuestMapFrame, "QuestsFrame", mapList)
rawset(QuestMapFrame, "DetailsFrame", details)
QuestLogFrame = nil
assert(Addon.QuestLogButtonHost() == details, "the test setup really has the reader on the details pane")
assert(listHost() == mapList, "on Retail the library belongs on the quest list")
assert(listHost() ~= details, "never on the details pane, which needs a selected quest")

-- Forever: the same map-hosted list, while the flavour answers Classic.
-- Forever is a Classic-line game (IsClassic is true there by design); asking
-- the flavour would send the button to QuestLogFrame, a window Forever does
-- not have.
setForever()
assert(Addon.Compat.IsClassic(), "Forever takes the Classic paths, which is what makes this case sharp")
assert(Addon.Compat.GameFlavor() == "forever", "and it is still its own game")
assert(listHost() == mapList, "on Forever the library belongs on the map list despite the Classic flavour")

-- Standalone Classic: its own window, with no map list lying about.
setClassic()
assert(Addon.Compat.IsClassic() and Addon.Compat.GameFlavor() == "classic", "really Classic now")
rawset(QuestMapFrame, "QuestsFrame", nil)
rawset(QuestMapFrame, "DetailsFrame", nil)
QuestLogFrame = node()
assert(listHost() == QuestLogFrame, "on Classic the library belongs on the quest log window")
QuestLogFrame = nil
assert(listHost() == nil, "Classic before its load-on-demand log arrives means no host")

-- Back to Retail for the one attach this session builds.
setRetail()
rawset(QuestMapFrame, "QuestsFrame", mapList)
rawset(QuestMapFrame, "DetailsFrame", details)
QuestLogFrame = nil

-- hookQuestUi is called at every moment the log could have arrived, so that is
-- where the button has to be put up -- including for a log that arrives late,
-- which the nil attach above already simulated.
Addon.hookQuestUi()
local book = Addon.questsLogButton
assert(book, "hookQuestUi should have put the library button on the quest list")
assert(book:GetParent() == UIParent, "the tab must escape clipping inside the quest list")
assert(Addon.AttachQuestsLogButton() == book, "attaching again must not build a second button")
Addon.hookQuestUi()
assert(Addon.questsLogButton == book, "a late second hook must not build a second button either")
assert(book:GetObjectType() == "CheckButton", "without the modern template the library uses a Classic side tab")

-- Its own anchor on its own host: the reader's button lives on the details
-- pane here, so stacking below it would pin the book to another window.
local ax = book:GetAnchor("TOPLEFT")
assert(ax == 2, "the tab sits outside the outer window, got x " .. tostring(ax))

-- Pressing it opens /whw quests with nothing selected -- the whole point of
-- hanging it on the list rather than the details pane.
assert(Addon.toggleQuestBrowser, "the library opens through the same toggle as /whw quests")
if Addon.questsFrame then Addon.questsFrame:Hide() end
local click = book:GetScript("OnClick")
assert(click, "the book does nothing without an OnClick")
click(book)
assert(Addon.questsFrame and Addon.questsFrame:IsShown(), "the book must open the quest browser with no quest selected")
click(book)
assert(not Addon.questsFrame:IsShown(), "a second press closes it again, like /whw quests")
assert(not Addon.panel:IsShown(), "the book opens the library, never the reader panel")

-- And it stays clickable above this addon's own windows: the panel opens
-- right beside the log and the browser is a window of its own, and the one
-- control whose job is to toggle the browser has to stay reachable while
-- either is up. The reading dimmer is FULLSCREEN, below FULLSCREEN_DIALOG.
Addon.panel:Show()
Addon.toggleQuestBrowser()
assert(Addon.questsFrame:IsShown(), "the browser is up for the draw-order check")
assert(book:GetFrameStrata() == "FULLSCREEN_DIALOG", "the book lives in FULLSCREEN_DIALOG, above the dimmer")
assert(book:GetFrameLevel() > Addon.panel:GetFrameLevel(),
  "the book draws at level " .. book:GetFrameLevel()
  .. ", under the panel at " .. Addon.panel:GetFrameLevel())
assert(book:GetFrameLevel() > Addon.questsFrame:GetFrameLevel(),
  "the book draws at level " .. book:GetFrameLevel()
  .. ", under the browser at " .. Addon.questsFrame:GetFrameLevel())
click(book)
assert(not Addon.questsFrame:IsShown(), "the book still toggles with the panel and browser up")
Addon.panel:Hide()

print("quest-library-button: ok")
