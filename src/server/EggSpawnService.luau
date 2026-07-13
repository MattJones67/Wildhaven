--[[
	EggSpawnService — owns every egg lying around the island.

	Loop: keep up to MaxWorldEggs alive. Every SpawnIntervalSeconds, if
	there's room, roll an egg type (rarity-weighted), pick a free spawn
	point (from ForestGenerator's curated list), and place an egg there
	with a ProximityPrompt. Mythic Eggs get announced server-wide.

	Collection is fully server-validated:
	  * ProximityPrompt.Triggered already fires ON THE SERVER
	  * we still re-check distance (a hacked client can fire prompts remotely)
	  * rate limit per player
	  * inventory capacity check (EggCapacity upgrade)
	Collected eggs go into data.EggInventory; the world slot frees up and
	the loop will spawn a replacement somewhere else.
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
local ForestGenerator = require(script.Parent.ForestGenerator)

local SPAWNING = GameConfig.EggSpawning

local EggSpawnService = {}

type WorldEgg = { Model: Model, EggType: string, PointIndex: number }

local worldEggs: { [Model]: WorldEgg } = {}
local worldEggCount = 0
local occupiedPoints: { [number]: boolean } = {}
local lastCollectAt: { [Player]: number } = {}

-- Tell one player their carried-egg situation changed (UI + optional toast)
function EggSpawnService.pushInventory(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	Remotes.EggInventoryUpdate:FireClient(player, {
		Inventory = data.EggInventory,
		Capacity = BaseUpgradeService.getEggCapacity(player),
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

	-- SECURITY CHECK 3: player must genuinely be near the egg — exploited
	-- clients can fire prompts from across the map
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local eggPosition = worldEgg.Model:GetPivot().Position
	if (root.Position - eggPosition).Magnitude > SPAWNING.PickupMaxDistance then
		return
	end

	-- SECURITY CHECK 4: capacity (upgradeable via EggCapacity)
	local capacity = BaseUpgradeService.getEggCapacity(player)
	if #data.EggInventory >= capacity then
		Remotes.Notify:FireClient(player, { Text = "Egg satchel full!", Kind = "Error" })
		return
	end

	-- All good: take it
	table.insert(data.EggInventory, worldEgg.EggType)

	worldEggs[worldEgg.Model] = nil
	occupiedPoints[worldEgg.PointIndex] = nil
	worldEggCount -= 1
	worldEgg.Model:Destroy()

	EggSpawnService.pushInventory(player)
	Remotes.Notify:FireClient(player, { Text = "+1 " .. worldEgg.EggType, Kind = "Pickup", EggType = worldEgg.EggType })
end

local function spawnOneEgg(rng: Random)
	local points = ForestGenerator.getEggSpawnPoints()
	if #points == 0 then
		return
	end

	-- Pick a free spawn point (a few tries, then give up until next tick)
	local pointIndex
	for _ = 1, 12 do
		local candidate = rng:NextInteger(1, #points)
		if not occupiedPoints[candidate] then
			pointIndex = candidate
			break
		end
	end
	if not pointIndex then
		return
	end

	local eggType = RollUtil.rollEggType(rng)
	local model = EggModels.create(eggType)
	model:PivotTo(CFrame.new(points[pointIndex]) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	CollectionService:AddTag(model, "WorldEgg") -- client bobs/spins tagged eggs

	local worldEgg: WorldEgg = { Model = model, EggType = eggType, PointIndex = pointIndex }

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Pick Up"
	prompt.ObjectText = eggType
	prompt.HoldDuration = 0 -- instant tap; mobile-friendly
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = model.PrimaryPart
	prompt.Triggered:Connect(function(player)
		onPromptTriggered(worldEgg, player)
	end)

	occupiedPoints[pointIndex] = true
	worldEggs[model] = worldEgg
	worldEggCount += 1
	model.Parent = workspace

	-- A Mythic Egg appearing is a server-wide event
	local eggDef = GameConfig.EggByName[eggType]
	if eggDef.Announce then
		Remotes.MythicAnnounce:FireAllClients({ EggType = eggType, Position = points[pointIndex] })
	end
end

function EggSpawnService.init()
	local rng = Random.new()

	Players.PlayerRemoving:Connect(function(player)
		lastCollectAt[player] = nil
	end)

	-- The spawn heartbeat: top the island up to the cap, one egg at a time
	task.spawn(function()
		while true do
			if worldEggCount < SPAWNING.MaxWorldEggs then
				spawnOneEgg(rng)
			end
			task.wait(SPAWNING.SpawnIntervalSeconds)
		end
	end)
end

return EggSpawnService
