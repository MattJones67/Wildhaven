--[[
	TerrainForge — sculpts the whole CONNECTED island as one heightmap.

	WORLD EXPANSION: every region is ~3x its old area, and everything now
	derives from GameConfig.Biomes (Center/Radius), so region sizes are
	one-number tweaks:

	  * Forest: flat village heart rolling into broad hills
	  * Desert: long dune seas (east)
	  * Tundra: snowfields climbing into a massive mountain ring (west)
	  * Volcanic: a huge volcano cone + walkable crater + lava lake (north)
	  * NATURAL BORDER RIDGES: gated regions are walled by mountain ridges
	    at their GateRadius, broken only by ONE mountain pass facing the
	    Forest — the pass holds the unlock gate (BiomeGenerator builds it)
	  * Coasts: everything blends down into beach, then ocean

	Generation is chunked WriteVoxels with a task.wait() between chunk rows
	so the (much bigger) build never freezes the server. The height
	function stays PURE MATH — getHeightAt(x, z) is the ground truth every
	prop builder sits on. Flatten sites (plots, arrivals) still win over
	everything, so pads never float.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.GameConfig)

local TerrainForge = {}

local WATER_SURFACE = -2
local OCEAN_FLOOR = -11
local EXTENT = GameConfig.World.Extent
local RES = 4
local CHUNK = 120
local Y_MIN, Y_MAX = -20, 168 -- tall enough for ridge-topped mountains

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
			continue
		end
		for _, plot in biome.PlotPositions do
			table.insert(flattenSites, { X = plot.X, Z = plot.Z, Y = plot.Y, R = 38 })
		end
		if biome.Name == "Forest" then
			arrivalPoints.Forest = Vector3.new(0, 0, 12)
		else
			local toOrigin = (Vector3.zero - biome.Center) * Vector3.new(1, 0, 1)
			local pos = biome.Center + toOrigin.Unit * (biome.Radius - 90)
			local groundY = biome.Name == "Tundra" and 8 or 4
			arrivalPoints[biome.Name] = Vector3.new(pos.X, groundY, pos.Z)
			table.insert(flattenSites, { X = pos.X, Z = pos.Z, Y = groundY, R = 30 })
			-- Flatten the mountain-pass corridor floor too, so walking
			-- through the unlocked gate is a real path, not a climb
			local passPos = biome.Center + toOrigin.Unit * (biome.GateRadius or (biome.Radius - 25))
			table.insert(flattenSites, { X = passPos.X, Z = passPos.Z, Y = 3, R = 34 })
		end
	end
	arrivalPoints.Sky = GameConfig.BiomeByName.Sky.Center + Vector3.new(0, 0, 30)
end

function TerrainForge.getArrival(biomeName: string): Vector3
	return arrivalPoints[biomeName]
end

-- Where each gated biome's mountain pass sits (BiomeGenerator's gate spot)
function TerrainForge.getPassPosition(biomeName: string): Vector3?
	local biome = GameConfig.BiomeByName[biomeName]
	if not biome or not biome.GateRadius then
		return nil
	end
	local toOrigin = (Vector3.zero - biome.Center) * Vector3.new(1, 0, 1)
	local pos = biome.Center + toOrigin.Unit * biome.GateRadius
	return Vector3.new(pos.X, 3, pos.Z)
end

-- ------------------------------------------------------------
-- Per-biome height fields (parametrized by each biome's Radius)
-- ------------------------------------------------------------

local function forestHeight(x: number, z: number): number
	local hills = math.noise(x / 110, z / 110, 17) * 10 + math.noise(x / 32, z / 32, 3) * 2.5
	local coreDist = math.sqrt(x * x + (z + 10) * (z + 10))
	local factor = smooth((coreDist - 90) / 80) -- dead flat village heart
	return math.max((2 + hills) * factor, -1)
end

local function desertHeight(x: number, z: number): number
	local dunes = math.noise(x / 140, z / 90, 909) * 14 + math.noise(x / 30, z / 30, 91) * 2.5
	return 4 + math.max(dunes, -3)
end

local function tundraHeight(x: number, z: number): number
	local biome = GameConfig.BiomeByName.Tundra
	local lx, lz = x - biome.Center.X, z - biome.Center.Z
	local d = math.sqrt(lx * lx + lz * lz)
	local base = 9 + math.noise(x / 90, z / 90, 404) * 8
	local t = math.clamp((d - biome.Radius * 0.42) / (biome.Radius * 0.38), 0, 1)
	local ridge = 1 - math.abs(math.noise(x / 150, z / 150, 44)) * 2
	return base + t ^ 1.6 * 85 * (0.55 + 0.45 * math.clamp(ridge, 0, 1))
end

local function volcanicHeight(x: number, z: number): number
	local biome = GameConfig.BiomeByName.Volcanic
	local lx, lz = x - biome.Center.X, z - biome.Center.Z
	local d = math.sqrt(lx * lx + lz * lz)
	local base = 5 + math.noise(x / 80, z / 80, 777) * 6
	local coneRadius = biome.Radius * 0.55
	if d < coneRadius then
		local craterRadius = coneRadius * 0.2
		local lakeRadius = coneRadius * 0.09
		if d < craterRadius then
			local rimHeight = 5 + (1 - craterRadius / coneRadius) ^ 1.15 * 130
			local floorHeight = 55
			if d < lakeRadius then
				return floorHeight + 0.5 -- the lava lake
			end
			return floorHeight + smooth((d - lakeRadius) / (craterRadius - lakeRadius)) * (rimHeight - floorHeight)
		end
		return base + (1 - d / coneRadius) ^ 1.15 * 130
	end
	return base
end

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

-- NATURAL BORDER RIDGES: a mountain wall ringing each gated biome at its
-- GateRadius, with ONE pass corridor facing the Forest. Returns extra
-- height (0 in the pass / away from borders).
local function ridgeHeight(x: number, z: number): number
	local world = GameConfig.World
	local total = 0
	for _, biome in GameConfig.Biomes do
		local gateRadius = biome.GateRadius
		if not gateRadius then
			continue
		end
		local dx, dz = x - biome.Center.X, z - biome.Center.Z
		local d = math.sqrt(dx * dx + dz * dz)
		local halfBand = biome.Radius * world.RidgeBand / 2
		if math.abs(d - gateRadius) > halfBand then
			continue
		end
		-- Inside the ridge band; is this the pass corridor?
		local toOrigin = math.atan2(-biome.Center.Z, -biome.Center.X)
		local pointAngle = math.atan2(dz, dx)
		local delta = math.abs(math.atan2(math.sin(pointAngle - toOrigin), math.cos(pointAngle - toOrigin)))
		local passFactor = smooth((delta - world.PassHalfAngle) / world.PassHalfAngle)
		local bump = smooth(1 - math.abs(d - gateRadius) / halfBand)
		local jag = 0.75 + 0.5 * math.abs(math.noise(x / 60, z / 60, 88))
		total += world.RidgeHeight * bump * passFactor * jag
	end
	return total
end

function TerrainForge.getHeightAt(x: number, z: number): (number, string)
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
		height = OCEAN_FLOOR + (height - OCEAN_FLOOR) * smooth(maxWeight / 0.35)
		-- Border mountains only rise where there's real land under them
		height += ridgeHeight(x, z) * smooth(maxWeight / 0.5)
	end
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
		return Enum.Material.Sand
	end
	if dominant == "Desert" then
		if height > 42 then
			return Enum.Material.Rock -- the border ridge shows as bare rock
		end
		return math.noise(x / 34, z / 34, 55) > 0.3 and Enum.Material.Sandstone or Enum.Material.Sand
	elseif dominant == "Tundra" then
		if height > 52 then
			return Enum.Material.Glacier
		end
		return Enum.Material.Snow
	elseif dominant == "Volcanic" then
		local biome = GameConfig.BiomeByName.Volcanic
		local dx, dz = x - biome.Center.X, z - biome.Center.Z
		if math.sqrt(dx * dx + dz * dz) < biome.Radius * 0.55 * 0.09 then
			return Enum.Material.CrackedLava -- the crater lake (glows!)
		end
		if height > 75 then
			return Enum.Material.Rock
		end
		return Enum.Material.Basalt
	end
	-- Forest (border ridges near the forest read as rocky crags too)
	if height > 45 then
		return Enum.Material.Rock
	end
	return math.noise(x / 30, z / 30, 21) > 0.25 and Enum.Material.LeafyGrass or Enum.Material.Grass
end

-- ------------------------------------------------------------
-- Voxel writing (chunked bulk WriteVoxels, with yields)
-- ------------------------------------------------------------

local function writeChunk(terrain: Terrain, x0: number, z0: number)
	local nx, nz = CHUNK / RES, CHUNK / RES

	-- Pass 1: heights for every column, and the chunk's tallest point —
	-- so we only write voxel rows that can contain ground (most of the
	-- map is low; skipping empty sky rows makes generation ~4x faster)
	local heights = table.create(nx)
	local dominants = table.create(nx)
	local chunkMax = WATER_SURFACE
	for ix = 1, nx do
		heights[ix] = table.create(nz)
		dominants[ix] = table.create(nz)
		local wx = x0 + (ix - 0.5) * RES
		for iz = 1, nz do
			local wz = z0 + (iz - 0.5) * RES
			local height, dominant = TerrainForge.getHeightAt(wx, wz)
			heights[ix][iz] = height
			dominants[ix][iz] = dominant
			if height > chunkMax then
				chunkMax = height
			end
		end
	end
	local yTop = math.min(Y_MAX, math.ceil((chunkMax + 8) / RES) * RES)
	local ny = (yTop - Y_MIN) / RES

	local region = Region3.new(
		Vector3.new(x0, Y_MIN, z0),
		Vector3.new(x0 + CHUNK, yTop, z0 + CHUNK)
	):ExpandToGrid(RES)

	-- Pass 2: fill the (much shorter) voxel arrays
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
			local height = heights[ix][iz]
			local material = materialFor(wx, wz, height, dominants[ix][iz])
			for iy = 1, ny do
				local voxelTop = Y_MIN + iy * RES
				local depth = height - (voxelTop - RES)
				local occ, mat
				if depth >= RES then
					occ, mat = 1, material
				elseif depth > 0.2 then
					occ, mat = depth / RES, material
				else
					occ, mat = 0, Enum.Material.Air
				end
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

	-- Endless-looking sea beyond the voxel range
	terrain:FillBlock(CFrame.new(0, -6, 0), Vector3.new(4200, 8, 4200), Enum.Material.Water)

	-- The island is big now: yield between chunk rows so the server stays
	-- responsive during the ~a-few-seconds generation
	local built = 0
	for x0 = -EXTENT, EXTENT - 1, CHUNK do
		for z0 = -EXTENT, EXTENT - 1, CHUNK do
			writeChunk(terrain, x0, z0)
		end
		built += 1
		if built % 4 == 0 then
			task.wait()
		end
	end
end

return TerrainForge
