-- Run from the addon root:  lua tests/forever-flavour.test.lua
--
-- World of Warcraft: Forever is a Classic-line game on a client built from
-- Retail's code, and asked the usual questions it gives Retail's answers:
-- GetBuildInfo returns a Retail-family interface, and WOW_PROJECT_ID equals
-- WOW_PROJECT_MAINLINE. Every branch in projectFamily therefore reached RETAIL.
--
-- That was not a theory. On 2026-09-18 the Forever client wrote an export of
-- thirteen passages -- its own quests 92461-92463, Thendalhain -- every row
-- stamped "retail", and they were merged into the Retail corpus beside
-- Blizzard's before anyone noticed. import_harvest's own comment says why that
-- must not happen: the same quest id is different text on a different game.
--
-- So the recognition comes from this addon's own manifest rather than from the
-- client. Each case below is run in a state where it should hold and in one
-- where it should not.

strlower = string.lower
strtrim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
CreateFrame = function() return setmetatable({}, {__index = function() return function() end end}) end
time = os.time
GetLocale = function() return "deDE" end

dofile("Core.lua")
-- Loaded with the addon name a real client passes, which is where Compat reads
-- its own manifest from.
assert(loadfile("Compat.lua"))("WordHunterWoW")
local Addon = WordHunterWoW_Addon
local Compat = Addon.Compat

-- The client Forever actually is: Retail's globals, and a version of its own.
-- Measured on 2026-09-19 with /whw diag: WOW_PROJECT_ID is Retail's, the
-- interface number GetBuildInfo returns is nil, and the build is 1.60.x.
local function onForeverClient()
  GetBuildInfo = function() return "1.60.1", "69893", "2026-09-01", nil end
  WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
  C_Seasons, Enum = nil, nil
end

-- A Retail client proper, for the cases that must not read as Forever.
local function onRetailClient()
  GetBuildInfo = function() return "12.1.0", "69814", "2026-09-01", 120100 end
  WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 1, 1
  C_Seasons, Enum = nil, nil
end

-- The manifest the Forever bundle actually ships: one file, every interface.
local BUNDLE_LIST = "11509, 16001, 20506, 30405, 40402, 50504, 120100"

local function manifest(interface)
  C_AddOns = { GetAddOnMetadata = function(name, field)
    assert(name == "WordHunterWoW", "asked about the wrong addon: " .. tostring(name))
    return field == "Interface" and interface or nil
  end }
  GetAddOnMetadata = nil
end

-- --- the fault this exists for ----------------------------------------------
onForeverClient()
manifest("16001")
Compat.Refresh()
assert(Compat.GameFlavor() == "forever",
  "the Forever build must know its own game, got " .. Compat.GameFlavor())
assert(Compat.IsForever(), "IsForever has to agree")
assert(not Compat.IsRetail(), "and it is certainly not Retail")

-- The bundle's list manifest on the Forever client: the list is not a number,
-- and on 2026-09-19 that read as Retail in the game. The version decides.
manifest(BUNDLE_LIST)
Compat.Refresh()
assert(Compat.GameFlavor() == "forever",
  "the bundle on the Forever client must read as Forever, got " .. Compat.GameFlavor())

-- The same list manifest on a Retail client: Retail. A list decides nothing.
onRetailClient()
manifest(BUNDLE_LIST)
Compat.Refresh()
assert(Compat.GameFlavor() == "retail",
  "a list manifest on Retail is still Retail, got " .. Compat.GameFlavor())

-- The repository's own Mainline manifest names Forever too, so the CurseForge
-- and GitHub builds load there: the client version still decides each game.
local MAINLINE_LIST = io.open("WordHunterWoW_Mainline.toc"):read("*l"):match("^## Interface:%s*(.-)%s*$")
assert(MAINLINE_LIST:find("16001", 1, true), "the Mainline manifest has to list Forever's 16001")
manifest(MAINLINE_LIST)
Compat.Refresh()
assert(Compat.GameFlavor() == "retail", "the Mainline list on Retail must read as Retail")
onForeverClient()
manifest(MAINLINE_LIST)
Compat.Refresh()
assert(Compat.GameFlavor() == "forever", "the Mainline list on Forever must read as Forever")
onRetailClient()

-- Classic Era is 1.15.x: a 1.x version alone is not Forever.
GetBuildInfo = function() return "1.15.9", "62222", "2026-09-01", 11509 end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 2, 1
manifest(BUNDLE_LIST)
Compat.Refresh()
assert(Compat.GameFlavor() == "classic",
  "Classic Era 1.15 must not read as Forever, got " .. Compat.GameFlavor())

-- The Retail client, the Retail build of the addon: Retail, as it always was.
onRetailClient()
manifest("120100")
Compat.Refresh()
assert(Compat.GameFlavor() == "retail",
  "the Retail build on this client is still Retail, got " .. Compat.GameFlavor())

-- --- Forever is a Classic-line game -----------------------------------------
-- Not a fourth branch through the addon: it wants the Classic quest log calls,
-- the Classic frame names and the Classic defaults. Only the corpus differs.
manifest("16001")
Compat.Refresh()
assert(Compat.IsClassic(), "Forever has to take the Classic paths")
assert(not Compat.IsSeasonOfDiscovery(), "and it is not Season of Discovery")

-- A client that answers for a season must not turn Forever into SoD. Filing a
-- Forever corpus under sod is the same mistake as filing it under retail, one
-- folder further along.
Enum = { SeasonID = { SeasonOfDiscovery = 2 } }
C_Seasons = { GetActiveSeason = function() return 2 end }
Compat.Refresh()
assert(Compat.GameFlavor() == "forever",
  "a season reading must not override Forever, got " .. Compat.GameFlavor())
C_Seasons, Enum = nil, nil

-- --- the other games are untouched ------------------------------------------
manifest("11509")
GetBuildInfo = function() return "1.15.9", "60000", "2026-01-01", 11509 end
WOW_PROJECT_ID, WOW_PROJECT_MAINLINE = 2, 1
Compat.Refresh()
assert(Compat.GameFlavor() == "classic", "Classic Era is still Classic, got " .. Compat.GameFlavor())

Enum = { SeasonID = { SeasonOfDiscovery = 2 } }
C_Seasons = { GetActiveSeason = function() return 2 end }
Compat.Refresh()
assert(Compat.GameFlavor() == "sod", "Season of Discovery still resolves, got " .. Compat.GameFlavor())
C_Seasons, Enum = nil, nil

-- --- a client with no manifest API at all ------------------------------------
-- The oldest clients this addon claims to support have neither C_AddOns nor the
-- global, and a missing manifest has to read as "not Forever" rather than as an
-- error while the TOC is still running.
onRetailClient()
C_AddOns, GetAddOnMetadata = nil, nil
Compat.Refresh()
assert(Compat.GameFlavor() == "retail",
  "with no way to read the manifest the old answer must stand, got " .. Compat.GameFlavor())

-- The Forever client with no manifest API: its version is enough on its own,
-- and the missing reader is not an error.
onForeverClient()
C_AddOns, GetAddOnMetadata = nil, nil
Compat.Refresh()
assert(Compat.GameFlavor() == "forever",
  "the version says Forever even with no manifest to read, got " .. Compat.GameFlavor())

-- And one that has only the old global form.
GetAddOnMetadata = function(_, field) return field == "Interface" and "16001" or nil end
Compat.Refresh()
assert(Compat.GameFlavor() == "forever",
  "the pre-C_AddOns global has to work too, got " .. Compat.GameFlavor())

-- A manifest call that throws must not take the addon down with it -- on
-- either client. On Retail the old answer stands; on Forever the version
-- still answers.
onRetailClient()
GetAddOnMetadata = function() error("no such addon") end
Compat.Refresh()
assert(Compat.GameFlavor() == "retail",
  "a throwing manifest call has to be survivable, got " .. Compat.GameFlavor())
onForeverClient()
Compat.Refresh()
assert(Compat.GameFlavor() == "forever",
  "and on Forever it still answers by version, got " .. Compat.GameFlavor())

print("forever-flavour: ok")
