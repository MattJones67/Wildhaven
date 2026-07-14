--[[
	ShopService — patch 5 rewrite. The old x2 Luck Boost button is GONE;
	this is now the POTION shop and the potion-drinking service:

	  BuyPotion(key)  -> SILVER purchase into data.Potions (shop sells only
	                     potions with a SilverCost; Major tiers come from
	                     the Wandering Trader and Lucky Blocks)
	  UsePotion(key)  -> consumes one, starts its timed buff in data.Buffs

	Stacking rule (GameConfig.Potions comment): ONE active buff per Kind.
	Buff expiry is a timestamp — PlayerStats reads it live, nothing to clean.

	SECURITY: server checks affordability, ownership, and the stacking rule;
	both remotes are rate-limited.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Remotes)

local DataService = require(script.Parent.DataService)
local IncomeService = require(script.Parent.IncomeService)

local ShopService = {}

local lastActionAt: { [Player]: number } = {}

local function rateLimited(player: Player): boolean
	local now = os.clock()
	local last = lastActionAt[player]
	if last and now - last < GameConfig.RateLimits.BuyCooldownSeconds then
		return true
	end
	lastActionAt[player] = now
	return false
end

local function pushPotions(player: Player)
	local data = DataService.get(player)
	if data then
		Remotes.PotionsUpdate:FireClient(player, { Potions = data.Potions })
	end
end

local function onBuyPotion(player: Player, key: any)
	if rateLimited(player) then
		return { Success = false, Error = "Too fast!" }
	end
	local data = DataService.get(player)
	if not data then
		return { Success = false, Error = "Still loading..." }
	end
	-- SECURITY: real potion, actually sold for silver
	local potion = typeof(key) == "string" and GameConfig.PotionByKey[key] or nil
	if not potion or not potion.SilverCost then
		return { Success = false, Error = "Not sold here!" }
	end
	-- SECURITY: server-side affordability
	if data.Silver < potion.SilverCost then
		return { Success = false, Error = "Not enough silver!" }
	end

	data.Silver -= potion.SilverCost
	data.Potions[key] = (data.Potions[key] or 0) + 1

	pushPotions(player)
	IncomeService.pushState(player)
	return { Success = true, Silver = math.floor(data.Silver) }
end

local function onUsePotion(player: Player, key: any)
	if rateLimited(player) then
		return { Success = false, Error = "Too fast!" }
	end
	local data = DataService.get(player)
	if not data then
		return { Success = false, Error = "Still loading..." }
	end
	local potion = typeof(key) == "string" and GameConfig.PotionByKey[key] or nil
	if not potion then
		return { Success = false, Error = "Unknown potion" }
	end
	-- SECURITY: must actually own one
	if (data.Potions[key] or 0) < 1 then
		return { Success = false, Error = "You don't have that potion!" }
	end
	-- Stacking rule: one buff per Kind at a time
	local active = data.Buffs[potion.Kind]
	if active and os.time() < active.EndsAt then
		return { Success = false, Error = "A " .. potion.Kind:lower() .. " buff is already active!" }
	end

	data.Potions[key] -= 1
	data.Buffs[potion.Kind] = {
		Key = key,
		Mult = potion.Mult,
		EndsAt = os.time() + potion.DurationSeconds,
	}

	pushPotions(player)
	IncomeService.pushState(player) -- luck/hatch numbers change right away
	return { Success = true, Kind = potion.Kind, SecondsLeft = potion.DurationSeconds }
end

function ShopService.init()
	Remotes.BuyPotion.OnServerInvoke = onBuyPotion
	Remotes.UsePotion.OnServerInvoke = onUsePotion

	Players.PlayerRemoving:Connect(function(player)
		lastActionAt[player] = nil
	end)
end

return ShopService
