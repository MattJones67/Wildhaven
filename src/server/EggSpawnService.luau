--[[
	EggSpawnService — owns every egg lying around the world.

	Spawning is PER-BIOME (patch 4): each biome keeps its own egg population
	(biome.MaxWorldEggs) drawn from its own egg list (biome.Eggs).

	PATCH 6: collecting is no longer instant — it's a timed SKILL-CHECK.
	Pressing the prompt starts a server-owned session:

	  * the SERVER generates the minigame (marker speed, zone size, zone
	    positions, required hits) from the egg's difficulty tier
	  * marker position is pure math on the SHARED server clock
	    (workspace:GetServerTimeNow()), so both sides compute identically:
	        position(t) = ((t - startAt) * speed) % 1
	  * the client sends each tap's clock time; the SERVER recomputes
	    hit/miss itself — a client saying "I got a perfect!" is ignored,
	    only its tap TIMES matter (and those are sanity-checked: monotonic,
	    not in the future, minimum spacing, player still near the egg)
	  * misses = CRACKS. The egg is never lost — cracks only shrink the
	    quality bonus:  Quality = 1 - cracks * CrackPenalty  (floor 0)
	  * quality rides on the carried egg {Type, Quality} and boosts
	    mutation/size odds when HatchService rolls it later

	The egg's prompt is disabled during a session (one collector at a time);
	abandoning, dying, or timing out frees it for everyone else.
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
local SKILL = GameConfig.SkillCheck

local EggSpawnService = {}

type WorldEgg = { Model: Model, EggType: string, Biome: string, PointIndex: number, Prompt: ProximityPrompt? }

type Session = {
	WorldEgg: WorldEgg,
	StartAt: number, -- shared server-clock moment the marker starts
	Speed: number,
	ZoneSize: number,
	Zones: { number }, -- zone start positions, indexed by tap number
	Required: number,
	Successes: number,
	Cracks: number,
	Taps: number,
	LastTapAt: number,
	Token: number, -- identity for the timeout guard
}

local worldEggs: { [Model]: WorldEgg } = {}
local biomeEggCount: { [string]: number } = {}
local occupiedPoints: { [string]: { [number]: boolean } } = {}
local lastCollectAt: { [Player]: number } = {}
local sessions: { [Player]: Session } = {}
local nextToken = 0

local rng = Random.new()

-- QuestService plugs in here (patch 4) to count egg pickups toward quests.
local collectedCallback: ((Player, string) -> ())? = nil
function EggSpawnService.setCollectedCallback(callback: (Player, string) -> ())
	collectedCallback = callback
end

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

-- ------------------------------------------------------------
-- Skill-check sessions
-- ------------------------------------------------------------

local function playerNearEgg(player: Player, worldEgg: WorldEgg, slack: number): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or worldEgg.Model.Parent == nil then
		return false
	end
	return (root.Position - worldEgg.Model:GetPivot().Position).Magnitude <= SPAWNING.PickupMaxDistance + slack
end

local function endSession(player: Player, notifyCancel: boolean)
	local session = sessions[player]
	if not session then
		return
	end
	sessions[player] = nil
	-- Re-open the egg for everyone (if it still exists and wasn't collected)
	if worldEggs[session.WorldEgg.Model] and session.WorldEgg.Prompt then
		session.WorldEgg.Prompt.Enabled = true
	end
	if notifyCancel then
		Remotes.EggSkillResult:FireClient(player, { Canceled = true })
	end
end

-- The successful (or crack-capped) finish: the player ALWAYS gets the egg.
local function finishSession(player: Player, session: Session)
	sessions[player] = nil
	local worldEgg = session.WorldEgg
	if not worldEggs[worldEgg.Model] then
		return -- egg vanished mid-game (shouldn't happen; be safe)
	end
	local data = DataService.get(player)
	if not data then
		endSession(player, true)
		return
	end
	-- Capacity re-check (it was pre-checked, but income/time passed)
	if #data.EggInventory >= PlayerStats.getEggCapacity(player) then
		Remotes.Notify:FireClient(player, { Text = "Egg satchel full!", Kind = "Error" })
		Remotes.EggSkillResult:FireClient(player, { Canceled = true })
		if worldEgg.Prompt then
			worldEgg.Prompt.Enabled = true
		end
		return
	end

	-- Quality from cracks: clean run = big hatch bonus, butchered = baseline
	local quality = math.clamp(1 - session.Cracks * SKILL.CrackPenalty, 0, 1)
	table.insert(data.EggInventory, { Type = worldEgg.EggType, Quality = quality })

	worldEggs[worldEgg.Model] = nil
	occupiedPoints[worldEgg.Biome][worldEgg.PointIndex] = nil
	biomeEggCount[worldEgg.Biome] -= 1
	worldEgg.Model:Destroy()

	EggSpawnService.pushInventory(player)
	Remotes.EggSkillResult:FireClient(player, {
		Collected = true,
		EggType = worldEgg.EggType,
		Cracks = session.Cracks,
		Quality = quality,
	})
	Remotes.Notify:FireClient(player, { Text = "+1 " .. worldEgg.EggType, Kind = "Pickup", EggType = worldEgg.EggType })
	GoalService.bump(player, "EggsCollected")
	if collectedCallback then
		collectedCallback(player, worldEgg.EggType)
	end
end

local function onPromptTriggered(worldEgg: WorldEgg, player: Player)
	-- SECURITY CHECK 1: rate limit session starts
	local now = os.clock()
	local last = lastCollectAt[player]
	if last and now - last < GameConfig.RateLimits.CollectCooldownSeconds then
		return
	end
	lastCollectAt[player] = now

	-- SECURITY CHECK 2: egg still exists, nobody's mid-game on it, and
	-- this player isn't already collecting something else
	if not worldEggs[worldEgg.Model] or sessions[player] then
		return
	end
	local data = DataService.get(player)
	if not data then
		return
	end
	-- SECURITY CHECK 3: genuinely near the egg
	if not playerNearEgg(player, worldEgg, 0) then
		return
	end
	-- SECURITY CHECK 4: room in the satchel (soft pre-check)
	if #data.EggInventory >= PlayerStats.getEggCapacity(player) then
		Remotes.Notify:FireClient(player, { Text = "Egg satchel full!", Kind = "Error" })
		return
	end

	-- Build the minigame from the egg's difficulty tier — the SERVER
	-- decides speed/zones/hits; the client only renders them.
	local tier = SKILL.Tiers[SKILL.EggTiers[worldEgg.EggType] or 1]
	-- Zones never spill past the bar's end, so what the client DRAWS is
	-- exactly what the server judges
	local zones = {}
	for _ = 1, tier.Hits + SKILL.MaxCracks do
		table.insert(zones, rng:NextNumber(0.05, 0.97 - tier.ZoneSize))
	end
	nextToken += 1
	local session: Session = {
		WorldEgg = worldEgg,
		StartAt = workspace:GetServerTimeNow() + SKILL.LeadInSeconds,
		Speed = tier.Speed,
		ZoneSize = tier.ZoneSize,
		Zones = zones,
		Required = tier.Hits,
		Successes = 0,
		Cracks = 0,
		Taps = 0,
		LastTapAt = 0,
		Token = nextToken,
	}
	sessions[player] = session

	-- Lock the egg: one collector at a time
	if worldEgg.Prompt then
		worldEgg.Prompt.Enabled = false
	end

	Remotes.EggSkillStart:FireClient(player, {
		Egg = worldEgg.Model,
		EggType = worldEgg.EggType,
		StartAt = session.StartAt,
		Speed = session.Speed,
		ZoneSize = session.ZoneSize,
		Zones = session.Zones,
		Required = session.Required,
		MaxCracks = SKILL.MaxCracks,
	})

	-- Walk-away / AFK timeout frees the egg
	local token = session.Token
	task.delay(SKILL.TimeoutSeconds, function()
		local current = sessions[player]
		if current and current.Token == token then
			endSession(player, true)
		end
	end)
end

-- A tap arrived. The client already showed its own predicted hit/miss for
-- responsiveness — but THIS is the judgment that counts.
local function onSkillTap(player: Player, tapTime: any)
	local session = sessions[player]
	if not session then
		return
	end
	-- SECURITY: tap time must be sane on the SHARED clock
	if typeof(tapTime) ~= "number" or tapTime ~= tapTime then
		return
	end
	local now = workspace:GetServerTimeNow()
	if tapTime < session.StartAt -- before the marker even started
		or tapTime > now + 0.05 -- claims to be from the future
		or tapTime < now - 3 -- suspiciously stale
		or tapTime < session.LastTapAt + SKILL.TapMinInterval then -- tap spam
		return
	end
	-- SECURITY: still standing at the egg (with a little chase slack)
	if not playerNearEgg(player, session.WorldEgg, 6) then
		endSession(player, true)
		return
	end

	session.LastTapAt = tapTime
	session.Taps += 1

	-- The exact same math the client used to draw the marker
	local position = ((tapTime - session.StartAt) * session.Speed) % 1
	local zoneStart = session.Zones[math.min(session.Taps, #session.Zones)]
	local inZone = ((position - zoneStart) % 1) <= session.ZoneSize + SKILL.ZoneTolerance

	if inZone then
		session.Successes += 1
	else
		session.Cracks += 1
	end

	if session.Successes >= session.Required then
		finishSession(player, session)
	elseif session.Cracks >= SKILL.MaxCracks then
		-- Quality is already zero — hand the (very cracked) egg over.
		-- TODO(hardcore): a "shatter" mode would end WITHOUT the egg here.
		finishSession(player, session)
	end
end

-- ------------------------------------------------------------
-- Spawning (unchanged from patch 4/5 apart from the prompt handle)
-- ------------------------------------------------------------

local function spawnOneEgg(biome, spawnRng: Random)
	local points = BiomeGenerator.getEggSpawnPoints(biome.Name)
	if #points == 0 then
		return
	end

	local taken = occupiedPoints[biome.Name]
	local pointIndex
	for _ = 1, 12 do
		local candidate = spawnRng:NextInteger(1, #points)
		if not taken[candidate] then
			pointIndex = candidate
			break
		end
	end
	if not pointIndex then
		return
	end

	local eggType = RollUtil.rollEggTypeFrom(biome.Eggs, spawnRng)
	local model = EggModels.createWorldEgg(eggType)
	model:PivotTo(CFrame.new(points[pointIndex]) * CFrame.Angles(0, spawnRng:NextNumber(0, math.pi * 2), 0))
	CollectionService:AddTag(model, "WorldEgg")

	local worldEgg: WorldEgg = { Model = model, EggType = eggType, Biome = biome.Name, PointIndex = pointIndex }

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Collect"
	prompt.ObjectText = eggType
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 9
	prompt.RequiresLineOfSight = false
	prompt.Parent = model.PrimaryPart
	worldEgg.Prompt = prompt
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
	local spawnRng = Random.new()
	for _, biome in GameConfig.Biomes do
		biomeEggCount[biome.Name] = 0
		occupiedPoints[biome.Name] = {}
	end

	Remotes.EggSkillTap.OnServerEvent:Connect(onSkillTap)
	Remotes.EggSkillCancel.OnServerEvent:Connect(function(player)
		endSession(player, false) -- they closed the UI themselves
	end)

	Players.PlayerRemoving:Connect(function(player)
		endSession(player, false)
		lastCollectAt[player] = nil
	end)

	task.spawn(function()
		while true do
			for _, biome in GameConfig.Biomes do
				if biomeEggCount[biome.Name] < biome.MaxWorldEggs then
					spawnOneEgg(biome, spawnRng)
				end
			end
			task.wait(SPAWNING.SpawnIntervalSeconds)
		end
	end)
end

return EggSpawnService
