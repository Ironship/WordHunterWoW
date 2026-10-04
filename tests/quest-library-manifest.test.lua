-- New library modules must really load in both supported manifests.
for _, path in ipairs({ 'WordHunterWoW_Mainline.toc', 'WordHunterWoW_Vanilla.toc' }) do
  local order, count = {}, 0
  for line in io.lines(path) do
    local file = line:match('^(%S+%.lua)%s*$')
    if file then count = count + 1 order[file] = count end
  end
  assert(order['QuestHistory.lua'], path .. ' must load per-character quest history')
  assert(order['QuestReader.lua'], path .. ' must load the real database reader')
  assert(order['QuestHistory.lua'] > order['Compat.lua'] and order['QuestHistory.lua'] > order['Harvest.lua'], 'history requires identity and compatibility helpers')
  assert(order['QuestReader.lua'] > order['QuestPanel.lua'] and order['QuestReader.lua'] < order['Init.lua'], 'reader must load before quest events and slash commands')
end
print('quest-library-manifest: both clients load reader and history: ok')
