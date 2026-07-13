--[[
	ShopService — handles Luck Boost purchases (and future shop items).

	Same server-authoritative pattern as HatchService: validate, deduct,
	apply. The boost itself is just a timestamp (LuckEndsAt) in the player's
	data — DataService.getLuckMultiplier() reads it, so expiry is automatic
	and there's nothing to clean up.

	TODO (later passes): gamepasses / monetisation hooks would live here.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Remotes)

local DataService = require(script.Parent.DataService)
local IncomeService = require(script.Parent.IncomeService)

local ShopService = {}

-- SECURITY: rate-limit purchases against remote spam
local lastBuyAt: { [Player]: number } = {}

local function onBuyLuckBoost(player: Player)
	-- SECURITY CHECK 1: rate limit
	local now = os.clock()
	local last = lastBuyAt[player]
	if last and now - last < GameConfig.RateLimits.BuyCooldownSeconds then
		return { Success = false, Error = "Too fast!" }
	end
	lastBuyAt[player] = now

	local data = DataService.get(player)
	if not data then
		return { Success = false, Error = "Still loading..." }
	end

	-- No stacking: one boost at a time keeps the economy predictable
	if os.time() < data.LuckEndsAt then
		return { Success = false, Error = "Boost already active!" }
	end

	-- SECURITY CHECK 2: server-side affordability
	local cost = GameConfig.LuckBoost.Cost
	if data.Coins < cost then
		return { Success = false, Error = "Not enough coins!" }
	end

	data.Coins -= cost
	data.LuckEndsAt = os.time() + GameConfig.LuckBoost.DurationSeconds

	IncomeService.pushState(player)

	return {
		Success = true,
		Coins = math.floor(data.Coins),
		SecondsLeft = GameConfig.LuckBoost.DurationSeconds,
	}
end

function ShopService.init()
	Remotes.BuyLuckBoost.OnServerInvoke = onBuyLuckBoost

	Players.PlayerRemoving:Connect(function(player)
		lastBuyAt[player] = nil
	end)
end

return ShopService
