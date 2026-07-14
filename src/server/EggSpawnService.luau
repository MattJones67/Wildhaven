--[[
	EggSpawnService — owns every egg lying around the world.

	Patch 4: spawning is PER-BIOME. Each biome keeps its own egg population
	(biome.MaxWorldEggs) drawn from its own egg list (biome.Eggs), at spawn
	points curated by its generator. The Desert only ever grows Sand Eggs.

	Collection is fully server-validated:
	  * ProximityPrompt.Triggered already fires ON THE SERVER
	  * we still re-check distance (a hacked client can fire prompts remotely)
	  * rate limit per player
	  * inventory capacity check (upgrades + rebirth bonus)
	Collected eggs go into data.EggInventory; the slot frees up and the loop
	spawns a replacement somewhere else in that biome.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local EggModels = require(ReplicatedStorage.EggModels)
local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Remotes)
local RollUtil = require(ReplicatedStorage.RollUtil)

local BiomeGenerator = require(script.Parent.BiomeGenerator)
local DataService = require(script.Parent.DataService)
local GoalService = require(script.Parent.GoalService)
local PlayerStats = require(script.Parent.PlayerStats)

local SPAWNING = GameConfig.EggSpawning

local EggSpawnService = {}

type WorldEgg = { Model: Model, EggType: string, Biome: string, PointIndex: number }

local worldEggs: { [Model]: WorldEgg } = {}
local biomeEggCount: { [string]: number } = {}
local occupiedPoints: { [string]: { [number]: boolean } } = {}
local lastCollectAt: { [Player]: number } = {}

-- QuestService plugs in here (Part 4) to count egg pickups toward quests
-- without a circular require.
local collectedCallback: ((Player, string) -> ())? = nil
function EggSpawnService.setCollectedCallback(callback: (Player, string) -> ())
	collectedCallback = callback
end

-- Tell one player their carried-egg situation changed (UI + optional toast)
function EggSpawnService.pushInventory(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	Remotes.EggInventoryUpdate:FireClient(player, {
		Inventory = data.EggInventory,
		Capacity = PlayerStats.getEggCapacity(player),
	})
end

local function onPromptTriggered(worldEgg: WorldEgg, player: Player)
	-- SECURITY CHECK 1: rate limit pickups
	local now = os.clock()
	local last = lastCollectAt[player]
	if last and now - last < GameConfig.RateLimits.CollectCooldownSeconds then
		return
	end
	lastCollectAt[player] = now

	-- SECURITY CHECK 2: the egg must still exist (double-trigger race)
	if not worldEggs[worldEgg.Model] then
		return
	end

	local data = DataService.get(player)
	if not data then
		return
	end

	-- SECURITY CHECK 3: player must genuinely be near the egg
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local eggPosition = worldEgg.Model:GetPivot().Position
	if (root.Position - eggPosition).Magnitude > SPAWNING.PickupMaxDistance then
		return
	end

	-- SECURITY CHECK 4: capacity (upgrades + rebirth bonus)
	local capacity = PlayerStats.getEggCapacity(player)
	if #data.EggInventory >= capacity then
		Remotes.Notify:FireClient(player, { Text = "Egg satchel full!", Kind = "Error" })
		return
	end

	-- All good: take it
	table.insert(data.EggInventory, worldEgg.EggType)

	worldEggs[worldEgg.Model] = nil
	occupiedPoints[worldEgg.Biome][worldEgg.PointIndex] = nil
	biomeEggCount[worldEgg.Biome] -= 1
	worldEgg.Model:Destroy()

	EggSpawnService.pushInventory(player)
	Remotes.Notify:FireClient(player, { Text = "+1 " .. worldEgg.EggType, Kind = "Pickup", EggType = worldEgg.EggType })
	GoalService.bump(player, "EggsCollected")
	if collectedCallback then
		collectedCallback(player, worldEgg.EggType)
	end
end

local function spawnOneEgg(biome, rng: Random)
	local points = BiomeGenerator.getEggSpawnPoints(biome.Name)
	if #points == 0 then
		return
	end

	local taken = occupiedPoints[biome.Name]
	local pointIndex
	for _ = 1, 12 do
		local candidate = rng:NextInteger(1, #points)
		if not taken[candidate] then
			pointIndex = candidate
			break
		end
	end
	if not pointIndex then
		return
	end

	-- This biome's own egg table (rarity-weighted within the biome)
	local eggType = RollUtil.rollEggTypeFrom(biome.Eggs, rng)
	local model = EggModels.createWorldEgg(eggType)
	model:PivotTo(CFrame.new(points[pointIndex]) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	CollectionService:AddTag(model, "WorldEgg")

	local worldEgg: WorldEgg = { Model = model, EggType = eggType, Biome = biome.Name, PointIndex = pointIndex }

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick Up"
	prompt.ObjectText = eggType
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = model.PrimaryPart
	prompt.Triggered:Connect(function(player)
		onPromptTriggered(worldEgg, player)
	end)

	taken[pointIndex] = true
	worldEggs[model] = worldEgg
	biomeEggCount[biome.Name] += 1
	model.Parent = workspace

	local eggDef = GameConfig.EggByName[eggType]
	if eggDef.Announce then
		Remotes.MythicAnnounce:FireAllClients({ EggType = eggType, Position = points[pointIndex] })
	end
end

function EggSpawnService.init()
	local rng = Random.new()
	for _, biome in GameConfig.Biomes do
		biomeEggCount[biome.Name] = 0
		occupiedPoints[biome.Name] = {}
	end

	Players.PlayerRemoving:Connect(function(player)
		lastCollectAt[player] = nil
	end)

	-- The spawn heartbeat: keep every biome topped up, one egg per tick each
	task.spawn(function()
		while true do
			for _, biome in GameConfig.Biomes do
				if biomeEggCount[biome.Name] < biome.MaxWorldEggs then
					spawnOneEgg(biome, rng)
				end
			end
			task.wait(SPAWNING.SpawnIntervalSeconds)
		end
	end)
end

return EggSpawnService
