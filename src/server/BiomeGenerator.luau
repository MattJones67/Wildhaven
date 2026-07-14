--[[
	BiomeGenerator — patch 4's new islands: Desert, Tundra, Volcanic, and
	the floating Sky Isles, each with its own terrain material, themed props,
	egg spawn points, sanctuary plot pads, a guide NPC, and a travel stone.

	It also adds the Forest's patch-4 furniture (travel hub by the village
	spawn, forest guide, forest sanctuary pads) — the Forest itself is still
	ForestGenerator's job.

	Everything is seeded and driven by GameConfig.Biomes, so islands are
	identical every server and positions are one-constant nudges.

	Exposes the lookups other services need:
	  getEggSpawnPoints(biome)  -> curated points (Forest delegates to ForestGenerator)
	  getTravelTarget(biome)    -> CFrame to teleport arrivals to
	  getTravelPillars()        -> { {Dest, Part} } for BiomeService to add prompts
	  getSanctuaryPlots(biome)  -> plot CFrames (SanctuaryService claims these)
	  getGuidePrompt(biome)     -> the NPC's ProximityPrompt (QuestService wires it)
	  getBiomeAt(position)      -> which biome a world position belongs to
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.GameConfig)
local ForestGenerator = require(script.Parent.ForestGenerator)

local BiomeGenerator = {}

local eggPoints: { [string]: { Vector3 } } = {}
local travelTargets: { [string]: CFrame } = {}
local travelPillars: { { Dest: string, Part: BasePart } } = {}
local sanctuaryPlots: { [string]: { CFrame } } = {}
local guidePrompts: { [string]: ProximityPrompt } = {}

-- ------------------------------------------------------------
-- Part helpers (same conventions as the other builders)
-- ------------------------------------------------------------

local function makePart(parent: Instance, props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = false
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = parent
	return part
end

local function makeBall(parent: Instance, size: Vector3, color: Color3, cframe: CFrame, material: Enum.Material?): Part
	local part = makePart(parent, {
		Size = size,
		Color = color,
		CFrame = cframe,
		Material = material or Enum.Material.SmoothPlastic,
		CanCollide = false,
		CanQuery = false,
	})
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

local function standingCylinder(parent: Instance, height: number, diameter: number, color: Color3, position: Vector3, material: Enum.Material?): Part
	local part = makePart(parent, {
		Size = Vector3.new(height, diameter, diameter),
		Color = color,
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Material = material or Enum.Material.SmoothPlastic,
	})
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- ------------------------------------------------------------
-- Shared furniture: sanctuary pads, guide NPCs, travel stones
-- ------------------------------------------------------------

local function buildSanctuaryPads(parent: Instance, biomeName: string, positions: { Vector3 })
	sanctuaryPlots[biomeName] = {}
	local half = GameConfig.Sanctuary.PlotHalfSize
	for _, pos in positions do
		makePart(parent, {
			Name = "SanctuaryPad",
			Size = Vector3.new(half * 2 + 2, 0.5, half * 2 + 2),
			Color = Color3.fromRGB(185, 178, 165),
			Material = Enum.Material.Slate,
			CFrame = CFrame.new(pos + Vector3.new(0, 0.25, 0)),
		})
		table.insert(sanctuaryPlots[biomeName], CFrame.new(pos + Vector3.new(0, 0.5, 0)))
	end
end

-- Ring of pad positions around a center (the common island layout)
local function padRing(center: Vector3, radius: number): { Vector3 }
	local positions = {}
	for i = 1, GameConfig.Sanctuary.PlotsPerBiome do
		local angle = (i / GameConfig.Sanctuary.PlotsPerBiome) * math.pi * 2 + math.pi / 4
		table.insert(positions, center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
	end
	return positions
end

local function buildGuideNPC(parent: Instance, biomeName: string, position: Vector3)
	local guide = GameConfig.Guides[biomeName]
	local biome = GameConfig.BiomeByName[biomeName]
	local npc = Instance.new("Model")
	npc.Name = "Guide_" .. biomeName

	local body = makeBall(npc, Vector3.new(1.6, 2.2, 1.3), biome.Color, CFrame.new(position + Vector3.new(0, 1.3, 0)))
	body.Name = "Body"
	body.CanQuery = true
	local headCF = CFrame.new(position + Vector3.new(0, 2.9, 0))
	makeBall(npc, Vector3.new(1.3, 1.2, 1.2), Color3.fromRGB(250, 225, 190), headCF)
	for _, side in { -1, 1 } do
		makeBall(npc, Vector3.new(0.3, 0.3, 0.2), Color3.new(1, 1, 1), headCF * CFrame.new(side * 0.25, 0.08, -0.5))
		makeBall(npc, Vector3.new(0.14, 0.14, 0.1), Color3.fromRGB(30, 30, 35), headCF * CFrame.new(side * 0.25, 0.08, -0.58))
	end
	-- Big friendly hat in the biome color
	standingCylinder(npc, 0.15, 2, biome.Color, position + Vector3.new(0, 3.45, 0)).CanCollide = false
	makeBall(npc, Vector3.new(1, 0.6, 1), biome.Color, CFrame.new(position + Vector3.new(0, 3.7, 0)))

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 130, 0, 32)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 4.6, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = body
	billboard.Parent = npc
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextScaled = true
	nameLabel.Text = biome.Emoji .. " " .. guide.Name
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.Parent = billboard
	local nameStroke = Instance.new("UIStroke")
	nameStroke.Color = Color3.fromRGB(20, 20, 25)
	nameStroke.Thickness = 2
	nameStroke.Parent = nameLabel

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Talk"
	prompt.ObjectText = guide.Name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = body
	guidePrompts[biomeName] = prompt

	npc.Parent = parent
end

-- A travel hub: one glowing pillar per DESTINATION biome. BiomeService
-- attaches the prompts + gate checks (this module only builds the parts).
local function buildTravelHub(parent: Instance, hereBiome: string, position: Vector3)
	local hub = Instance.new("Model")
	hub.Name = "TravelHub_" .. hereBiome
	standingCylinder(hub, 0.6, 9, Color3.fromRGB(200, 195, 185), position + Vector3.new(0, 0.3, 0), Enum.Material.Slate)
	local destinations = {}
	for _, biome in GameConfig.Biomes do
		if biome.Name ~= hereBiome then
			table.insert(destinations, biome)
		end
	end
	for i, biome in destinations do
		local angle = (i / #destinations) * math.pi * 2
		local pillarPos = position + Vector3.new(math.cos(angle) * 3.2, 0, math.sin(angle) * 3.2)
		makePart(hub, {
			Size = Vector3.new(1.2, 4.4, 1.2),
			Color = Color3.fromRGB(120, 115, 105),
			Material = Enum.Material.Slate,
			CFrame = CFrame.new(pillarPos + Vector3.new(0, 2.2, 0)),
		})
		local crystal = makePart(hub, {
			Name = "TravelCrystal",
			Size = Vector3.new(0.9, 1.3, 0.9),
			Color = biome.Color,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CFrame = CFrame.new(pillarPos + Vector3.new(0, 5, 0)) * CFrame.Angles(0, math.rad(45), math.rad(45)),
		})
		local light = Instance.new("PointLight")
		light.Color = biome.Color
		light.Brightness = 1.2
		light.Range = 10
		light.Parent = crystal
		table.insert(travelPillars, { Dest = biome.Name, Part = crystal })
	end
	hub.Parent = parent
end

-- ------------------------------------------------------------
-- Themed island builders
-- ------------------------------------------------------------

local function collectRingPoints(biomeName: string, center: Vector3, rng: Random, count: number, minR: number, maxR: number)
	eggPoints[biomeName] = eggPoints[biomeName] or {}
	for _ = 1, count do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(minR, maxR)
		table.insert(eggPoints[biomeName], center + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
	end
end

local function buildDesert(parent: Instance, biome, rng: Random)
	local c = biome.Center
	workspace.Terrain:FillCylinder(CFrame.new(c.X, -4, c.Z), 8, 100, Enum.Material.Sand)
	-- Dunes
	for _ = 1, 8 do
		local pos = c + Vector3.new(rng:NextNumber(-80, 80), 0, rng:NextNumber(-80, 80))
		workspace.Terrain:FillBall(pos + Vector3.new(0, -2, 0), rng:NextNumber(6, 12), Enum.Material.Sand)
	end
	-- Cacti: trunk + two arms
	for _ = 1, 10 do
		local pos = c + Vector3.new(rng:NextNumber(-85, 85), 0, rng:NextNumber(-85, 85))
		local height = rng:NextNumber(3, 5.5)
		local green = Color3.fromRGB(90, 155, 80)
		standingCylinder(parent, height, 1, green, pos + Vector3.new(0, height / 2, 0), Enum.Material.Grass)
		for _, side in { -1, 1 } do
			if rng:NextNumber() < 0.7 then
				standingCylinder(parent, height * 0.4, 0.7, green, pos + Vector3.new(side * 0.85, height * 0.55, 0), Enum.Material.Grass)
			end
		end
	end
	-- Ruins: weathered pillars + a fallen arch
	local ruins = c + Vector3.new(35, 0, -35)
	for i = 1, 5 do
		local angle = (i / 5) * math.pi * 2
		local height = rng:NextNumber(3, 7)
		standingCylinder(parent, height, 2, Color3.fromRGB(215, 190, 145), ruins + Vector3.new(math.cos(angle) * 8, height / 2, math.sin(angle) * 8), Enum.Material.Sandstone)
	end
	makePart(parent, {
		Size = Vector3.new(10, 1.5, 2),
		Color = Color3.fromRGB(215, 190, 145),
		Material = Enum.Material.Sandstone,
		CFrame = CFrame.new(ruins + Vector3.new(0, 7.5, 0)) * CFrame.Angles(0, math.rad(20), math.rad(6)),
	})
	collectRingPoints(biome.Name, c, rng, 10, 20, 80)
	table.insert(eggPoints[biome.Name], ruins + Vector3.new(0, 0, 4)) -- one by the ruins
end

local function buildTundra(parent: Instance, biome, rng: Random)
	local c = biome.Center
	workspace.Terrain:FillCylinder(CFrame.new(c.X, -4, c.Z), 8, 100, Enum.Material.Snow)
	for _ = 1, 3 do
		local pos = c + Vector3.new(rng:NextNumber(-60, 60), 0, rng:NextNumber(-60, 60))
		workspace.Terrain:FillCylinder(CFrame.new(pos.X, -0.3, pos.Z), 1, rng:NextNumber(8, 14), Enum.Material.Glacier)
	end
	-- Snowy pines: trunk + white-dusted blobs
	for _ = 1, 12 do
		local pos = c + Vector3.new(rng:NextNumber(-85, 85), 0, rng:NextNumber(-85, 85))
		local height = rng:NextNumber(4, 7)
		standingCylinder(parent, height, 1, Color3.fromRGB(105, 78, 58), pos + Vector3.new(0, height / 2, 0), Enum.Material.Wood)
		for layer = 0, 2 do
			local size = 5 - layer * 1.3
			makeBall(parent, Vector3.new(size, size * 0.6, size), Color3.fromRGB(70, 120, 95), CFrame.new(pos + Vector3.new(0, height + layer * 1.3, 0)), Enum.Material.Grass)
		end
		makeBall(parent, Vector3.new(2, 1, 2), Color3.fromRGB(240, 245, 250), CFrame.new(pos + Vector3.new(0, height + 3.2, 0)))
	end
	-- Ice spikes
	for _ = 1, 8 do
		local pos = c + Vector3.new(rng:NextNumber(-80, 80), 0, rng:NextNumber(-80, 80))
		local height = rng:NextNumber(3, 8)
		local spike = makeBall(parent, Vector3.new(1.6, height, 1.6), Color3.fromRGB(190, 230, 250), CFrame.new(pos + Vector3.new(0, height / 2, 0)) * CFrame.Angles(rng:NextNumber(-0.1, 0.1), 0, rng:NextNumber(-0.1, 0.1)), Enum.Material.Ice)
		spike.Transparency = 0.2
	end
	collectRingPoints(biome.Name, c, rng, 11, 20, 80)
end

local function buildVolcanic(parent: Instance, biome, rng: Random)
	local c = biome.Center
	workspace.Terrain:FillCylinder(CFrame.new(c.X, -4, c.Z), 8, 90, Enum.Material.Basalt)
	-- Lava pools (bright, glowing terrain)
	for _ = 1, 4 do
		local pos = c + Vector3.new(rng:NextNumber(-60, 60), 0, rng:NextNumber(-60, 60))
		workspace.Terrain:FillCylinder(CFrame.new(pos.X, -0.6, pos.Z), 1.4, rng:NextNumber(6, 10), Enum.Material.CrackedLava)
	end
	-- Obsidian spikes + dark boulders
	for _ = 1, 10 do
		local pos = c + Vector3.new(rng:NextNumber(-75, 75), 0, rng:NextNumber(-75, 75))
		local height = rng:NextNumber(4, 9)
		makeBall(parent, Vector3.new(2, height, 2), Color3.fromRGB(45, 42, 48), CFrame.new(pos + Vector3.new(0, height / 2, 0)) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.15, 0.15)), Enum.Material.Slate)
	end
	-- Ember vents: cracks with fire + drifting sparks
	for _ = 1, 5 do
		local pos = c + Vector3.new(rng:NextNumber(-65, 65), 0, rng:NextNumber(-65, 65))
		local vent = makePart(parent, {
			Size = Vector3.new(2.4, 0.6, 2.4),
			Color = Color3.fromRGB(70, 60, 60),
			Material = Enum.Material.Slate,
			CFrame = CFrame.new(pos + Vector3.new(0, 0.3, 0)),
		})
		local fire = Instance.new("Fire")
		fire.Size = 4
		fire.Parent = vent
		local sparks = Instance.new("ParticleEmitter")
		sparks.Color = ColorSequence.new(Color3.fromRGB(255, 150, 60))
		sparks.LightEmission = 1
		sparks.Rate = 4
		sparks.Lifetime = NumberRange.new(1, 2)
		sparks.Speed = NumberRange.new(3, 6)
		sparks.Size = NumberSequence.new(0.15)
		sparks.Parent = vent
	end
	collectRingPoints(biome.Name, c, rng, 10, 18, 70)
end

local function buildSky(parent: Instance, biome, rng: Random)
	local c = biome.Center -- floats at Y = 150
	-- Three floating grass discs joined by plank bridges
	local discs = {
		{ Offset = Vector3.zero, Radius = 45 },
		{ Offset = Vector3.new(70, 8, 25), Radius = 26 },
		{ Offset = Vector3.new(-60, -6, -30), Radius = 22 },
	}
	for _, disc in discs do
		local center = c + disc.Offset
		workspace.Terrain:FillCylinder(CFrame.new(center.X, center.Y - 3, center.Z), 6, disc.Radius, Enum.Material.Grass)
		-- Rocky underside so islands don't look like pancakes
		workspace.Terrain:FillBall(center - Vector3.new(0, 8, 0), disc.Radius * 0.55, Enum.Material.Rock)
		-- Cloud puffs drifting around the rim
		for _ = 1, 4 do
			local angle = rng:NextNumber(0, math.pi * 2)
			local puff = makeBall(parent, Vector3.new(8, 3.5, 8), Color3.fromRGB(250, 250, 255),
				CFrame.new(center + Vector3.new(math.cos(angle) * (disc.Radius + 6), rng:NextNumber(-4, 2), math.sin(angle) * (disc.Radius + 6))))
			puff.Transparency = 0.35
		end
	end
	-- Bridges between main disc and satellites
	for _, target in { discs[2], discs[3] } do
		local fromPos = c + (target.Offset.Unit * 40) + Vector3.new(0, 0.4, 0)
		local toPos = c + target.Offset - (target.Offset.Unit * (target.Radius - 3)) + Vector3.new(0, target.Offset.Y > 0 and 0.4 or 0.4, 0)
		local span = toPos - fromPos
		local segments = math.max(4, math.floor(span.Magnitude / 2.4))
		for i = 0, segments do
			local t = i / segments
			makePart(parent, {
				Size = Vector3.new(3, 0.35, 2.2),
				Color = Color3.fromRGB(150, 108, 70),
				Material = Enum.Material.Wood,
				CFrame = CFrame.lookAt(fromPos:Lerp(toPos, t), toPos),
			})
		end
	end
	-- Floating crystals for sparkle
	for _ = 1, 6 do
		local pos = c + Vector3.new(rng:NextNumber(-40, 40), rng:NextNumber(4, 12), rng:NextNumber(-40, 40))
		local crystal = makePart(parent, {
			Size = Vector3.new(1, 1.6, 1),
			Color = Color3.fromRGB(190, 215, 255),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(45), rng:NextNumber(0, 3), math.rad(45)),
		})
		crystal.Transparency = 0.25
	end
	collectRingPoints(biome.Name, c, rng, 8, 8, 38)
	-- A couple of points on the satellite discs
	table.insert(eggPoints[biome.Name], c + discs[2].Offset)
	table.insert(eggPoints[biome.Name], c + discs[3].Offset)
end

-- ------------------------------------------------------------
-- Public API
-- ------------------------------------------------------------

function BiomeGenerator.getEggSpawnPoints(biomeName: string): { Vector3 }
	if biomeName == "Forest" then
		return ForestGenerator.getEggSpawnPoints()
	end
	return eggPoints[biomeName] or {}
end

function BiomeGenerator.getTravelTarget(biomeName: string): CFrame?
	return travelTargets[biomeName]
end

function BiomeGenerator.getTravelPillars(): { { Dest: string, Part: BasePart } }
	return travelPillars
end

function BiomeGenerator.getSanctuaryPlots(biomeName: string): { CFrame }
	return sanctuaryPlots[biomeName] or {}
end

function BiomeGenerator.getGuidePrompt(biomeName: string): ProximityPrompt?
	return guidePrompts[biomeName]
end

-- Which biome does a world position belong to? (nearest island center)
function BiomeGenerator.getBiomeAt(position: Vector3): string
	local bestName, bestDistance = "Forest", math.huge
	for _, biome in GameConfig.Biomes do
		local distance = (Vector3.new(position.X, 0, position.Z) - Vector3.new(biome.Center.X, 0, biome.Center.Z)).Magnitude
		if distance < bestDistance then
			bestName, bestDistance = biome.Name, distance
		end
	end
	return bestName
end

-- Called BEFORE any island generates: the ocean floor everything sits in.
-- (Island fills overwrite water; filling water later would flood them.)
function BiomeGenerator.buildOcean()
	workspace.Terrain:FillBlock(CFrame.new(0, -6, 0), Vector3.new(1700, 8, 1700), Enum.Material.Water)
end

function BiomeGenerator.build()
	local rng = Random.new(GameConfig.Forest.Seed + 4) -- patch-4 furniture seed
	local islands = Instance.new("Model")
	islands.Name = "Biomes"

	local builders = {
		Desert = buildDesert,
		Tundra = buildTundra,
		Volcanic = buildVolcanic,
		Sky = buildSky,
	}

	for _, biome in GameConfig.Biomes do
		local buildIsland = builders[biome.Name]
		if buildIsland then
			buildIsland(islands, biome, rng)
		end
		-- Arrival point: island edge closest to the Forest (or village spawn)
		if biome.Name == "Forest" then
			travelTargets.Forest = CFrame.new(Vector3.new(0, 3, 12))
			buildTravelHub(islands, "Forest", Vector3.new(16, 0, 20)) -- beside the village spawn
			buildGuideNPC(islands, "Forest", Vector3.new(-10, 0, 16)) -- near the well
			buildSanctuaryPads(islands, "Forest", padRing(Vector3.zero, 92))
		elseif biome.Name == "Sky" then
			-- The Sky main disc only fits ONE pad (its satellites are small)
			local edge = biome.Center + Vector3.new(0, 0, 30)
			travelTargets.Sky = CFrame.new(edge + Vector3.new(0, 3, 0))
			buildTravelHub(islands, "Sky", edge + Vector3.new(8, 0, 0))
			buildGuideNPC(islands, "Sky", edge + Vector3.new(-8, 0, -2))
			buildSanctuaryPads(islands, "Sky", { biome.Center + Vector3.new(0, 0, -18) })
		else
			local toOrigin = (Vector3.new(0, 0, 0) - biome.Center) * Vector3.new(1, 0, 1)
			local edge = biome.Center + toOrigin.Unit * 20
			travelTargets[biome.Name] = CFrame.new(edge + Vector3.new(0, 3, 0))
			buildTravelHub(islands, biome.Name, edge + Vector3.new(6, 0, 6))
			buildGuideNPC(islands, biome.Name, edge + Vector3.new(-8, 0, 4))
			buildSanctuaryPads(islands, biome.Name, padRing(biome.Center, 58))
		end
	end

	islands.Parent = workspace
end

return BiomeGenerator
