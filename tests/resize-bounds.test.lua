-- Run from the addon root:  lua tests/resize-bounds.test.lua
--
-- Retail replaced SetMinResize and SetMaxResize with a single SetResizeBounds.
-- The addon guarded the new call so it would not error on a client that lacks
-- it -- and then did nothing else, which left every window on Classic with no
-- size limits whatever. Dragged small enough a window vanishes, dragged large
-- enough it leaves the screen, and neither has a way back short of resetting
-- the layout. Guarding a call is not the same as handling its absence.

strlower = string.lower
strtrim = function(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
time = os.time
GetLocale = function() return "deDE" end

local made = {}
CreateFrame = function()
  local t = {}
  return setmetatable(t, { __index = function() return function() end end })
end

dofile("Core.lua")
local Addon = WordHunterWoW_Addon
assert(Addon.MakeResizable, "Core.lua should provide MakeResizable")

-- A window on either client: it records what it was asked, and only offers the
-- calls that client actually has. The catch-all below deliberately answers nil
-- for the three resize calls -- a stub that makes every method look present is
-- how the first version of this test managed to take the Retail path while
-- claiming to be Classic.
local RESIZE_API = { SetResizeBounds = true, SetMinResize = true, SetMaxResize = true }
local function window(modern)
  local f = { calls = {} }
  function f:SetResizable() self.calls.resizable = true end
  function f:HookScript() end
  function f:IsShown() return false end
  if modern then
    function f:SetResizeBounds(a, b, c, d) self.calls.bounds = { a, b, c, d } end
  else
    function f:SetMinResize(a, b) self.calls.min = { a, b } end
    function f:SetMaxResize(a, b) self.calls.max = { a, b } end
  end
  return setmetatable(f, {
    __index = function(_, key)
      if RESIZE_API[key] then return nil end
      return function() end
    end,
  })
end

-- Retail: one call, unchanged.
local retail = window(true)
Addon.MakeResizable(retail, "panel", 300, 200, 900, 700)
assert(retail.calls.resizable, "the window has to be resizable at all")
assert(retail.calls.bounds, "Retail should still use SetResizeBounds")
assert(table.concat(retail.calls.bounds, ",") == "300,200,900,700",
  "and pass the same four numbers through")

-- Classic: the two calls it replaced, with the same numbers split across them.
local classic = window(false)
Addon.MakeResizable(classic, "panel", 300, 200, 900, 700)
assert(classic.calls.resizable, "the window has to be resizable there too")
assert(classic.calls.min, "Classic has no SetResizeBounds, so the minimum must come from SetMinResize")
assert(classic.calls.max, "and the maximum from SetMaxResize")
assert(table.concat(classic.calls.min, ",") == "300,200", "minimum width and height")
assert(table.concat(classic.calls.max, ",") == "900,700", "maximum width and height")

-- A client with neither must still not error: no limits is bad, but a window
-- that never appears because the addon threw while building it is worse.
local bare = setmetatable({ SetResizable = function() end, HookScript = function() end },
  { __index = function(_, key)
      if RESIZE_API[key] then return nil end
      return function() end
    end })
local ok = pcall(Addon.MakeResizable, bare, "panel", 300, 200, 900, 700)
assert(ok, "a client with neither call must not take the addon down")

print("resize-bounds: ok")
