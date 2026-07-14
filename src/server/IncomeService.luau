--[[
	IncomeService — pays out passive income and keeps clients informed.

	Slice 3 rule: revenue comes ONLY from EQUIPPED pets. The whole formula
	(equipped pets * upgrades * rebirth * index bonuses) lives in
	PlayerStats.getIncomePerSecond — this service just applies it per tick
	via DataService.grantCoins (which also feeds TotalEarned for rebirth).

	Also answers GetState — the client's one big snapshot on join.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Remotes)

local DataService = require(script.Parent.DataService)
local GoalService = require(script.Parent.GoalService)
local PlayerStats = require(script.Parent.PlayerStats)

local IncomeService = {}

-- Send one player a fresh snapshot of their numbers.
function IncomeService.pushState(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	Remotes.StateUpdate:FireClient(player, {
		Coins = math.floor(data.Coins),
		IncomePerSecond = PlayerStats.getIncomePerSecond(player),
		LuckMultiplier = math.floor(PlayerStats.getLuck(player) * 100 + 0.5) / 100,
		LuckSecondsLeft = DataService.getLuckSecondsLeft(player),
		TotalEarned = math.floor(data.TotalEarned),
		NextRebirthRequirement = PlayerStats.getNextRebirthRequirement(player),
		Rebirths = data.Rebirths,
	})
end

function IncomeService.init()
	Remotes.GetState.OnServerInvoke = function(player: Player)
		local data = DataService.waitForData(player, 10)
		if not data then
			return nil
		end
		return {
			Coins = math.floor(data.Coins),
			IncomePerSecond = PlayerStats.getIncomePerSecond(player),
			LuckMultiplier = math.floor(PlayerStats.getLuck(player) * 100 + 0.5) / 100,
			LuckSecondsLeft = DataService.getLuckSecondsLeft(player),
			Collection = data.Collection,
			EggInventory = data.EggInventory,
			EggCapacity = PlayerStats.getEggCapacity(player),
			Upgrades = data.Upgrades,
			HatchSlots = data.Upgrades.HatchSlots and GameConfig.UpgradeByKey.HatchSlots.Values[data.Upgrades.HatchSlots] or 2,
			-- slice 3:
			Equipped = data.Equipped,
			EquipSlots = PlayerStats.getEquipSlots(player),
			Rebirths = data.Rebirths,
			TotalEarned = math.floor(data.TotalEarned),
			NextRebirthRequirement = PlayerStats.getNextRebirthRequirement(player),
			Discovered = data.Discovered,
			AutoHatchUnlocked = PlayerStats.hasAutoHatch(player),
			AutoHatchEnabled = data.AutoHatch,
			Goal = GoalService.payload(player),
		}
	end

	-- The heartbeat of the economy: accrue income for everyone, every tick.
	task.spawn(function()
		while true do
			task.wait(GameConfig.Income.TickSeconds)
			for player in DataService.getAllLoaded() do
				local income = PlayerStats.getIncomePerSecond(player)
				if income > 0 then
					DataService.grantCoins(player, income * GameConfig.Income.TickSeconds)
				end
				IncomeService.pushState(player)
			end
		end
	end)
end

return IncomeService
