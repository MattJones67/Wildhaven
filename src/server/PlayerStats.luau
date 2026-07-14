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

-- Total effective luck for every roll (pets, mutations, sizes)
function PlayerStats.getLuck(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 1
	end
	local boost = DataService.getLuckMultiplier(player) -- 1, or 2 while boosted
	local rebirthBonus = 1 + REBIRTH.LuckPerRebirth * (data.Rebirths or 0)
	local indexBonus = 1 + IndexUtil.bonuses(data.Discovered or {}).Luck
	return boost * rebirthBonus * indexBonus
end

-- Coins/sec from EQUIPPED pets only (the slice-3 rule), fully multiplied
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

	local upgradeMult = upgradeValue(data, "IncomeBoost")
	local rebirthMult = 1 + REBIRTH.IncomePerRebirth * (data.Rebirths or 0)
	local indexMult = 1 + IndexUtil.bonuses(data.Discovered or {}).Income
	return base * upgradeMult * rebirthMult * indexMult
end

function PlayerStats.getHatchSpeedMultiplier(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 1
	end
	local mult = upgradeValue(data, "HatchSpeed") * (1 - REBIRTH.HatchSpeedPerRebirth) ^ (data.Rebirths or 0)
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
