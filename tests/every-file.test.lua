-- Run from the addon root:  lua tests/every-file.test.lua
--
-- Load the ten files the .toc names, in the order it names them, and run the
-- surfaces the rest of the suite never reaches.
--
-- Two of the ten could not be loaded here at all until now. Init.lua indexes
-- SlashCmdList at file scope and the stub had no such table, and Settings.lua
-- calls UIDropDownMenu_SetWidth, which the fabricating __index used to answer
-- with a manufactured node. So the file that decides what happens on
-- ADDON_LOADED and on every quest event, and the whole /whw command tree, were
-- executed by nothing. The one test that names Init.lua opens it and greps the
-- text, which catches a renamed function and not a nil-global typo.
--
-- This is the hole the wowstub repair was for, left open in the two files it
-- would matter most in.

local node = dofile("tests/wowstub.lua")

local TOC = {}
for line in io.lines("WordHunterWoW_Mainline.toc") do
  local file = line:match("^(%S+%.lua)%s*$")
  if file then TOC[#TOC + 1] = file end
end
assert(#TOC == 10, "the manifest names " .. #TOC .. " lua files, expected 10")

-- Loaded from the manifest rather than from a list written here. A list would
-- be a second answer to "what does this addon load", and the two drift.
for _, file in ipairs(TOC) do
  local chunk, err = loadfile(file)
  assert(chunk, "the manifest names " .. file .. " but it will not load: " .. tostring(err))
  local ok, runErr = pcall(chunk, "WordHunterWoW")
  assert(ok, file .. " raised while loading: " .. tostring(runErr))
end
print("  every file the manifest names loads, in the order it names them")

local Addon = WordHunterWoW_Addon
WordHunterWoWDB = nil
Addon.initializeDatabase()
Addon.createPanel()
Addon.createEditor()

-- The slash commands, which is the surface a player reaches when nothing is on
-- screen. Driven through SlashCmdList exactly as the client does it.
local run = SlashCmdList["WORDHUNTERWOW"] or SlashCmdList["WHW"]
assert(run, "Init.lua registered no slash handler under any name this test knows")
local said = {}
local realPrint = print
print = function(...) said[#said + 1] = table.concat({ ... }, " ") end
local commands = {
  "", "settings", "words", "stats", "reset", "bg", "opacity",
  "lang", "harvest", "harvest on", "harvest off", "harvest clear", "export",
}
for _, command in ipairs(commands) do
  local ok, err = pcall(run, command)
  print = realPrint
  assert(ok, "/whw " .. command .. " raised: " .. tostring(err))
  print = function(...) said[#said + 1] = table.concat({ ... }, " ") end
end
print = realPrint
print("  every /whw command runs on a fresh profile without raising")

-- Stats.lua, which no other test loads. Its arithmetic is checked elsewhere;
-- what is checked here is that opening it on an empty profile does not raise,
-- which is the first thing a new player who types /whw stats will do.
assert(Addon.toggleStats, "Stats.lua defined no toggleStats")
local ok, err = pcall(Addon.toggleStats)
assert(ok, "opening the statistics window on an empty profile raised: " .. tostring(err))
pcall(Addon.toggleStats)
print("  the statistics window opens and closes on an empty profile")

print("every-file: ok")
