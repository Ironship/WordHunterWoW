-- Run from the addon root:  lua tests/text-lines.test.lua
--
-- The panel shows German and English side by side, one word frame at a time.
-- Both columns have to walk the quest the same way or they stop lining up, and
-- the German side used to run gmatch("%S+") over the whole text, which threw
-- away every line break in it. This checks the walk itself, without the layout.

strlower = string.lower
strtrim = function(s) return (tostring(s):gsub("^%s+", ""):gsub("%s+$", "")) end
CreateFrame = function() return setmetatable({}, {__index = function() return function() end end}) end
time = os.time
GetLocale = function() return "deDE" end

dofile("Core.lua")
local Addon = WordHunterWoW_Addon
assert(Addon and Addon.TextLines, "Core.lua does not provide TextLines")

local function shape(text)
  local out = {}
  for _, tokens in ipairs(Addon.TextLines(text)) do out[#out + 1] = #tokens end
  return table.concat(out, ",")
end

assert(shape("") == "0", "empty text should be one empty line, got " .. shape(""))
assert(shape("ein wort") == "2", "got " .. shape("ein wort"))

-- the case that was broken: a quest's story, a blank line, then its objectives
local quest = "Sprecht mit dem Botschafter.NLNLTrefft Euch in Sturmwind."
quest = quest:gsub("NL", "\n")
assert(shape(quest) == "4,0,4", "line breaks were lost: " .. shape(quest))
print("  paragraphs survive: " .. shape(quest))

-- and the words themselves are unchanged, in order
local flat = {}
for _, tokens in ipairs(Addon.TextLines(quest)) do
  for _, token in ipairs(tokens) do flat[#flat + 1] = token end
end
assert(table.concat(flat, " ") == "Sprecht mit dem Botschafter. Trefft Euch in Sturmwind.",
       "words changed: " .. table.concat(flat, " "))
print("  every word kept, in order")

-- trailing and repeated breaks must not invent or swallow lines
assert(shape("a" .. "\n") == "1", "got " .. shape("a" .. "\n"))
assert(shape("a" .. "\n" .. "\n" .. "\n" .. "b") == "1,0,0,1", "got " .. shape("a" .. "\n" .. "\n" .. "\n" .. "b"))
print("  repeated and trailing breaks counted exactly")

assert(shape(nil) == "0", "nil text must not raise")
print("  nil text handled")

print("text-lines: all assertions passed")
