--[[
	PlayerStats — the single place where a player's DERIVED numbers are
	composed. Everything that asks "how lucky / how fast / how many" goes
	through here, so the stacking rules live in exactly one file:

	  luck        = luck boost * (1 + rebirth luck) * (1 + index luck bonus)
	  income/sec  = sum(EQUIPPED pets' base*mutation*size)
	                * IncomeBoost upgrade * (1 + rebirth income) * (1 + index bonus)
	  hatch speed = HatchSpeed upgrade * (1 - 5%)^rebirths   (floored)
	  capacity    = EggCapacity upgrade + 2 per rebirth
	  equip slots = EquipSlots upgrade + rebirth "EquipSlot" unlocks

	Deliberately standalone (only DataService + shared modules) so any
	service can require it without dependency cycles.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local IndexUtil = require(ReplicatedStorage.IndexUtil)
local RollUtil = require(ReplicatedStorage.RollUtil)

local DataService = require(script.Parent.DataService)

local REBIRTH = GameConfig.Rebirth

local PlayerStats = {}

-- Raw upgrade value at the player's current level for one key
local function upgradeValue(data, key: string): any
	local upgrade = GameConfig.UpgradeByKey[key]
	local level = (data and data.Upgrades[key]) or 1
	return upgrade.Values[math.clamp(level, 1, #upgrade.Values)]
end

-- How many rebirth-ladder unlocks of a given type the player has earned
local function rebirthUnlockCount(data, unlockType: string): number
	local count = 0
	for _, unlock in REBIRTH.Unlocks do
		if unlock.Type == unlockType and (data.Rebirths or 0) >= unlock.Rebirth then
			count += 1
		end
	end
	return count
end

function PlayerStats.hasAutoHatch(player: Player): boolean
	local data = DataService.get(player)
	return data ~= nil and rebirthUnlockCount(data, "AutoHatch") > 0
end

-- Sanctuary caps (patch 4): both are plain upgrade values
function PlayerStats.getSanctuaryObjectCap(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 0
	end
	return upgradeValue(data, "SanctuarySize")
end

function PlayerStats.getSanctuaryPetCap(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 0
	end
	return upgradeValue(data, "SanctuaryPets")
end

-- Patch 4 perk sources: the biome hosting your sanctuary, and your class.
-- Both return neutral values when unset, so they're safe everywhere.
local function plotPerk(data): { Income: number?, Luck: number?, HatchSpeed: number? }
	local biomeName = data.Sanctuary and data.Sanctuary.Biome or "Forest"
	local biome = GameConfig.BiomeByName[biomeName]
	return biome and biome.Perk or {}
end

local function classPerks(data): { Income: number?, Luck: number?, HatchSpeed: number?, MutationChance: number? }
	local class = data.Class and GameConfig.ClassByName[data.Class]
	return class and class.Perks or {}
end

-- Total effective luck for every roll (pets, mutations, sizes)
function PlayerStats.getLuck(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 1
	end
	local boost = DataService.getLuckMultiplier(player) -- 1, or 2 while boosted
	local rebirthBonus = 1 + REBIRTH.LuckPerRebirth * (data.Rebirths or 0)
	local indexBonus = 1 + IndexUtil.bonuses(data.Discovered or {}).Luck
	local plot = plotPerk(data).Luck or 1
	local class = classPerks(data).Luck or 1
	return boost * rebirthBonus * indexBonus * plot * class
end

-- Extra multiplier applied to MUTATION odds only (Demon class, etc.).
-- HatchService rolls mutations with getLuck() * this.
function PlayerStats.getMutationLuck(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 1
	end
	return classPerks(data).MutationChance or 1
end

-- Sanctuary earnings (patch 4): pets placed into habitats earn ON TOP of
-- equipped pets. Matched-habitat pets earn x MatchedHabitatBonus, and a
-- cohesive theme (enough same-biome objects) adds the theme multiplier.
local function sanctuaryIncome(data): number
	local sanct = data.Sanctuary
	if not sanct or not sanct.PlacedPets then
		return 0
	end
	local byId = {}
	for _, entry in data.Collection do
		if entry.Id then
			byId[entry.Id] = entry
		end
	end
	-- How many placed objects belong to each biome theme?
	local themeCounts = {}
	for _, object in sanct.Objects or {} do
		local def = GameConfig.SanctuaryObjectByKey[object.Key]
		if def and def.Biome then
			themeCounts[def.Biome] = (themeCounts[def.Biome] or 0) + 1
		end
	end
	local objectsByUid = {}
	for _, object in sanct.Objects or {} do
		objectsByUid[object.Uid] = object
	end

	local total = 0
	local theme = GameConfig.Sanctuary.ThemeBonus
	for _, placed in sanct.PlacedPets do
		local entry = byId[placed.PetId]
		local object = objectsByUid[placed.ObjectUid]
		local objectDef = object and GameConfig.SanctuaryObjectByKey[object.Key]
		if entry and objectDef then
			local income = RollUtil.incomeForEntry(entry)
			local animal = GameConfig.AnimalByName[entry.Species]
			local petBiome = animal and animal.Biome
			if petBiome and objectDef.Biome == petBiome then
				income *= GameConfig.Sanctuary.MatchedHabitatBonus
				if (themeCounts[petBiome] or 0) >= theme.MinSameBiomeObjects then
					income *= theme.Mult
				end
			end
			total += income
		end
	end
	return total
end

-- Coins/sec = EQUIPPED pets + SANCTUARY-placed pets, fully multiplied
function PlayerStats.getIncomePerSecond(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 0
	end
	-- Sum only the equipped entries (Equipped holds pet Ids)
	local equippedSet = {}
	for _, id in data.Equipped or {} do
		equippedSet[id] = true
	end
	local base = 0
	for _, entry in data.Collection do
		if entry.Id and equippedSet[entry.Id] then
			base += RollUtil.incomeForEntry(entry)
		end
	end
	base += sanctuaryIncome(data)

	local upgradeMult = upgradeValue(data, "IncomeBoost")
	local rebirthMult = 1 + REBIRTH.IncomePerRebirth * (data.Rebirths or 0)
	local indexMult = 1 + IndexUtil.bonuses(data.Discovered or {}).Income
	local plotMult = plotPerk(data).Income or 1
	local classMult = classPerks(data).Income or 1
	return base * upgradeMult * rebirthMult * indexMult * plotMult * classMult
end

function PlayerStats.getHatchSpeedMultiplier(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 1
	end
	local mult = upgradeValue(data, "HatchSpeed") * (1 - REBIRTH.HatchSpeedPerRebirth) ^ (data.Rebirths or 0)
	mult *= plotPerk(data).HatchSpeed or 1
	mult *= classPerks(data).HatchSpeed or 1
	return math.max(mult, REBIRTH.HatchSpeedFloor)
end

function PlayerStats.getEggCapacity(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 3
	end
	return upgradeValue(data, "EggCapacity") + REBIRTH.CapacityPerRebirth * (data.Rebirths or 0)
end

function PlayerStats.getEquipSlots(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 2
	end
	return upgradeValue(data, "EquipSlots") + rebirthUnlockCount(data, "EquipSlot")
end

-- Lifetime-earnings requirement for the player's NEXT rebirth
function PlayerStats.getNextRebirthRequirement(player: Player): number
	local data = DataService.get(player)
	local rebirths = data and data.Rebirths or 0
	return REBIRTH.RequirementBase * REBIRTH.RequirementGrowth ^ rebirths
end

return PlayerStats
