--[[
	ReturnsService — the "welcome back" layer: offline income + daily reward.

	OFFLINE INCOME: DataService stamps LastSeenAt on every save. On join we
	pay out (time away, capped) * equipped income rate * offline multiplier —
	all server-computed from server timestamps, nothing client-supplied.

	DAILY REWARD: one claim per 24h (server-timestamped). Returning within
	the grace window advances an escalating streak; longer gaps reset it.
	Granted automatically on join with a friendly popup — no claim button
	to forget on mobile.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Remotes)

local DataService = require(script.Parent.DataService)
local IncomeService = require(script.Parent.IncomeService)
local PlayerStats = require(script.Parent.PlayerStats)

local OFFLINE = GameConfig.Offline
local DAILY = GameConfig.Daily

local ReturnsService = {}

local function grantOfflineIncome(player: Player, data)
	if data.LastSeenAt <= 0 then
		return -- first ever session
	end
	local away = os.time() - data.LastSeenAt
	if away < OFFLINE.MinAwaySeconds then
		return
	end
	local seconds = math.min(away, OFFLINE.MaxSeconds)
	-- NOTE: uses the CURRENT equipped rate. EquipService auto-equips legacy
	-- players slightly after load, which is why init waits a beat first.
	local rate = PlayerStats.getIncomePerSecond(player)
	local earned = math.floor(rate * seconds * OFFLINE.RateMultiplier)
	if earned <= 0 then
		return
	end
	DataService.grantCoins(player, earned)
	Remotes.WelcomeBack:FireClient(player, {
		Coins = earned,
		AwaySeconds = seconds,
	})
end

local function grantDailyReward(player: Player, data)
	local since = os.time() - data.LastDailyClaimAt
	if data.LastDailyClaimAt > 0 and since < DAILY.CooldownSeconds then
		return -- already claimed within 24h
	end

	-- Streak: keep climbing inside the grace window, reset outside it
	if data.LastDailyClaimAt > 0 and since <= DAILY.GraceSeconds then
		data.DailyStreak += 1
	else
		data.DailyStreak = 1
	end
	data.LastDailyClaimAt = os.time()

	local day = ((data.DailyStreak - 1) % #DAILY.Rewards) + 1
	local reward = DAILY.Rewards[day]

	if reward.Type == "Coins" then
		DataService.grantCoins(player, reward.Amount)
	elseif reward.Type == "LuckBoost" then
		data.LuckEndsAt = os.time() + GameConfig.LuckBoost.DurationSeconds
	elseif reward.Type == "Egg" then
		-- Room in the satchel? Otherwise a coin consolation, never a lost reward
		if #data.EggInventory < PlayerStats.getEggCapacity(player) then
			table.insert(data.EggInventory, reward.EggType)
			Remotes.EggInventoryUpdate:FireClient(player, {
				Inventory = data.EggInventory,
				Capacity = PlayerStats.getEggCapacity(player),
			})
		else
			DataService.grantCoins(player, 500)
		end
	end

	Remotes.DailyReward:FireClient(player, {
		Day = day,
		Streak = data.DailyStreak,
		Label = reward.Label,
	})
end

local function onPlayerAdded(player: Player)
	local data = DataService.waitForData(player, 15)
	if not data or player.Parent == nil then
		return
	end
	-- Let EquipService finish its join work (auto-equip for legacy saves)
	-- so the offline rate isn't computed against an empty team.
	task.wait(1)
	if player.Parent == nil then
		return
	end
	grantOfflineIncome(player, data)
	grantDailyReward(player, data)
	IncomeService.pushState(player)
end

function ReturnsService.init()
	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return ReturnsService
