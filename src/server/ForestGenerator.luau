--[[
	ForestGenerator — procedurally builds the whole Forest island at server
	start: voxel Terrain (island, beach, river, pond, dirt paths), clustered
	trees and foliage, landmarks (via LandmarkBuilder), and atmosphere.

	Everything is driven by GameConfig.Forest with a fixed Seed, so the same
	island generates every time — tweak a number, regenerate, compare.
	Landmark positions are plain constants in the config: nudge them freely.

	It also produces the two lists other systems need:
	  * getEggSpawnPoints() — sensible spots for world eggs
	  * getCabinPlots()     — CFrames of the village cabins (player bases)
]]

local Lighting = game:GetService("Lighting")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.GameConfig)
local LandmarkBuilder = require(script.Parent.LandmarkBuilder)
local TerrainForge = require(script.Parent.TerrainForge)

local FOREST = GameConfig.Forest

local ForestGenerator = {}

local eggSpawnPoints: { Vector3 } = {}
local cabinPlots: { CFrame } = {}

-- ------------------------------------------------------------
-- Geometry helpers
-- ------------------------------------------------------------

local function flat(v: Vector3): Vector2
	return Vector2.new(v.X, v.Z)
end

-- Distance from point P to the segment A-B (all in flat XZ space)
local function distToSegment(p: Vector2, a: Vector2, b: Vector2): number
	local ab = b - a
	local t = math.clamp((p - a):Dot(ab) / ab:Dot(ab), 0, 1)
	return (p - (a + ab * t)).Magnitude
end

local function distToPolyline(p: Vector2, points: { Vector2 }): number
	local best = math.huge
	for i = 1, #points - 1 do
		best = math.min(best, distToSegment(p, points[i], points[i + 1]))
	end
	return best
end

-- Is this spot free of landmarks / water / paths? Used before planting
-- anything, so trees never grow through the campfire.
local function isBlocked(pos: Vector3): boolean
	local p = flat(pos)
	if p.Magnitude > FOREST.IslandRadius - 10 then
		return true -- too close to the shore
	end
	if (p - flat(FOREST.VillageCenter)).Magnitude < FOREST.VillageRadius + 12 then
		return true
	end
	if (p - flat(FOREST.TreehousePosition)).Magnitude < 16 then
		return true
	end
	if (p - flat(FOREST.PondCenter)).Magnitude < FOREST.PondRadius + 6 then
		return true
	end
	if distToPolyline(p, FOREST.RiverPoints) < FOREST.RiverWidth + 5 then
		return true
	end
	for _, path in FOREST.Paths do
		if distToPolyline(p, path) < FOREST.PathWidth + 3 then
			return true
		end
	end
	return false
end

-- A random unblocked point in the forest, WITH its true ground height
-- (the continent rework means the outer forest rolls into hills).
local function randomOpenPoint(rng: Random, maxRadius: number?): Vector3?
	for _ = 1, 30 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = math.sqrt(rng:NextNumber()) * (maxRadius or FOREST.IslandRadius - 14)
		local x, z = math.cos(angle) * radius, math.sin(angle) * radius
		local pos = Vector3.new(x, 0, z)
		if not isBlocked(pos) then
			local height = TerrainForge.getHeightAt(x, z)
			if height > 0.5 or radius < 170 then -- skip beach/waterline spots
				return Vector3.new(x, math.max(height, 0), z)
			end
		end
	end
	return nil
end

-- ------------------------------------------------------------
-- Terrain: ocean, island, beach, pond, river, dirt paths
-- ------------------------------------------------------------

local function generateTerrain()
	local terrain = workspace.Terrain

	-- (The continent ground itself comes from TerrainForge, which runs
	-- BEFORE this. Here we only carve the forest's water features and
	-- paths into that ground — all inside the flat village core.)

	-- Pond: carve a hole, part-fill with water
	local pond = FOREST.PondCenter
	terrain:FillCylinder(CFrame.new(pond.X, 0.5, pond.Z), 6, FOREST.PondRadius, Enum.Material.Air)
	terrain:FillCylinder(CFrame.new(pond.X, -2.2, pond.Z), 3, FOREST.PondRadius - 1, Enum.Material.Water)

	-- River: carve a channel along the polyline, then lay water in it
	local riverPoints = FOREST.RiverPoints
	for i = 1, #riverPoints - 1 do
		local a, b = riverPoints[i], riverPoints[i + 1]
		local length = (b - a).Magnitude
		local steps = math.ceil(length / 4)
		for step = 0, steps do
			local p = a:Lerp(b, step / steps)
			terrain:FillBlock(CFrame.new(p.X, 0.6, p.Y), Vector3.new(FOREST.RiverWidth + 5, 5, 6), Enum.Material.Air)
			terrain:FillBlock(CFrame.new(p.X, -1.8, p.Y), Vector3.new(FOREST.RiverWidth, 2.5, 6), Enum.Material.Water)
		end
	end

	-- Dirt paths: paint strips of Ground along each path polyline
	for _, path in FOREST.Paths do
		for i = 1, #path - 1 do
			local a, b = path[i], path[i + 1]
			local length = (b - a).Magnitude
			local steps = math.ceil(length / 3)
			for step = 0, steps do
				local p = a:Lerp(b, step / steps)
				terrain:FillCylinder(CFrame.new(p.X, -0.4, p.Y), 1.5, FOREST.PathWidth, Enum.Material.Ground)
			end
		end
	end
end

-- ------------------------------------------------------------
-- Flora & scatter (all primitive parts, clustered not sprinkled)
-- ------------------------------------------------------------

local function makePart(parent: Instance, props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = false -- hundreds of foliage parts; shadows cost too much
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

-- Three tree species so copses read as a real mixed forest:
-- round oaks, tall dark pines, and pale birches with amber crowns.
local TREE_PALETTES = {
	Oak = {
		Trunk = Color3.fromRGB(115, 82, 58),
		Leaves = { Color3.fromRGB(88, 158, 82), Color3.fromRGB(104, 176, 90), Color3.fromRGB(76, 145, 76) },
	},
	Pine = {
		Trunk = Color3.fromRGB(95, 66, 48),
		Leaves = { Color3.fromRGB(52, 110, 78), Color3.fromRGB(60, 122, 84), Color3.fromRGB(46, 98, 70) },
	},
	Birch = {
		Trunk = Color3.fromRGB(215, 210, 200),
		Leaves = { Color3.fromRGB(170, 175, 80), Color3.fromRGB(195, 165, 75), Color3.fromRGB(150, 160, 72) },
	},
}

local function buildTree(parent: Instance, position: Vector3, rng: Random)
	local roll = rng:NextNumber()
	local species = roll < 0.5 and "Oak" or roll < 0.8 and "Pine" or "Birch"
	local palette = TREE_PALETTES[species]
	local scale = rng:NextNumber(0.7, species == "Pine" and 2 or 1.6)
	local trunkHeight = (species == "Pine" and 9 or 6) * scale

	standingCylinder(parent, trunkHeight, (species == "Birch" and 1 or 1.4) * scale, palette.Trunk,
		position + Vector3.new(0, trunkHeight / 2, 0), Enum.Material.Wood)

	if species == "Pine" then
		-- Stacked shrinking cones (fat balls) up the trunk
		for layer = 0, 3 do
			local blobSize = (6.5 - layer * 1.4) * scale
			makeBall(parent, Vector3.new(blobSize, blobSize * 0.75, blobSize), palette.Leaves[layer % 3 + 1],
				CFrame.new(position + Vector3.new(0, trunkHeight * 0.55 + layer * 2.2 * scale, 0)), Enum.Material.Grass)
		end
	else
		for i, color in palette.Leaves do
			local offset = Vector3.new(rng:NextNumber(-1.8, 1.8), trunkHeight + (i - 1) * 1.4 * scale, rng:NextNumber(-1.8, 1.8))
			local blobSize = (6 - i) * scale + 1.5
			makeBall(parent, Vector3.new(blobSize, blobSize * 0.8, blobSize), color, CFrame.new(position + offset), Enum.Material.Grass)
		end
	end
end

local function buildRock(parent: Instance, position: Vector3, rng: Random, big: boolean)
	local size = big and rng:NextNumber(3, 5.5) or rng:NextNumber(1, 2.4)
	makeBall(parent, Vector3.new(size, size * rng:NextNumber(0.5, 0.75), size * rng:NextNumber(0.8, 1.2)),
		Color3.fromRGB(145, 145, 150), CFrame.new(position + Vector3.new(0, size * 0.2, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
		Enum.Material.Slate)
end

local function buildBush(parent: Instance, position: Vector3, rng: Random)
	local size = rng:NextNumber(2, 3.5)
	makeBall(parent, Vector3.new(size, size * 0.7, size), Color3.fromRGB(70, 140, 70),
		CFrame.new(position + Vector3.new(0, size * 0.3, 0)), Enum.Material.Grass)
	makeBall(parent, Vector3.new(size * 0.7, size * 0.55, size * 0.7), Color3.fromRGB(90, 160, 80),
		CFrame.new(position + Vector3.new(rng:NextNumber(-0.8, 0.8), size * 0.5, rng:NextNumber(-0.8, 0.8))), Enum.Material.Grass)
end

local function buildFern(parent: Instance, position: Vector3, rng: Random)
	for i = 1, 4 do
		local angle = (i / 4) * math.pi * 2 + rng:NextNumber(0, 1)
		makeBall(parent, Vector3.new(0.25, 1.4, 0.7), Color3.fromRGB(65, 150, 85),
			CFrame.new(position + Vector3.new(0, 0.6, 0))
				* CFrame.Angles(0, angle, math.rad(35))
				* CFrame.new(0, 0.3, -0.35))
	end
end

local function buildMushroom(parent: Instance, position: Vector3, rng: Random)
	local height = rng:NextNumber(0.6, 1.4)
	standingCylinder(parent, height, 0.35, Color3.fromRGB(235, 225, 205), position + Vector3.new(0, height / 2, 0))
	local capColor = rng:NextNumber() < 0.5 and Color3.fromRGB(210, 80, 70) or Color3.fromRGB(230, 180, 120)
	makeBall(parent, Vector3.new(height * 1.1, height * 0.55, height * 1.1), capColor, CFrame.new(position + Vector3.new(0, height, 0)))
end

local function buildFallenLog(parent: Instance, position: Vector3, rng: Random)
	local length = rng:NextNumber(5, 9)
	local log = makePart(parent, {
		Size = Vector3.new(length, 1.6, 1.6),
		Color = Color3.fromRGB(100, 72, 50),
		CFrame = CFrame.new(position + Vector3.new(0, 0.7, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
		Material = Enum.Material.Wood,
	})
	log.Shape = Enum.PartType.Cylinder
	-- A little moss on top
	makeBall(parent, Vector3.new(length * 0.5, 0.4, 1.2), Color3.fromRGB(90, 150, 80), log.CFrame * CFrame.new(0, 0, -0.7), Enum.Material.Grass)
end

local function buildTallGrass(parent: Instance, position: Vector3, rng: Random)
	for _ = 1, 3 do
		makeBall(parent, Vector3.new(0.15, rng:NextNumber(1, 1.8), 0.15), Color3.fromRGB(110, 180, 90),
			CFrame.new(position + Vector3.new(rng:NextNumber(-0.5, 0.5), 0.6, rng:NextNumber(-0.5, 0.5)))
				* CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.15, 0.15)))
	end
end

local function buildFireflyPatch(parent: Instance, position: Vector3)
	local anchor = makePart(parent, {
		Size = Vector3.new(1, 1, 1),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CFrame = CFrame.new(position + Vector3.new(0, 3, 0)),
	})
	local flies = Instance.new("ParticleEmitter")
	flies.Color = ColorSequence.new(Color3.fromRGB(220, 255, 140))
	flies.LightEmission = 1
	flies.Rate = 3
	flies.Lifetime = NumberRange.new(2.5, 4)
	flies.Speed = NumberRange.new(0.4, 1)
	flies.SpreadAngle = Vector2.new(180, 180)
	flies.Size = NumberSequence.new(0.12)
	flies.Parent = anchor
end

-- ------------------------------------------------------------
-- Atmosphere: warm dappled dusk, gentle fog, light rays
-- ------------------------------------------------------------

local function setupAtmosphere()
	Lighting.Brightness = 2.2
	Lighting.Ambient = Color3.fromRGB(95, 95, 85)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 140, 120)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 225, 180)
	Lighting.ClockTime = 16.4 -- late-afternoon gold; fireflies read well

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.32
	atmosphere.Color = Color3.fromRGB(200, 205, 195)
	atmosphere.Haze = 1.6
	atmosphere.Parent = Lighting

	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.08
	rays.Spread = 0.6
	rays.Parent = Lighting

	-- TODO(real audio): looping forest birdsong / wind ambience goes here.
	-- The Sound object is wired now so swapping in a real SoundId later is
	-- a one-line change.
	local ambience = Instance.new("Sound")
	ambience.Name = "ForestAmbience"
	ambience.Looped = true
	ambience.Volume = 0.3
	ambience.Parent = game:GetService("SoundService")
end

-- ------------------------------------------------------------
-- Egg spawn points: clearings, path sides, near landmarks, under trees
-- ------------------------------------------------------------

local function collectEggSpawnPoints(rng: Random, treePositions: { Vector3 })
	for _, clearing in FOREST.Clearings do
		for _ = 1, 3 do
			table.insert(eggSpawnPoints, clearing + Vector3.new(rng:NextNumber(-8, 8), 0, rng:NextNumber(-8, 8)))
		end
	end
	for _, path in FOREST.Paths do
		for i = 1, #path - 1 do
			local mid = path[i]:Lerp(path[i + 1], 0.5)
			table.insert(eggSpawnPoints, Vector3.new(mid.X + rng:NextNumber(-6, 6), 0, mid.Y + rng:NextNumber(-6, 6)))
		end
	end
	-- Beside landmarks (just outside their footprints)
	for _ = 1, 4 do
		local angle = rng:NextNumber(0, math.pi * 2)
		table.insert(eggSpawnPoints, FOREST.VillageCenter + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (FOREST.VillageRadius + 10))
	end
	for _ = 1, 3 do
		local angle = rng:NextNumber(0, math.pi * 2)
		table.insert(eggSpawnPoints, FOREST.TreehousePosition + Vector3.new(math.cos(angle), 0, math.sin(angle)) * 20)
		table.insert(eggSpawnPoints, FOREST.PondCenter + Vector3.new(math.cos(angle + 1), 0, math.sin(angle + 1)) * (FOREST.PondRadius + 6))
	end
	-- Under a sampling of trees
	for i = 1, #treePositions, 4 do
		local tree = treePositions[i]
		table.insert(eggSpawnPoints, tree + Vector3.new(rng:NextNumber(-4, 4), 0, rng:NextNumber(-4, 4)))
	end
end

-- ------------------------------------------------------------
-- Public API
-- ------------------------------------------------------------

function ForestGenerator.getEggSpawnPoints(): { Vector3 }
	return eggSpawnPoints
end

function ForestGenerator.getCabinPlots(): { CFrame }
	return cabinPlots
end

function ForestGenerator.build()
	setupAtmosphere()
	generateTerrain()

	local forest = Instance.new("Model")
	forest.Name = "Forest"

	local rng = Random.new(FOREST.Seed)
	local treePositions: { Vector3 } = {}

	-- Tree copses: pick cluster centers, then plant a huddle around each
	for _ = 1, FOREST.TreeClusterCount do
		local center = randomOpenPoint(rng)
		if center then
			local count = rng:NextInteger(FOREST.TreesPerClusterMin, FOREST.TreesPerClusterMax)
			for _ = 1, count do
				local offset = Vector3.new(rng:NextNumber(-FOREST.TreeClusterRadius, FOREST.TreeClusterRadius), 0,
					rng:NextNumber(-FOREST.TreeClusterRadius, FOREST.TreeClusterRadius))
				local pos = center + offset
				if not isBlocked(pos) then
					buildTree(forest, pos, rng)
					table.insert(treePositions, pos)
				end
			end
		end
	end

	-- Scattered details, densest near tree clusters by nature of randomOpenPoint
	for i = 1, FOREST.RockCount do
		local pos = randomOpenPoint(rng)
		if pos then
			buildRock(forest, pos, rng, i % 5 == 0) -- every 5th rock is a boulder
		end
	end
	for _ = 1, FOREST.BushCount do
		local pos = randomOpenPoint(rng)
		if pos then
			buildBush(forest, pos, rng)
		end
	end
	for _ = 1, FOREST.FernCount do
		local pos = randomOpenPoint(rng)
		if pos then
			buildFern(forest, pos, rng)
		end
	end
	for _ = 1, FOREST.MushroomCount do
		local pos = randomOpenPoint(rng)
		if pos then
			buildMushroom(forest, pos, rng)
		end
	end
	for _ = 1, FOREST.FallenLogCount do
		local pos = randomOpenPoint(rng)
		if pos then
			buildFallenLog(forest, pos, rng)
		end
	end
	for _ = 1, FOREST.TallGrassCount do
		local pos = randomOpenPoint(rng)
		if pos then
			buildTallGrass(forest, pos, rng)
		end
	end
	for _ = 1, FOREST.FireflyPatchCount do
		local pos = randomOpenPoint(rng)
		if pos then
			buildFireflyPatch(forest, pos)
		end
	end

	-- Landmarks (each is its own Model pivoted at a config constant)
	LandmarkBuilder.buildVillage(forest, FOREST.VillageCenter, FOREST.VillageRadius)
	LandmarkBuilder.buildTreehouse(forest, FOREST.TreehousePosition)
	LandmarkBuilder.buildDock(forest, FOREST.PondCenter, FOREST.PondRadius)
	LandmarkBuilder.buildBridges(forest, FOREST.BridgePositions)

	-- Cabin plots ring the village; BaseUpgradeService builds/claims them
	for i = 1, FOREST.CabinCount do
		local angle = (i / FOREST.CabinCount) * math.pi * 2
		local pos = FOREST.VillageCenter + Vector3.new(math.cos(angle), 0, math.sin(angle)) * FOREST.VillageRadius
		-- Face the village center
		table.insert(cabinPlots, CFrame.lookAt(pos, Vector3.new(FOREST.VillageCenter.X, pos.Y, FOREST.VillageCenter.Z)))
	end

	collectEggSpawnPoints(rng, treePositions)

	forest.Parent = workspace
end

return ForestGenerator
