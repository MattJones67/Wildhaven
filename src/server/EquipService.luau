--[[
	EquipService — owns which pets each player has EQUIPPED. This matters
	because (slice 3 rule) income comes ONLY from equipped pets.

	The server is the authority: data.Equipped holds pet Ids, and every
	toggle is validated (you must own the pet; you can't exceed your slot
	count). The client's PetFollowController just renders what the
	EquipBroadcast says — for every player, so you see other people's
	teams trailing behind them too.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Remotes)

local DataService = require(script.Parent.DataService)
local GoalService = require(script.Parent.GoalService)
local IncomeService = require(script.Parent.IncomeService)
local PlayerStats = require(script.Parent.PlayerStats)

local EquipService = {}

local lastToggleAt: { [Player]: number } = {}

-- Tell EVERY client what this player has equipped (for follow visuals)
function EquipService.broadcast(player: Player)
	local data = DataService.get(player)
	local pets = {}
	if data then
		local byId = {}
		for _, entry in data.Collection do
			if entry.Id then
				byId[entry.Id] = entry
			end
		end
		for _, id in data.Equipped do
			local entry = byId[id]
			if entry then
				table.insert(pets, { Species = entry.Species, Mutation = entry.Mutation, Size = entry.Size or "Normal" })
			end
		end
	end
	Remotes.EquipBroadcast:FireAllClients({ UserId = player.UserId, Pets = pets })
end

-- Tell THIS player their equip state (ids + slots, drives the equip UI)
function EquipService.pushEquipped(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	Remotes.EquipUpdate:FireClient(player, {
		Equipped = data.Equipped,
		Slots = PlayerStats.getEquipSlots(player),
	})
end

-- After rebirth, slot count can shrink (upgrades reset) — trim overflow.
function EquipService.clampToSlots(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local slots = PlayerStats.getEquipSlots(player)
	while #data.Equipped > slots do
		table.remove(data.Equipped)
	end
	EquipService.pushEquipped(player)
	EquipService.broadcast(player)
	IncomeService.pushState(player)
end

local function onToggleEquip(player: Player, petId: any)
	-- SECURITY CHECK 1: rate limit (equip spam = broadcast spam)
	local now = os.clock()
	local last = lastToggleAt[player]
	if last and now - last < 0.25 then
		return { Success = false, Error = "Too fast!" }
	end
	lastToggleAt[player] = now

	if typeof(petId) ~= "number" then
		return { Success = false, Error = "Bad request" }
	end
	local data = DataService.get(player)
	if not data then
		return { Success = false, Error = "Still loading..." }
	end

	-- SECURITY CHECK 2: you can only equip a pet you actually OWN
	local owned = false
	for _, entry in data.Collection do
		if entry.Id == petId then
			owned = true
			break
		end
	end
	if not owned then
		return { Success = false, Error = "You don't own that pet!" }
	end

	-- Toggle: unequip if it's already on the team...
	for index, id in data.Equipped do
		if id == petId then
			table.remove(data.Equipped, index)
			EquipService.pushEquipped(player)
			EquipService.broadcast(player)
			IncomeService.pushState(player)
			GoalService.check(player)
			return { Success = true, Equipped = false }
		end
	end

	-- ...otherwise equip, if a slot is free (SECURITY CHECK 3)
	if #data.Equipped >= PlayerStats.getEquipSlots(player) then
		return { Success = false, Error = "No free equip slots!" }
	end
	table.insert(data.Equipped, petId)

	EquipService.pushEquipped(player)
	EquipService.broadcast(player)
	IncomeService.pushState(player)
	GoalService.check(player)
	return { Success = true, Equipped = true }
end

function EquipService.init()
	Remotes.ToggleEquip.OnServerInvoke = onToggleEquip

	Players.PlayerAdded:Connect(function(player)
		task.spawn(function()
			local data = DataService.waitForData(player, 15)
			if not data or player.Parent == nil then
				return
			end
			-- MIGRATION NICETY: auto-equip the best pets for players from
			-- before the equip system, so their income doesn't drop to zero.
			if #data.Equipped == 0 and #data.Collection > 0 then
				local slots = PlayerStats.getEquipSlots(player)
				local sorted = table.clone(data.Collection)
				local RollUtil = require(ReplicatedStorage.RollUtil)
				table.sort(sorted, function(a, b)
					return RollUtil.incomeForEntry(a) > RollUtil.incomeForEntry(b)
				end)
				for i = 1, math.min(slots, #sorted) do
					table.insert(data.Equipped, sorted[i].Id)
				end
			end
			EquipService.pushEquipped(player)
			EquipService.broadcast(player)
			-- Late joiner needs everyone ELSE's teams too
			for _, other in Players:GetPlayers() do
				if other ~= player then
					EquipService.broadcast(other)
				end
			end
		end)
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastToggleAt[player] = nil
		Remotes.EquipBroadcast:FireAllClients({ UserId = player.UserId, Pets = {} })
	end)
end

return EquipService
