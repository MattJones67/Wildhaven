--[[
	TerrainForge — sculpts the whole CONNECTED continent as one heightmap:

	  * Forest: flat village heart rolling into gentle noise hills
	  * Desert: long dune waves (east)
	  * Tundra: base snowfields climbing into a massive mountain ring (west)
	  * Volcanic: a huge volcano cone with a walkable crater + lava lake (north)
	  * Coasts: every biome blends down into a beach, then the ocean

	The land is written with Terrain:WriteVoxels in chunks (the bulk API —
	filling this much ground with FillBlock would take minutes). The height
	function is PURE MATH (seeded noise), so:
	  * the same continent generates every server
	  * getHeightAt(x, z) lets every other builder sit props on the ground

	Sanctuary plots and biome arrival points are flattened into the height
	function itself, so pads never float or sink no matter how the noise
	rolls. Sky Isles are NOT part of the continent (BiomeGenerator floats
	them separately).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.GameConfig)

local TerrainForge = {}

local WATER_SURFACE = -2 -- sea level
local OCEAN_FLOOR = -11
local EXTENT = 780 -- continent voxels span [-EXTENT, EXTENT] on X and Z
local RES = 4 -- voxel resolution (Roblox terrain grid)
local CHUNK = 120 -- studs per WriteVoxels chunk (30x30 columns)
local Y_MIN, Y_MAX = -20, 120 -- vertical voxel range

local function smooth(t: number): number
	t = math.clamp(t, 0, 1)
	return t * t * (3 - 2 * t)
end

-- ------------------------------------------------------------
-- Flatten sites: plots + arrivals get level ground, guaranteed
-- ------------------------------------------------------------

local flattenSites: { { X: number, Z: number, Y: number, R: number } } = {}
local arrivalPoints: { [string]: Vector3 } = {}

local function computeSites()
	for _, biome in GameConfig.Biomes do
		if biome.Name == "Sky" then
			continue -- floats; not on the continent
		end
		-- Every sanctuary plot: dead-flat pad footprint
		for _, plot in biome.PlotPositions do
			table.insert(flattenSites, { X = plot.X, Z = plot.Z, Y = plot.Y, R = 38 })
		end
		-- Arrival zone (travel crystal drop-off) on the Forest-facing edge
		if biome.Name == "Forest" then
			arrivalPoints.Forest = Vector3.new(0, 0, 12) -- the village spawn
		else
			local toOrigin = (Vector3.zero - biome.Center) * Vector3.new(1, 0, 1)
			local pos = biome.Center + toOrigin.Unit * (biome.Radius - 60)
			local groundY = biome.Name == "Tundra" and 8 or 4
			arrivalPoints[biome.Name] = Vector3.new(pos.X, groundY, pos.Z)
			table.insert(flattenSites, { X = pos.X, Z = pos.Z, Y = groundY, R = 30 })
		end
	end
	-- Sky arrival: on the floating main disc
	arrivalPoints.Sky = GameConfig.BiomeByName.Sky.Center + Vector3.new(0, 0, 30)
end

-- Where travelers land in each biome (BiomeGenerator builds hubs here)
function TerrainForge.getArrival(biomeName: string): Vector3
	return arrivalPoints[biomeName]
end

-- ------------------------------------------------------------
-- Per-biome height fields (all seeded noise; tune freely)
-- ------------------------------------------------------------

local function forestHeight(x: number, z: number): number
	local hills = math.noise(x / 70, z / 70, 17) * 7 + math.noise(x / 26, z / 26, 3) * 2
	-- Dead-flat core so the village, river, pond and paths sit exactly at 0
	local coreDist = math.sqrt(x * x + (z + 10) * (z + 10))
	local factor = smooth((coreDist - 90) / 80) -- 0 inside r90, 1 past r170
	return math.max((2 + hills) * factor, -1)
end

local function desertHeight(x: number, z: number): number
	-- Long rolling dune waves + small ripples
	local dunes = math.noise(x / 85, z / 55, 909) * 11 + math.noise(x / 22, z / 22, 91) * 2
	return 4 + math.max(dunes, -3)
end

local function tundraHeight(x: number, z: number): number
	local lx, lz = x + 480, z
	local d = math.sqrt(lx * lx + lz * lz)
	local base = 9 + math.noise(x / 60, z / 60, 404) * 7
	-- Mountain ring: the further from the tundra heart, the higher — with a
	-- ridged noise so it reads as peaks and icy walls, not a smooth bowl
	local t = math.clamp((d - 110) / 130, 0, 1)
	local ridge = 1 - math.abs(math.noise(x / 95, z / 95, 44)) * 2
	return base + t ^ 1.6 * 62 * (0.55 + 0.45 * math.clamp(ridge, 0, 1))
end

local function volcanicHeight(x: number, z: number): number
	local lx, lz = x, z - 480
	local d = math.sqrt(lx * lx + lz * lz)
	local base = 5 + math.noise(x / 50, z / 50, 777) * 5
	if d < 130 then
		if d < 26 then
			-- Inside the crater: bowl walls down to a flat lava lake
			local rimHeight = 5 + (1 - 26 / 130) ^ 1.15 * 95
			local floorHeight = 38
			if d < 12 then
				return floorHeight + 0.5 -- the lava lake itself
			end
			return floorHeight + smooth((d - 12) / 14) * (rimHeight - floorHeight)
		end
		-- The cone
		return base + (1 - d / 130) ^ 1.15 * 95
	end
	return base
end

-- Region weights: 1 deep inside a biome, fading to 0 at its Radius
local function biomeWeight(x: number, z: number, biome): number
	local dx, dz = x - biome.Center.X, z - biome.Center.Z
	local t = math.sqrt(dx * dx + dz * dz) / biome.Radius
	if t >= 1 then
		return 0
	end
	if t < 0.6 then
		return 1
	end
	return smooth(1 - (t - 0.6) / 0.4)
end

local heightFields = {
	Forest = forestHeight,
	Desert = desertHeight,
	Tundra = tundraHeight,
	Volcanic = volcanicHeight,
}

-- THE height function: blended biome fields + coast falloff + flat pads.
function TerrainForge.getHeightAt(x: number, z: number): number
	local sumWeight, sumHeight, maxWeight = 0, 0, 0
	local dominant = "Forest"
	for _, biome in GameConfig.Biomes do
		local field = heightFields[biome.Name]
		if field then
			local weight = biomeWeight(x, z, biome)
			if weight > 0 then
				sumWeight += weight
				sumHeight += field(x, z) * weight
				if weight > maxWeight then
					maxWeight = weight
					dominant = biome.Name
				end
			end
		end
	end
	local height
	if sumWeight <= 0 then
		height = OCEAN_FLOOR
	else
		height = sumHeight / sumWeight
		-- Coast: as the strongest weight fades out, sink to the ocean floor
		height = OCEAN_FLOOR + (height - OCEAN_FLOOR) * smooth(maxWeight / 0.35)
	end
	-- Flat pads win over everything
	for _, site in flattenSites do
		local dx, dz = x - site.X, z - site.Z
		local d = math.sqrt(dx * dx + dz * dz)
		if d < site.R then
			height += (site.Y - height) * smooth((site.R - d) / 16)
		end
	end
	return height, dominant
end

-- ------------------------------------------------------------
-- Materials
-- ------------------------------------------------------------

local function materialFor(x: number, z: number, height: number, dominant: string): Enum.Material
	if height <= 0.6 then
		return Enum.Material.Sand -- beaches + shallows everywhere
	end
	if dominant == "Desert" then
		return math.noise(x / 34, z / 34, 55) > 0.3 and Enum.Material.Sandstone or Enum.Material.Sand
	elseif dominant == "Tundra" then
		if height > 46 then
			return Enum.Material.Glacier -- the high ice walls
		end
		return Enum.Material.Snow
	elseif dominant == "Volcanic" then
		local dx, dz = x, z - 480
		if math.sqrt(dx * dx + dz * dz) < 12 then
			return Enum.Material.CrackedLava -- the crater lake (glows!)
		end
		if height > 60 then
			return Enum.Material.Rock
		end
		return Enum.Material.Basalt
	end
	-- Forest
	return math.noise(x / 30, z / 30, 21) > 0.25 and Enum.Material.LeafyGrass or Enum.Material.Grass
end

-- ------------------------------------------------------------
-- Voxel writing (chunked bulk WriteVoxels)
-- ------------------------------------------------------------

local function writeChunk(terrain: Terrain, x0: number, z0: number)
	local region = Region3.new(
		Vector3.new(x0, Y_MIN, z0),
		Vector3.new(x0 + CHUNK, Y_MAX, z0 + CHUNK)
	):ExpandToGrid(RES)

	local nx, ny, nz = CHUNK / RES, (Y_MAX - Y_MIN) / RES, CHUNK / RES
	local materials = table.create(nx)
	local occupancy = table.create(nx)

	for ix = 1, nx do
		local wx = x0 + (ix - 0.5) * RES
		local matX = table.create(ny)
		local occX = table.create(ny)
		materials[ix] = matX
		occupancy[ix] = occX
		for iy = 1, ny do
			matX[iy] = table.create(nz)
			occX[iy] = table.create(nz)
		end
		for iz = 1, nz do
			local wz = z0 + (iz - 0.5) * RES
			local height, dominant = TerrainForge.getHeightAt(wx, wz)
			local material = materialFor(wx, wz, height, dominant)
			for iy = 1, ny do
				local voxelTop = Y_MIN + iy * RES
				local depth = height - (voxelTop - RES) -- ground depth at this voxel
				local occ, mat
				if depth >= RES then
					occ, mat = 1, material
				elseif depth > 0.2 then
					occ, mat = depth / RES, material
				else
					occ, mat = 0, Enum.Material.Air
				end
				-- Fill open space below sea level with water
				if occ < 0.5 and voxelTop <= WATER_SURFACE + RES / 2 then
					occ, mat = 1, Enum.Material.Water
				end
				occX[iy][iz] = occ
				matX[iy][iz] = mat
			end
		end
	end

	terrain:WriteVoxels(region, RES, materials, occupancy)
end

function TerrainForge.build()
	computeSites()
	local terrain = workspace.Terrain

	-- Endless-looking sea beyond the continent's voxel range
	terrain:FillBlock(CFrame.new(0, -6, 0), Vector3.new(2600, 8, 2600), Enum.Material.Water)

	for x0 = -EXTENT, EXTENT - 1, CHUNK do
		for z0 = -EXTENT, EXTENT - 1, CHUNK do
			writeChunk(terrain, x0, z0)
		end
	end
end

return TerrainForge
