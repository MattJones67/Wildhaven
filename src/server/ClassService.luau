--[[
	ClassService — rolls the player's CLASS (their passive identity perk).

	Class definitions, weights, and perk values all live in
	GameConfig.Classes. The perks themselves are already applied everywhere
	by PlayerStats (income / luck / hatch speed / mutation odds), so this
	service only owns WHO gets to roll WHEN, and what they rolled.

	Roll payment ladder (checked in order, server-side):
	  1. First roll ever (Class == "")            -> FREE
	  2. Class Token (earned from quests)         -> consumes one token
	  3. Free daily roll (24h since last free)    -> free, stamps the timer
	  4. Otherwise                                -> costs coins (RerollCost)

	SECURITY: rate-limited; the server rolls the RNG; timestamps are server
	time (os.time()), so client clock fiddling does nothing.

	TODO(monetisation): a paid Robux re-roll would be a MarketplaceService
	ProcessReceipt that calls doRoll(player, "paid") — the payment ladder
	below stays untouched.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Remotes)

local DataService = require(script.Parent.DataService)
local IncomeService = require(script.Parent.IncomeService)

local CLASSES = GameConfig.Classes

local ClassService = {}

local lastRollAt: { [Player]: number } = {}

-- Weighted roll over the class list (same raffle math as pets)
local function rollWeighted(rng: Random): any
	local totalWeight = 0
	for _, class in CLASSES.List do
		totalWeight += class.Weight
	end
	local ticket = rng:NextNumber() * totalWeight
	local runningTotal = 0
	for _, class in CLASSES.List do
		runningTotal += class.Weight
		if ticket <= runningTotal then
			return class
		end
	end
	return CLASSES.List[1]
end

local rng = Random.new()

local function onRollClass(player: Player)
	-- SECURITY CHECK 1: rate limit (the client also plays a ~2s animation)
	local now = os.clock()
	local last = lastRollAt[player]
	if last and now - last < 1.5 then
		return { Success = false, Error = "Too fast!" }
	end
	lastRollAt[player] = now

	local data = DataService.get(player)
	if not data then
		return { Success = false, Error = "Still loading..." }
	end

	-- SECURITY CHECK 2: the payment ladder (all server state)
	local paidWith
	if data.Class == "" or data.Class == nil then
		paidWith = "first" -- welcome to Wildhaven
	elseif (data.ClassTokens or 0) > 0 then
		data.ClassTokens -= 1
		paidWith = "token"
	elseif os.time() - (data.LastClassRollAt or 0) >= CLASSES.FreeRollCooldownSeconds then
		data.LastClassRollAt = os.time()
		paidWith = "daily"
	elseif data.Coins >= CLASSES.RerollCost then
		data.Coins -= CLASSES.RerollCost
		paidWith = "coins"
	else
		local waitSeconds = (data.LastClassRollAt or 0) + CLASSES.FreeRollCooldownSeconds - os.time()
		local hours = math.max(1, math.ceil(waitSeconds / 3600))
		return { Success = false, Error = ("Free roll in ~%dh (or %d 🪙)"):format(hours, CLASSES.RerollCost) }
	end

	local class = rollWeighted(rng)
	data.Class = class.Name

	IncomeService.pushState(player) -- perks changed income/luck instantly

	return {
		Success = true,
		Class = class.Name,
		Tier = class.Tier,
		Blurb = class.Blurb,
		PaidWith = paidWith,
		Coins = math.floor(data.Coins),
	}
end

function ClassService.init()
	Remotes.RollClass.OnServerInvoke = onRollClass

	Players.PlayerRemoving:Connect(function(player)
		lastRollAt[player] = nil
	end)
end

return ClassService
