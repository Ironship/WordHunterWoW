-- Run from the addon root:  lua tests/resize-grip.test.lua
--
-- Dragging the corner made the window jump between sizes and swallow clicks.
--
-- StartSizing makes the corner follow the cursor, but the corner stops at the
-- size bounds and at the edge of the screen while the cursor keeps going. So on
-- most real drags the cursor finishes somewhere off the 16px grip. OnMouseUp is
-- only ever delivered to the button the cursor is over, so releasing away from
-- the grip never reached StopMovingOrSizing, and the frame stayed in sizing
-- mode: still following the cursor with no button held.
--
-- That is what this models. The frame tracks whether it is sizing, and the
-- release is delivered the way the game delivers it -- to the grip only when
-- the cursor is still on it.

local sizing = {}

local function frame()
  local f = { scripts = {}, shown = true }
  function f:SetScript(name, fn) self.scripts[name] = fn end
  function f:HookScript(name, fn)
    local prev = self.scripts[name]
    self.scripts[name] = function(...) if prev then prev(...) end fn(...) end
  end
  function f:StartSizing() sizing[self] = true end
  function f:StopMovingOrSizing() sizing[self] = false end
  function f:IsShown() return self.shown end
  function f:Hide() self.shown = false if self.scripts.OnHide then self.scripts.OnHide(self) end end
  function f:GetPoint() return "CENTER", nil, "CENTER", 0, 0 end
  function f:GetSize() return 500, 300 end
  -- Everything else is a method that does nothing -- except the fields the
  -- addon checks for presence. A catch-all that answered those would make
  -- MakeResizable think the grip already existed and skip building it.
  local DATA = { resizeHandle = true }
  return setmetatable(f, { __index = function(_, key)
    if DATA[key] then return nil end
    return function() end
  end })
end

strlower = string.lower
strtrim = function(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
time = os.time
GetLocale = function() return "deDE" end
local handles = {}
CreateFrame = function()
  local f = frame()
  handles[#handles + 1] = f
  return f
end

dofile("Core.lua")
local Addon = WordHunterWoW_Addon
WordHunterWoWDB = { settings = { targetLocale = "deDE", frames = {} }, words = {}, wordsByLocale = {} }
Addon.initializeDatabase()

local window = frame()
Addon.MakeResizable(window, "panel", 400, 230, 1200, 800)
local grip = window.resizeHandle
assert(grip, "MakeResizable should give the frame a grip")

-- A drag that ends with the cursor off the grip. This is the ordinary case, not
-- an edge case: it happens the moment the window stops following the cursor.
grip.scripts.OnDragStart(grip)
assert(sizing[window], "dragging the grip should start sizing")
grip.scripts.OnDragStop(grip)
assert(sizing[window] == false,
  "releasing away from the grip must still stop sizing, or the window keeps " ..
  "following the cursor with the button up")

-- The size is kept at the end of the drag, not left to whatever happens next.
local saved = WordHunterWoWDB.settings.frames[Addon.LayoutKey("panel")]
assert(saved and saved.w == 500 and saved.h == 300, "the new size should be saved on release")

-- A press and release with no movement in between: no drag ever starts, and
-- nothing should be left running.
WordHunterWoWDB.settings.frames = {}
grip.scripts.OnMouseUp(grip)
assert(sizing[window] == false, "a plain click on the grip must not leave sizing on")

-- Hidden mid-drag -- Escape, or the quest window closing underneath. Without
-- this the frame is still sizing when it is next shown.
grip.scripts.OnDragStart(grip)
assert(sizing[window])
window:Hide()
assert(sizing[window] == false, "hiding the window mid-drag must stop sizing")

-- Called twice, the frame must not end up with the size handler stacked: every
-- change would then be saved twice, and any future handler would run twice.
local before = window.scripts.OnSizeChanged
Addon.MakeResizable(window, "panel", 400, 230, 1200, 800)
assert(window.scripts.OnSizeChanged == before, "MakeResizable must not re-hook a frame it already set up")

-- Finishing a drag has to record that the size is the player's own. Nothing
-- else can tell afterwards: the frame has a saved size whether it was dragged,
-- merely moved, or sized by the addon to fit its contents.
WordHunterWoWDB.settings.frames = {}
grip.scripts.OnDragStart(grip)
grip.scripts.OnDragStop(grip)
local entry = WordHunterWoWDB.settings.frames[Addon.LayoutKey("panel")]
assert(entry and entry.userSized, "a finished drag should mark the size as the player's")

-- And it has to survive everything that writes the entry afterwards -- moving
-- the window is the common one, and it used to replace the whole record.
Addon.SaveFramePosition(window, Addon.LayoutKey("panel"))
assert(WordHunterWoWDB.settings.frames[Addon.LayoutKey("panel")].userSized,
  "moving the window must not undo the size the player chose")

-- A press and release that never became a drag is not a choice of size.
WordHunterWoWDB.settings.frames = {}
grip.scripts.OnMouseUp(grip)
local clicked = WordHunterWoWDB.settings.frames[Addon.LayoutKey("panel")]
assert(clicked and not clicked.userSized, "a click that never dragged is not a size the player picked")

print("resize-grip: ok")
