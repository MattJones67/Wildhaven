--[[
	IncomeService — pays out passive income and keeps clients informed.

	Pet revenue formula (slice 2): base income * mutation * SIZE, summed
	across the collection (that part lives in RollUtil.incomePerSecond),
	then multiplied by the IncomeBoost base upgrade.

	Every tick it adds each player's income to their SERVER-side balance
	and pushes a StateUpdate. It also answers GetState (the client's one
	big snapshot on join) and exposes pushState() so other services can
	refresh a client right after a purchase or hatch.

	SECURITY: coins only ever change in the server services — the client
	just renders the numbers it is sent.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Remotes)
local RollUtil = require(ReplicatedStorage.RollUtil)

local BaseUpgradeService = require(script.Parent.BaseUpgradeService)
local DataService = require(script.Parent.DataService)

local IncomeService = {}

-- Full coins/sec including the IncomeBoost upgrade
function IncomeService.getIncomePerSecond(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 0
	end
	return RollUtil.incomePerSecond(data.Collection) * BaseUpgradeService.getIncomeMultiplier(player)
end

-- Send one player a fresh snapshot of their numbers.
function IncomeService.pushState(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	Remotes.StateUpdate:FireClient(player, {
		Coins = math.floor(data.Coins),
		IncomePerSecond = IncomeService.getIncomePerSecond(player),
		LuckMultiplier = DataService.getLuckMultiplier(player),
		LuckSecondsLeft = DataService.getLuckSecondsLeft(player),
	})
end

function IncomeService.init()
	-- The client calls this once on startup for its full state. waitForData
	-- handles the race where the client asks before the DataStore load ends.
	Remotes.GetState.OnServerInvoke = function(player: Player)
		local data = DataService.waitForData(player, 10)
		if not data then
			return nil
		end
		return {
			Coins = math.floor(data.Coins),
			IncomePerSecond = IncomeService.getIncomePerSecond(player),
			LuckMultiplier = DataService.getLuckMultiplier(player),
			LuckSecondsLeft = DataService.getLuckSecondsLeft(player),
			Collection = data.Collection,
			EggInventory = data.EggInventory,
			EggCapacity = BaseUpgradeService.getEggCapacity(player),
			Upgrades = data.Upgrades,
			HatchSlots = BaseUpgradeService.getHatchSlots(player),
		}
	end

	-- The heartbeat of the economy: accrue income for everyone, every tick.
	task.spawn(function()
		while true do
			task.wait(GameConfig.Income.TickSeconds)
			for player, data in DataService.getAllLoaded() do
				local income = IncomeService.getIncomePerSecond(player)
				if income > 0 then
					data.Coins += income * GameConfig.Income.TickSeconds
				end
				IncomeService.pushState(player)
			end
		end
	end)
end

return IncomeService
