--[[
	IndexUtil — pure math for the Collection Index (the "dex").

	Shared because both sides need it: the SERVER computes the permanent
	set-completion bonuses that feed into income/luck, and the CLIENT
	renders completion % and which sets are done. No state lives here —
	everything derives from the saved `Discovered` table ({[species]=true}).
]]

local GameConfig = require(script.Parent.GameConfig)

local IndexUtil = {}

-- All species of one rarity (roster order preserved)
local speciesByRarity: { [string]: { string } } = {}
for _, animal in GameConfig.Animals do
	speciesByRarity[animal.Rarity] = speciesByRarity[animal.Rarity] or {}
	table.insert(speciesByRarity[animal.Rarity], animal.Name)
end

function IndexUtil.discoveredCount(discovered: { [string]: boolean }): number
	local count = 0
	for _, animal in GameConfig.Animals do
		if discovered[animal.Name] then
			count += 1
		end
	end
	return count
end

function IndexUtil.completionPercent(discovered: { [string]: boolean }): number
	return math.floor(IndexUtil.discoveredCount(discovered) / #GameConfig.Animals * 100 + 0.5)
end

function IndexUtil.isSetComplete(discovered: { [string]: boolean }, rarity: string): boolean
	for _, species in speciesByRarity[rarity] or {} do
		if not discovered[species] then
			return false
		end
	end
	return true
end

-- Total permanent bonuses from every completed set.
-- Returns fractions: { Income = 0.25, Luck = 0.1 } means +25% income, +10% luck.
function IndexUtil.bonuses(discovered: { [string]: boolean }): { Income: number, Luck: number }
	local income, luck = 0, 0
	for _, reward in GameConfig.IndexRewards do
		if IndexUtil.isSetComplete(discovered, reward.Rarity) then
			income += reward.Bonus.Income or 0
			luck += reward.Bonus.Luck or 0
		end
	end
	return { Income = income, Luck = luck }
end

return IndexUtil
