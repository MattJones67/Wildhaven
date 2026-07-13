--[[
	HatchService — the base hatchery. Hatching no longer happens at a
	pedestal: you carry an egg home and incubate it in a hatch slot.

	Flow when the client fires StartHatch(eggType):
	  1. VALIDATE: rate limit, data loaded, player NEAR THEIR OWN BASE,
	     actually owns one of that egg, has a free slot
	  2. Move the egg from inventory into a slot with a server-owned timer
	     (duration = egg's HatchSeconds * the HatchSpeed upgrade)
	  3. A visible egg sits on the slot pad, wobbling as time runs out
	     (clients render the countdown from attributes)
	  4. When the timer ends, the SERVER rolls pet + mutation + SIZE with
	     the player's luck, adds it to the collection, and tells the client
	     to play the reveal at the pad.

	Timers persist: data.Hatches stores {Slot, EggType, EndsAt} with real
	epoch times, so rejoining resumes them — and anything that finished
	while you were offline completes the moment you're back. No egg is
	ever lost.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local EggModels = require(ReplicatedStorage.EggModels)
local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Remotes)
local RollUtil = require(ReplicatedStorage.RollUtil)

local BaseUpgradeService = require(script.Parent.BaseUpgradeService)
local DataService = require(script.Parent.DataService)
local IncomeService = require(script.Parent.IncomeService)

local HatchService = {}

local lastStartAt: { [Player]: number } = {}
local slotEggModels: { [Player]: { [number]: Model } } = {}

-- ------------------------------------------------------------
-- Slot egg visuals (the egg sitting on the pad while it incubates)
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
	-- Attributes let the CLIENT render the countdown + wobble locally
	model:SetAttribute("HatchEndsAt", hatch.EndsAt)
	model:SetAttribute("HatchDuration", egg.HatchSeconds)
	CollectionService:AddTag(model, "SlotEgg")
	model.Parent = workspace

	slotEggModels[player] = slotEggModels[player] or {}
	slotEggModels[player][hatch.Slot] = model
end

-- Called by BaseUpgradeService whenever a cabin is rebuilt (join, upgrade):
-- re-seat every incubating egg on its (possibly moved) pad.
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
-- Starting a hatch
-- ------------------------------------------------------------

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

	-- SECURITY CHECK 3: must be near YOUR base (hatching is a home activity)
	local plotCFrame = BaseUpgradeService.getPlotCFrame(player)
	if not plotCFrame then
		return { Success = false, Error = "You have no base!" }
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - plotCFrame.Position).Magnitude > GameConfig.Hatchery.MaxStartDistance then
		return { Success = false, Error = "Go to your base to hatch!" }
	end

	-- SECURITY CHECK 4: the player actually carries one of these eggs
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

	-- SECURITY CHECK 5: a free slot exists (slots are an upgrade)
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

	-- All validated: move egg from inventory into the slot
	table.remove(data.EggInventory, inventoryIndex)
	local egg = GameConfig.EggByName[eggType]
	local duration = egg.HatchSeconds * BaseUpgradeService.getHatchSpeedMultiplier(player)
	local hatch = { Slot = freeSlot, EggType = eggType, EndsAt = os.time() + math.ceil(duration) }
	table.insert(data.Hatches, hatch)

	placeSlotEgg(player, hatch)

	-- Refresh the client's inventory display
	Remotes.EggInventoryUpdate:FireClient(player, {
		Inventory = data.EggInventory,
		Capacity = BaseUpgradeService.getEggCapacity(player),
	})

	return { Success = true, Slot = freeSlot, EndsAt = hatch.EndsAt }
end

-- ------------------------------------------------------------
-- Completing hatches (server-owned timer loop)
-- ------------------------------------------------------------

local function completeHatch(player: Player, data, hatchIndex: number)
	local hatch = data.Hatches[hatchIndex]
	table.remove(data.Hatches, hatchIndex)

	-- THE ROLL happens here, at completion, with the server's luck value.
	local luck = DataService.getLuckMultiplier(player)
	local species = RollUtil.rollPetFromEgg(hatch.EggType, luck)
	local mutation = RollUtil.rollMutation(luck)
	local size = RollUtil.rollSize(luck)

	table.insert(data.Collection, { Species = species, Mutation = mutation, Size = size })

	-- Where should the reveal play? At the pad if it exists, else at the player.
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
	})
	Remotes.CollectionUpdate:FireClient(player, data.Collection)
	IncomeService.pushState(player)
end

function HatchService.init()
	Remotes.StartHatch.OnServerInvoke = onStartHatch
	BaseUpgradeService.setBaseRebuiltCallback(onBaseRebuilt)

	-- Tick the hatchery once a second; completes offline hatches too,
	-- because EndsAt is a real epoch timestamp.
	task.spawn(function()
		while true do
			task.wait(1)
			local now = os.time()
			for player, data in DataService.getAllLoaded() do
				-- Walk backwards so removals don't skip entries
				for index = #data.Hatches, 1, -1 do
					if data.Hatches[index].EndsAt <= now then
						completeHatch(player, data, index)
					end
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
