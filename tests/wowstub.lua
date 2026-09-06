-- Enough of the game's globals to load the addon's UI files outside it.
--
-- Frames answer to anything, and make a child frame for any field they are
-- asked for, so layout code runs unchanged. Four things are modelled rather
-- than waved through, because tests turn on them: whether a frame is shown, how
-- big it is, where it is anchored, and that a frame's font strings are separate
-- objects from one another.
--
-- The rest of this file is about where the manufacturing stops. Anything it
-- invents is something a test cannot then find missing, so it invents only what
-- the client itself creates -- a named frame and its template's children -- and
-- refuses everything else: the addon's own namespace, the saved variables, the
-- optional companion addon's data, and its own private bookkeeping.
-- tests/wowstub.test.lua holds that line.

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
  -- A test that wants to read a whole pane cannot walk the pane's children:
  -- indexing a stub node manufactures another node for any key, so ipairs over
  -- one never ends. Setting CAPTURE_TEXT to a table records every string the
  -- addon writes, in order, until the test clears it again.
  function t:SetText(v)
    self._text = v
    if CAPTURE_TEXT then CAPTURE_TEXT[#CAPTURE_TEXT + 1] = tostring(v or "") end
  end
  function t:GetText() return self._text end
  function t:SetSize(w, h) self.w, self.h = w, h end
  function t:SetWidth(w) self.w = w end
  function t:SetHeight(h) self.h = h end
  -- rawget, because the __index below manufactures a node for any key it has
  -- not seen. Read plainly, the first GetWidth on a frame that was anchored
  -- rather than sized -- every scroll frame in this panel -- fabricated a table,
  -- stored it under "w", and returned it; the "or 430" never ran, and from then
  -- on the frame answered its width with a table forever. Nothing failed:
  -- comparing a width against a table is an error only if something compares
  -- them, so a test that measured such a frame quietly measured nothing.
  function t:GetWidth()
    local w = rawget(self, "w")
    return type(w) == "number" and w or 430
  end
  function t:GetHeight()
    local h = rawget(self, "h")
    return type(h) == "number" and h or 240
  end
  function t:GetSize() return self:GetWidth(), self:GetHeight() end
  -- Measurements have to be numbers, and text has to get wider as the font
  -- grows -- otherwise a test cannot tell whether a size change reached the
  -- layout at all.
  -- LAST_FONT_SIZE lets a test see the size the addon actually asked for,
  -- without having to reach into pooled frames it does not own.
  function t:SetFont(_, size) self._fontSize = size LAST_FONT_SIZE = size end
  function t:GetFontSize() return self._fontSize end
  -- Width follows the font and the string, not the font alone. Every string
  -- being the same width made the four legend labels the same width, so a
  -- layout that steps past a label by a flat amount and one that measures it
  -- came out identical here -- and the flat one collides on screen the moment
  -- the letters grow. 0.55em a character is close enough to the game's default
  -- face that an ordinary word still measures about the 40px this used to say.
  function t:GetStringWidth()
    local text = tostring(self._text or "")
    return math.max(1, #text) * (self._fontSize or 12) * 0.55
  end
  function t:GetStringHeight() return 10 end
  function t:GetNumPoints() return 0 end
  -- Where the frame was last anchored, kept under a private name and read back
  -- through GetAnchor rather than through GetPoint. GetPoint is what
  -- SaveFramePosition calls, and answering it here would start writing these
  -- numbers into the saved layout -- which is not what any of this measures.
  -- Only the offsets are kept: a test asking whether a heading pushed the text
  -- below it down wants the y, and has no other way to see it.
  function t:SetPoint(point, a, b, c, d)
    local x, y
    if type(c) == "number" and type(d) == "number" then
      x, y = c, d
    elseif type(a) == "number" and type(b) == "number" then
      x, y = a, b
    end
    self._points = self._points or {}
    self._points[point] = { x = x, y = y }
  end
  -- Draw order. Modelled because two frames of this addon are deliberately
  -- ordered against each other -- the quest log's button has to stay above the
  -- panel it opens -- and without these the calls would be answered by the
  -- fabricating __index below, so a test comparing two strata would compare two
  -- manufactured tables and pass whatever the addon did.
  --
  -- A level is inherited from the parent, one step up, exactly as the client
  -- does it; an explicit SetFrameLevel wins over that.
  -- Scale, which is the mechanism half this addon's windows grow by. It was not
  -- modelled at all, so SetScale was answered by the fabricating __index and
  -- GetScale handed back a table -- meaning no test could tell a window that
  -- scales from one that does not, which is exactly the fault being fixed.
  -- Multiplied down the parent chain as the client does it.
  function t:SetScale(value) rawset(self, "_scale", value) end
  function t:GetScale() return rawget(self, "_scale") or 1 end
  function t:GetEffectiveScale()
    local up = rawget(self, "_parent")
    return self:GetScale() * (up and up:GetEffectiveScale() or 1)
  end
  function t:SetFrameStrata(value) rawset(self, "_strata", value) end
  function t:GetFrameStrata()
    local own = rawget(self, "_strata")
    if own then return own end
    local up = rawget(self, "_parent")
    return up and up:GetFrameStrata() or "MEDIUM"
  end
  function t:SetFrameLevel(value) rawset(self, "_level", value) end
  function t:GetFrameLevel()
    local own = rawget(self, "_level")
    if own then return own end
    local up = rawget(self, "_parent")
    return up and (up:GetFrameLevel() + 1) or 0
  end
  function t:SetToplevel() end
  function t:SetAllPoints() end
  function t:ClearAllPoints() self._points = {} end
  function t:GetAnchor(point)
    local p = self._points and self._points[point]
    if not p then return nil, nil end
    return p.x, p.y
  end
  -- A frame's font strings and textures are separate objects in the game, and
  -- the panel's title, progress line and legend are all font strings on the one
  -- frame. Manufacturing them through __index handed out the same node for
  -- every call, so a test could not tell the title from the line under it --
  -- and a change that re-fonted only one of them would have passed.
  function t:CreateFontString() return node() end
  function t:CreateTexture() return node() end
  return setmetatable(t, {
    -- Never for the underscored names above. Those are this file's own
    -- bookkeeping, not children of the frame, and manufacturing them is the
    -- same mistake GetWidth used to make: GetText on a font string nothing had
    -- written to answered with a table rather than nil, and a test that read
    -- back what the UI displayed got something truthy whatever the UI did. No
    -- production file reads a field beginning with an underscore off a frame,
    -- so the rule costs nothing.
    __index = function(self, key)
      if type(key) == "string" and key:sub(1, 1) == "_" then return nil end
      local made = node()
      rawset(self, key, made)
      return made
    end,
    __call = function(self) return self end,
  })
end

-- Frames the addon names, and looks up again through _G. The real client
-- creates a global for a named frame and for its template's children, so a
-- stub that does not answer those lookups fails on code that is perfectly fine.
local created = 0
local namedFrames = {}
CreateFrame = function(_, name, parent)
  local f = node()
  created = created + 1
  local given = name or ("Stub" .. created)
  function f:GetName() return given end
  -- Kept so a level and a strata can be inherited the way the client does it.
  -- The third argument was being dropped, which made every frame a root: two
  -- frames deliberately ordered against each other both answered from the same
  -- default, and the comparison said nothing.
  if type(parent) == "table" then rawset(f, "_parent", parent) end
  function f:SetParent(other)
    if type(other) == "table" then rawset(self, "_parent", other) end
  end
  function f:GetParent() return rawget(self, "_parent") end
  if name then
    _G[name] = f
    namedFrames[name] = true
  end
  return f
end

-- Globals that are data, not frames, and that the client therefore never
-- invents: the addon's own namespace, the five saved variables both .toc files
-- declare, and the quest text the separate ENPanel addon publishes. Naming them
-- is redundant with the rule below -- none of them extends a frame name today --
-- but the rule is only as good as the frame names it is handed, and the day
-- someone names a frame WordHunterWoWCorpus the hole reopens silently. This
-- list is the statement of intent; the rule is the mechanism.
local NEVER_A_FRAME = {
  WordHunterWoW_Addon = true,
  WordHunterWoWDB = true,
  WordHunterWoWExport = true,
  WordHunterWoWLanguage = true,
  WordHunterWoWCorpus = true,
  WordHunterWoWCorpusExport = true,
  WordHunterWoW_QuestEN = true,
}

setmetatable(_G, {
  __index = function(_, key)
    if type(key) ~= "string" or NEVER_A_FRAME[key] then return nil end
    -- Only the children a template hangs off a frame that already exists --
    -- $parentText, $parentLow, $parentHigh -- which is the whole of what the
    -- client actually creates behind the addon's back. Fabricating for any name
    -- beginning "WordHunterWoW" caught those, and caught WordHunterWoW_Addon
    -- with them: Core.lua reads that global before it assigns it, so the addon
    -- namespace was itself a fabricating node and every field read off it came
    -- back a fresh table. In every test that loads this file,
    -- assert(Addon.AnythingAtAll) passed for symbols that had been deleted --
    -- the deletion was still caught further down, but by an assertion about
    -- something else, or by a raw index error inside QuestPanel. Matching
    -- against the frames CreateFrame was actually given a name for is narrow
    -- enough that a missing symbol is missing, and wide enough that
    -- Settings.lua's sliders still find their captions.
    for name in pairs(namedFrames) do
      if #key > #name and key:sub(1, #name) == name then
        local made = node()
        function made:GetName() return key end
        rawset(_G, key, made)
        return made
      end
    end
    return nil
  end,
})
-- The game's font objects, at the sizes the client really gives them. They are
-- not all one size: the panel's chrome draws from three of these and its words
-- from a fourth, and a stub that made them equal would hide the one thing the
-- split is about -- that two surfaces at the same setting are not the same size
-- on screen.
local function fontObject(size)
  return { GetFont = function() return "FRIZQT__.TTF", size, "" end }
end
GameFontHighlight = fontObject(12)
GameFontNormal = fontObject(12)
GameFontNormalLarge = fontObject(16)
GameFontNormalSmall = fontObject(10)
GameFontDisableSmall = fontObject(10)
-- The two the addon uses that were missing here. Absent, they were answered by
-- the fabricating __index above, so a test that measured a window drawing from
-- one of them measured a manufactured table. ChatFontNormal is the odd one: it
-- is the size the player set for their CHAT window, so 14 is a default rather
-- than a fixed fact, and a surface drawing from it is not the same size as its
-- neighbours at any setting.
GameFontHighlightSmall = fontObject(10)
ChatFontNormal = fontObject(14)

-- The quest windows. Whether they are open decides whether the panel opens.
QuestFrame, QuestMapFrame, WorldMapFrame = node(), node(), node()
GetQuestID = function() return 184 end
GetTitleText = function() return "Sten Stoutarm" end
GetQuestText = function() return "Was haben wir denn hier?" end
GetObjectiveText = function() return "Bringt 8 Stücke zähes Wolfsfleisch." end
GetProgressText = function() return "" end
GetRewardText = function() return "" end

return node
