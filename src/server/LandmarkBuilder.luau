--[[
	LandmarkBuilder — the hand-crafted set pieces: the spawn village
	(campfire, walkways, lanterns, well, benches, signpost), the big
	central treehouse, the pond dock, and the river bridges.

	Every landmark is its own Model built around a single position argument,
	so moving one later means changing one constant in GameConfig.Forest.
	Player cabins are NOT built here — see BaseBuilder (they change per player).
]]

local LandmarkBuilder = {}

local WOOD = Color3.fromRGB(140, 100, 65)
local DARK_WOOD = Color3.fromRGB(105, 72, 48)
local STONE = Color3.fromRGB(150, 148, 145)
local LEAF = Color3.fromRGB(90, 160, 85)

local function makePart(parent: Instance, props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.Wood
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
		Material = material or Enum.Material.Wood,
	})
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Warm glowing lantern on a pole — used all over the village
local function buildLampPost(parent: Instance, position: Vector3)
	standingCylinder(parent, 5, 0.4, DARK_WOOD, position + Vector3.new(0, 2.5, 0))
	local lantern = makePart(parent, {
		Size = Vector3.new(0.8, 1, 0.8),
		Color = Color3.fromRGB(255, 215, 130),
		Material = Enum.Material.Neon,
		CFrame = CFrame.new(position + Vector3.new(0, 5.2, 0)),
		CanCollide = false,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 210, 140)
	light.Brightness = 1.2
	light.Range = 14
	light.Parent = lantern
end

-- ------------------------------------------------------------
-- The spawn village: campfire heart, walkway ring, furniture
-- ------------------------------------------------------------

local function buildCampfire(parent: Instance, center: Vector3)
	-- Stone ring
	for i = 1, 7 do
		local angle = (i / 7) * math.pi * 2
		makeBall(parent, Vector3.new(1.4, 0.9, 1.1), STONE,
			CFrame.new(center + Vector3.new(math.cos(angle) * 2.2, 0.35, math.sin(angle) * 2.2)) * CFrame.Angles(0, angle, 0),
			Enum.Material.Slate)
	end
	-- Crossed logs
	for i = 1, 3 do
		local log = makePart(parent, {
			Size = Vector3.new(3.4, 0.7, 0.7),
			Color = DARK_WOOD,
			CFrame = CFrame.new(center + Vector3.new(0, 0.6, 0)) * CFrame.Angles(0, i * math.pi / 3, math.rad(18)),
		})
		log.Shape = Enum.PartType.Cylinder
		log.CanCollide = false
	end
	-- The fire itself: Roblox's built-in Fire effect + warm light + smoke
	local core = makePart(parent, {
		Size = Vector3.new(1, 1, 1),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CFrame = CFrame.new(center + Vector3.new(0, 1.2, 0)),
	})
	local fire = Instance.new("Fire")
	fire.Size = 6
	fire.Heat = 9
	fire.Parent = core
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 170, 90)
	light.Brightness = 2
	light.Range = 24
	light.Parent = core
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(120, 115, 110))
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	smoke.Rate = 3
	smoke.Lifetime = NumberRange.new(2, 3.5)
	smoke.Speed = NumberRange.new(2, 3)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 3) })
	smoke.Parent = core
	-- TODO(real audio): crackling fire loop — Sound is wired, id comes later.
	local crackle = Instance.new("Sound")
	crackle.Name = "CampfireCrackle"
	crackle.Looped = true
	crackle.Volume = 0.5
	crackle.RollOffMaxDistance = 40
	crackle.Parent = core
end

function LandmarkBuilder.buildVillage(parent: Instance, center: Vector3, radius: number)
	local village = Instance.new("Model")
	village.Name = "Village"

	buildCampfire(village, center)

	-- Spawn pad: players appear beside the campfire
	local spawn = Instance.new("SpawnLocation")
	spawn.Size = Vector3.new(7, 0.5, 7)
	spawn.CFrame = CFrame.new(center + Vector3.new(0, 0.25, 9))
	spawn.Anchored = true
	spawn.Color = Color3.fromRGB(185, 180, 170)
	spawn.Material = Enum.Material.Slate
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = village

	-- Raised walkway ring around the campfire + a lamp post per quarter
	local ringRadius = 14
	local segments = 16
	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		local nextAngle = ((i + 1) / segments) * math.pi * 2
		local a = center + Vector3.new(math.cos(angle) * ringRadius, 0.35, math.sin(angle) * ringRadius)
		local b = center + Vector3.new(math.cos(nextAngle) * ringRadius, 0.35, math.sin(nextAngle) * ringRadius)
		makePart(village, {
			Size = Vector3.new(3.2, 0.35, (b - a).Magnitude + 0.6),
			Color = WOOD,
			CFrame = CFrame.lookAt((a + b) / 2, b),
		})
		if i % 4 == 0 then
			buildLampPost(village, center + Vector3.new(math.cos(angle) * (ringRadius + 2.5), 0, math.sin(angle) * (ringRadius + 2.5)))
		end
	end

	-- Radial walkways from the ring out toward each cabin plot
	local cabinCount = 8
	for i = 1, cabinCount do
		local angle = (i / cabinCount) * math.pi * 2
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local a = center + dir * ringRadius
		local b = center + dir * (radius - 6)
		makePart(village, {
			Size = Vector3.new(2.4, 0.35, (b - a).Magnitude),
			Color = WOOD,
			CFrame = CFrame.lookAt((a + b) / 2 + Vector3.new(0, 0.35, 0), b + Vector3.new(0, 0.35, 0)),
		})
	end

	-- Log benches facing the fire
	for i = 1, 3 do
		local angle = i * (math.pi * 2 / 3) + 0.5
		local pos = center + Vector3.new(math.cos(angle) * 6, 0, math.sin(angle) * 6)
		local bench = makePart(village, {
			Size = Vector3.new(3.6, 0.5, 1),
			Color = DARK_WOOD,
			CFrame = CFrame.lookAt(pos + Vector3.new(0, 0.8, 0), Vector3.new(center.X, 0.8, center.Z)) * CFrame.Angles(0, math.rad(90), 0),
		})
		for _, side in { -1.2, 1.2 } do
			makePart(village, {
				Size = Vector3.new(0.4, 0.6, 0.8),
				Color = DARK_WOOD,
				CFrame = bench.CFrame * CFrame.new(side, -0.55, 0),
			})
		end
	end

	-- The village well
	local wellPos = center + Vector3.new(-8, 0, 8)
	standingCylinder(village, 1.6, 4, STONE, wellPos + Vector3.new(0, 0.8, 0), Enum.Material.Slate)
	standingCylinder(village, 1.2, 3, Color3.fromRGB(40, 60, 80), wellPos + Vector3.new(0, 1.7, 0), Enum.Material.SmoothPlastic)
	for _, side in { -1.6, 1.6 } do
		standingCylinder(village, 3.4, 0.35, DARK_WOOD, wellPos + Vector3.new(side, 1.7, 0))
	end
	makePart(village, {
		Size = Vector3.new(4.4, 0.3, 2.4),
		Color = DARK_WOOD,
		CFrame = CFrame.new(wellPos + Vector3.new(0, 3.5, 0)) * CFrame.Angles(0, 0, math.rad(12)),
	})

	-- Signpost by the spawn
	local signPos = center + Vector3.new(5, 0, 12)
	standingCylinder(village, 4, 0.4, DARK_WOOD, signPos + Vector3.new(0, 2, 0))
	makePart(village, {
		Size = Vector3.new(3, 0.8, 0.2),
		Color = WOOD,
		CFrame = CFrame.new(signPos + Vector3.new(0.8, 3.2, 0)) * CFrame.Angles(0, math.rad(-15), 0),
	})
	makePart(village, {
		Size = Vector3.new(2.6, 0.7, 0.2),
		Color = WOOD,
		CFrame = CFrame.new(signPos + Vector3.new(-0.6, 2.4, 0)) * CFrame.Angles(0, math.rad(20), 0),
	})

	village.Parent = parent
end

-- ------------------------------------------------------------
-- The great treehouse: trunk, platforms, truss ladder, lookout
-- ------------------------------------------------------------

function LandmarkBuilder.buildTreehouse(parent: Instance, position: Vector3)
	local treehouse = Instance.new("Model")
	treehouse.Name = "Treehouse"

	-- Massive trunk + canopy
	standingCylinder(treehouse, 30, 9, Color3.fromRGB(110, 78, 54), position + Vector3.new(0, 15, 0), Enum.Material.Wood)
	for i, offset in { Vector3.new(0, 32, 0), Vector3.new(6, 29, 4), Vector3.new(-6, 30, -3), Vector3.new(2, 31, -6) } do
		local size = 16 - i * 1.5
		makeBall(treehouse, Vector3.new(size, size * 0.75, size), LEAF, CFrame.new(position + offset), Enum.Material.Grass)
	end

	-- Platform helper: a wooden disc around the trunk with railing posts
	local function platform(height: number, radius: number)
		standingCylinder(treehouse, 0.6, radius * 2, WOOD, position + Vector3.new(0, height, 0))
		for i = 1, 10 do
			local angle = (i / 10) * math.pi * 2
			makePart(treehouse, {
				Size = Vector3.new(0.3, 2.4, 0.3),
				Color = DARK_WOOD,
				CFrame = CFrame.new(position + Vector3.new(math.cos(angle) * (radius - 0.4), height + 1.4, math.sin(angle) * (radius - 0.4))),
			})
		end
		-- Rail ring (thin, sits on the posts)
		standingCylinder(treehouse, 0.25, radius * 2 - 0.5, DARK_WOOD, position + Vector3.new(0, height + 2.6, 0))
	end

	platform(10, 8.5)
	platform(18, 7.5)
	platform(26, 6) -- the lookout

	-- Climbable truss ladder up the south face, ground to lookout
	local truss = Instance.new("TrussPart")
	truss.Size = Vector3.new(2, 26.5, 2)
	truss.CFrame = CFrame.new(position + Vector3.new(0, 13.25, 5.6))
	truss.Anchored = true
	truss.BrickColor = BrickColor.new("Dark orange")
	truss.Parent = treehouse

	-- A hanging lantern per platform for dusk charm
	for _, height in { 12.5, 20.5, 28.5 } do
		local lantern = makePart(treehouse, {
			Size = Vector3.new(0.7, 0.9, 0.7),
			Color = Color3.fromRGB(255, 215, 130),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CFrame = CFrame.new(position + Vector3.new(6.5, height, 0)),
		})
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 210, 140)
		light.Brightness = 1
		light.Range = 12
		light.Parent = lantern
	end

	treehouse.Parent = parent
end

-- ------------------------------------------------------------
-- Pond dock + river bridges
-- ------------------------------------------------------------

function LandmarkBuilder.buildDock(parent: Instance, pondCenter: Vector3, pondRadius: number)
	local dock = Instance.new("Model")
	dock.Name = "Dock"
	-- The dock reaches from the west shore out over the water
	local shore = pondCenter + Vector3.new(-pondRadius - 2, 0, 0)
	for i = 0, 3 do
		makePart(dock, {
			Size = Vector3.new(3, 0.35, 3.4),
			Color = WOOD,
			CFrame = CFrame.new(shore + Vector3.new(i * 3.2, 0.7, 0)),
		})
	end
	for _, dz in { -1.2, 1.2 } do
		for _, dx in { 3, 9.5 } do
			standingCylinder(dock, 2.6, 0.5, DARK_WOOD, shore + Vector3.new(dx, 0, dz))
		end
	end
	buildLampPost(dock, shore + Vector3.new(10.5, 0.6, 1.2))
	dock.Parent = parent
end

function LandmarkBuilder.buildBridges(parent: Instance, positions: { Vector3 })
	for index, position in positions do
		local bridge = Instance.new("Model")
		bridge.Name = "Bridge" .. index
		-- Gently arched planks spanning east-west over the river
		for i = -3, 3 do
			makePart(bridge, {
				Size = Vector3.new(2.4, 0.35, 2),
				Color = WOOD,
				CFrame = CFrame.new(position + Vector3.new(i * 2.1, 1 + math.cos(i * 0.5) * 0.7, 0))
					* CFrame.Angles(0, 0, math.rad(-i * 4)),
			})
		end
		-- Rails
		for _, dz in { -1.1, 1.1 } do
			makePart(bridge, {
				Size = Vector3.new(13.5, 0.25, 0.25),
				Color = DARK_WOOD,
				CFrame = CFrame.new(position + Vector3.new(0, 2.6, dz)),
				CanCollide = false,
			})
			for _, dx in { -6, 0, 6 } do
				makePart(bridge, {
					Size = Vector3.new(0.3, 1.8, 0.3),
					Color = DARK_WOOD,
					CFrame = CFrame.new(position + Vector3.new(dx, 1.8, dz)),
					CanCollide = false,
				})
			end
		end
		bridge.Parent = parent
	end
end

return LandmarkBuilder
