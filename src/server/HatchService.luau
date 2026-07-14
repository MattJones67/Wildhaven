--[[
	HatchService — the base hatchery (slice 2), now with slice-3 duties:

	  * hatch speed & luck come from PlayerStats (upgrades × rebirth × index)
	  * every hatched pet gets a unique Id (so it can be equipped)
	  * discovery: first-ever species fill in the Collection Index; completing
	    a rarity set announces its permanent bonus
	  * goal counters bump (HatchCount, BestRarityOrder)
	  * AUTO-HATCH (rebirth unlock): a server loop feeds satchel eggs into
	    free slots automatically, from anywhere on the island

	Timers persist as epoch timestamps in data.Hatches, so rejoining
	resumes them and offline finishes complete on arrival. No egg is lost.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local EggModels = require(ReplicatedStorage.EggModels)
local GameConfig = require(ReplicatedStorage.GameConfig)
local IndexUtil = require(ReplicatedStorage.IndexUtil)
local Remotes = require(ReplicatedStorage.Remotes)
local RollUtil = require(ReplicatedStorage.RollUtil)

local BaseUpgradeService = require(script.Parent.BaseUpgradeService)
local DataService = require(script.Parent.DataService)
local GoalService = require(script.Parent.GoalService)
local IncomeService = require(script.Parent.IncomeService)
local PlayerStats = require(script.Parent.PlayerStats)

local HatchService = {}

local lastStartAt: { [Player]: number } = {}
local slotEggModels: { [Player]: { [number]: Model } } = {}

-- QuestService plugs in here (patch 4) to count hatches toward quests
-- without a circular require. Receives (player, species, rarityOrder).
local hatchedCallback: ((Player, string, number) -> ())? = nil
function HatchService.setHatchedCallback(callback: (Player, string, number) -> ())
	hatchedCallback = callback
end

-- ------------------------------------------------------------
-- Slot egg visuals
-- ------------------------------------------------------------

local function destroySlotEgg(player: Player, slot: number)
	local models = slotEggModels[player]
	if models and models[slot] then
		models[slot]:Destroy()
		models[slot] = nil
	end
end

local function placeSlotEgg(player: Player, hatch: { Slot: number, EggType: string, EndsAt: number })
	destroySlotEgg(player, hatch.Slot)
	local pads = BaseUpgradeService.getPadPositions(player)
	local pad = pads[hatch.Slot]
	if not pad then
		return -- pad not built yet; onBaseRebuilt will try again
	end

	local egg = GameConfig.EggByName[hatch.EggType]
	local model = EggModels.create(hatch.EggType)
	model:PivotTo(CFrame.new(pad))
	model:SetAttribute("HatchEndsAt", hatch.EndsAt)
	model:SetAttribute("HatchDuration", egg.HatchSeconds)
	CollectionService:AddTag(model, "SlotEgg")
	model.Parent = workspace

	slotEggModels[player] = slotEggModels[player] or {}
	slotEggModels[player][hatch.Slot] = model
end

local function onBaseRebuilt(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	for _, hatch in data.Hatches do
		placeSlotEgg(player, hatch)
	end
end

-- ------------------------------------------------------------
-- Starting a hatch (shared by manual + auto paths)
-- ------------------------------------------------------------

-- Core deposit logic, AFTER caller-specific validation. Assumes data loaded.
local function startHatchInternal(player: Player, data, eggType: string)
	-- Owns one of these eggs?
	local inventoryIndex
	for index, carried in data.EggInventory do
		if carried == eggType then
			inventoryIndex = index
			break
		end
	end
	if not inventoryIndex then
		return { Success = false, Error = "You don't have that egg!" }
	end

	-- Free slot? (slot count is an upgrade)
	local slotCount = BaseUpgradeService.getHatchSlots(player)
	local used = {}
	for _, hatch in data.Hatches do
		used[hatch.Slot] = true
	end
	local freeSlot
	for slot = 1, slotCount do
		if not used[slot] then
			freeSlot = slot
			break
		end
	end
	if not freeSlot then
		return { Success = false, Error = "All hatch slots busy!" }
	end

	table.remove(data.EggInventory, inventoryIndex)
	local egg = GameConfig.EggByName[eggType]
	local duration = egg.HatchSeconds * PlayerStats.getHatchSpeedMultiplier(player)
	local hatch = { Slot = freeSlot, EggType = eggType, EndsAt = os.time() + math.ceil(duration) }
	table.insert(data.Hatches, hatch)

	placeSlotEgg(player, hatch)
	Remotes.EggInventoryUpdate:FireClient(player, {
		Inventory = data.EggInventory,
		Capacity = PlayerStats.getEggCapacity(player),
	})
	return { Success = true, Slot = freeSlot, EndsAt = hatch.EndsAt }
end

local function onStartHatch(player: Player, eggType: any)
	-- SECURITY CHECK 1: rate limit
	local now = os.clock()
	local last = lastStartAt[player]
	if last and now - last < GameConfig.RateLimits.StartHatchCooldownSeconds then
		return { Success = false, Error = "Too fast!" }
	end
	lastStartAt[player] = now

	-- SECURITY CHECK 2: well-formed egg type
	if typeof(eggType) ~= "string" or not GameConfig.EggByName[eggType] then
		return { Success = false, Error = "Unknown egg" }
	end

	local data = DataService.get(player)
	if not data then
		return { Success = false, Error = "Still loading..." }
	end

	-- SECURITY CHECK 3: manual hatching happens AT your base
	local plotCFrame = BaseUpgradeService.getPlotCFrame(player)
	if not plotCFrame then
		return { Success = false, Error = "You have no base!" }
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - plotCFrame.Position).Magnitude > GameConfig.Hatchery.MaxStartDistance then
		return { Success = false, Error = "Go to your base to hatch!" }
	end

	return startHatchInternal(player, data, eggType)
end

-- ------------------------------------------------------------
-- Completing hatches
-- ------------------------------------------------------------

local function completeHatch(player: Player, data, hatchIndex: number)
	local hatch = data.Hatches[hatchIndex]
	table.remove(data.Hatches, hatchIndex)

	-- THE ROLL: pet from this egg's pool + mutation + size, with total luck.
	-- Mutations additionally honor class perks (e.g. Demon +10% mutation odds).
	local luck = PlayerStats.getLuck(player)
	local species = RollUtil.rollPetFromEgg(hatch.EggType, luck)
	local mutation = RollUtil.rollMutation(luck * PlayerStats.getMutationLuck(player))
	local size = RollUtil.rollSize(luck)

	local entry = { Species = species, Mutation = mutation, Size = size, Id = data.NextPetId }
	data.NextPetId += 1
	table.insert(data.Collection, entry)

	-- DISCOVERY: first time seeing this species fills in the dex
	if not data.Discovered[species] then
		data.Discovered[species] = true
		Remotes.IndexUpdate:FireClient(player, { Discovered = data.Discovered })
		Remotes.Notify:FireClient(player, { Text = "📖 NEW PET: " .. species .. "!", Kind = "Discovery" })
		-- Did that complete a rarity set? Announce the permanent bonus.
		local rarity = GameConfig.AnimalByName[species].Rarity
		if IndexUtil.isSetComplete(data.Discovered, rarity) then
			for _, reward in GameConfig.IndexRewards do
				if reward.Rarity == rarity then
					Remotes.Notify:FireClient(player, { Text = "🏆 " .. reward.Label, Kind = "Discovery" })
				end
			end
		end
	end

	-- Goal ladder + quest bookkeeping
	local rarityOrder = GameConfig.RarityByName[GameConfig.AnimalByName[species].Rarity].Order
	GoalService.bump(player, "HatchCount")
	GoalService.raiseTo(player, "BestRarityOrder", rarityOrder)
	if hatchedCallback then
		hatchedCallback(player, species, rarityOrder)
	end

	-- Where should the reveal play?
	local pads = BaseUpgradeService.getPadPositions(player)
	local position = pads[hatch.Slot]
	if not position then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		position = root and (root :: BasePart).Position or Vector3.zero
	end
	destroySlotEgg(player, hatch.Slot)

	local animal = GameConfig.AnimalByName[species]
	Remotes.HatchComplete:FireClient(player, {
		Species = species,
		Rarity = animal.Rarity,
		Mutation = mutation,
		Size = size,
		EggType = hatch.EggType,
		Position = position,
		PetId = entry.Id,
	})
	Remotes.CollectionUpdate:FireClient(player, data.Collection)
	IncomeService.pushState(player)
end

-- ------------------------------------------------------------
-- Auto-hatch toggle (rebirth unlock)
-- ------------------------------------------------------------

local function onToggleAutoHatch(player: Player)
	local data = DataService.get(player)
	if not data then
		return { Success = false, Error = "Still loading..." }
	end
	-- SECURITY: only works once the rebirth ladder unlocked it
	if not PlayerStats.hasAutoHatch(player) then
		return { Success = false, Error = "Unlocks at Rebirth 2!" }
	end
	data.AutoHatch = not data.AutoHatch
	return { Success = true, Enabled = data.AutoHatch }
end

function HatchService.init()
	Remotes.StartHatch.OnServerInvoke = onStartHatch
	Remotes.ToggleAutoHatch.OnServerInvoke = onToggleAutoHatch
	BaseUpgradeService.setBaseRebuiltCallback(onBaseRebuilt)

	-- Completion tick (also finishes hatches that ended while offline)
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.time()
			for player, data in DataService.getAllLoaded() do
				for index = #data.Hatches, 1, -1 do
					if data.Hatches[index].EndsAt <= now then
						completeHatch(player, data, index)
					end
				end
			end
		end
	end)

	-- Auto-hatch tick: quietly feed satchel eggs into free slots
	task.spawn(function()
		while true do
			task.wait(GameConfig.AutoHatch.IntervalSeconds)
			for player, data in DataService.getAllLoaded() do
				if data.AutoHatch and PlayerStats.hasAutoHatch(player) and #data.EggInventory > 0 then
					-- FIFO: oldest carried egg goes in first
					startHatchInternal(player, data, data.EggInventory[1])
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastStartAt[player] = nil
		local models = slotEggModels[player]
		if models then
			slotEggModels[player] = nil
			for _, model in models do
				model:Destroy()
			end
		end
	end)
end

return HatchService
