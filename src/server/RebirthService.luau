--[[
	RebirthService — the long-term retention spine.

	Rebirth trades your CURRENT progress for PERMANENT power:
	  RESET: coins (back to starting), ALL base upgrade levels (including
	         aesthetics — the cabin visibly reverts, that's the sacrifice)
	  KEPT:  pets, discoveries, carried eggs, running hatches, goals
	  GAINED (forever, per rebirth — see GameConfig.Rebirth):
	         +50% income, +25% luck, 5% faster hatches, +2 egg capacity,
	         plus the unlock ladder (+equip slots, AUTO-HATCH at rebirth 2)

	Requirement: lifetime TotalEarned must reach an escalating threshold
	(25k, 100k, 400k, ...). SECURITY: the server checks the requirement
	against ITS OWN TotalEarned figure — the client just renders progress.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Remotes)

local BaseUpgradeService = require(script.Parent.BaseUpgradeService)
local DataService = require(script.Parent.DataService)
local EquipService = require(script.Parent.EquipService)
local GoalService = require(script.Parent.GoalService)
local IncomeService = require(script.Parent.IncomeService)
local PlayerStats = require(script.Parent.PlayerStats)

local RebirthService = {}

local lastRebirthAt: { [Player]: number } = {}

local function onRebirth(player: Player)
	-- SECURITY CHECK 1: rate limit (rebirth rebuilds the cabin — not spammable)
	local now = os.clock()
	local last = lastRebirthAt[player]
	if last and now - last < 2 then
		return { Success = false, Error = "Too fast!" }
	end
	lastRebirthAt[player] = now

	local data = DataService.get(player)
	if not data then
		return { Success = false, Error = "Still loading..." }
	end

	-- SECURITY CHECK 2: the server-side lifetime earnings must qualify
	local requirement = PlayerStats.getNextRebirthRequirement(player)
	if data.TotalEarned < requirement then
		return { Success = false, Error = "Earn more coins first!" }
	end

	-- THE TRADE
	data.Rebirths += 1
	data.Coins = GameConfig.Economy.StartingCoins
	for _, upgrade in GameConfig.BaseUpgrades do
		data.Upgrades[upgrade.Key] = 1 -- everything back to level 1
	end

	-- What did this rebirth unlock? (for the celebration banner)
	local unlockLabel = nil
	for _, unlock in GameConfig.Rebirth.Unlocks do
		if unlock.Rebirth == data.Rebirths then
			unlockLabel = unlock.Label
		end
	end

	-- Apply the fallout: cabin reverts, walk speed resets, equips may
	-- overflow the (smaller) slot count and get trimmed
	BaseUpgradeService.refresh(player)
	EquipService.clampToSlots(player)
	GoalService.check(player) -- "Rebirth once" goal is a live stat
	IncomeService.pushState(player)

	Remotes.RebirthCelebrate:FireClient(player, {
		Count = data.Rebirths,
		UnlockLabel = unlockLabel,
		NextRequirement = PlayerStats.getNextRebirthRequirement(player),
	})
	return { Success = true, Count = data.Rebirths }
end

function RebirthService.init()
	Remotes.Rebirth.OnServerInvoke = onRebirth

	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastRebirthAt[player] = nil
	end)
end

return RebirthService
