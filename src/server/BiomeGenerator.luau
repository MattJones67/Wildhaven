--[[
	BiomeGenerator — decorates the continent TerrainForge sculpted, region
	by region, and floats the Sky Isles:

	  * Desert: cactus stands, weathered ruins, and TWO stepped pyramids
	    with dark doorways (egg spawns hide by them)
	  * Tundra: snowy pines, ice spikes, giant translucent ICE WALL slabs
	    up in the mountain ring, and a frozen pond
	  * Volcanic: obsidian spikes, ember vents, crater-rim smoke, and two
	    glowing lava falls running down the volcano's flank
	  * Sky: three floating grass discs, plank bridges, clouds, crystals

	Every prop asks TerrainForge.getHeightAt for its ground, so it all sits
	on the real slopes. It also builds the shared furniture: travel hubs,
	guide NPCs, sanctuary pads (positions straight from GameConfig), and
	the translucent GATE WALL rings around locked biomes (BiomeService
	enforces them; BiomeWallController makes them solid locally for locked
	players).

	Exposes the lookups other services need — same API as before:
	  getEggSpawnPoints / getTravelTarget / getTravelPillars /
	  getSanctuaryPlots / getGuidePrompt / getBiomeAt
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local ForestGenerator = require(script.Parent.ForestGenerator)
local TerrainForge = require(script.Parent.TerrainForge)

local BiomeGenerator = {}

local eggPoints: { [string]: { Vector3 } } = {}
local travelTargets: { [string]: CFrame } = {}
local travelPillars: { { Dest: string, Part: BasePart } } = {}
local sanctuaryPlots: { [string]: { CFrame } } = {}
local guidePrompts: { [string]: ProximityPrompt } = {}

-- ------------------------------------------------------------
-- Part helpers
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

-- Ground height shorthand
local function groundAt(x: number, z: number): number
	return (TerrainForge.getHeightAt(x, z))
end

-- A random position inside a biome's region, on the ground, skipping water
local function randomGroundPoint(biome, rng: Random, minR: number, maxR: number): Vector3?
	for _ = 1, 15 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(minR, maxR)
		local x = biome.Center.X + math.cos(angle) * radius
		local z = biome.Center.Z + math.sin(angle) * radius
		local height = groundAt(x, z)
		if height > 1 then
			return Vector3.new(x, height, z)
		end
	end
	return nil
end

-- ------------------------------------------------------------
-- Shared furniture: pads, guides, travel hubs, gate walls
-- ------------------------------------------------------------

local function buildSanctuaryPads(parent: Instance, biome)
	sanctuaryPlots[biome.Name] = {}
	local half = GameConfig.Sanctuary.PlotHalfSize
	for _, pos in biome.PlotPositions do
		makePart(parent, {
			Name = "SanctuaryPad",
			Size = Vector3.new(half * 2 + 2, 0.5, half * 2 + 2),
			Color = Color3.fromRGB(185, 178, 165),
			Material = Enum.Material.Slate,
			CFrame = CFrame.new(pos + Vector3.new(0, 0.25, 0)),
		})
		table.insert(sanctuaryPlots[biome.Name], CFrame.new(pos + Vector3.new(0, 0.5, 0)))
	end
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

-- Translucent gate-wall ring around a locked biome. Server-side these
-- never collide (unlocked players walk straight through); the CLIENT
-- turns collision on locally while the biome is locked for them, and
-- BiomeService teleports out anyone who cheats past. ForceField material
-- gives the shimmer "energy barrier" look for free.
local function buildGateWall(parent: Instance, biome)
	local radius = biome.WallRadius
	if not radius then
		return
	end
	local segments = 36
	local arc = (2 * math.pi * radius) / segments
	local wallFolder = Instance.new("Folder")
	wallFolder.Name = "GateWall_" .. biome.Name

	for i = 1, segments do
		local angle = (i / segments) * math.pi * 2
		local x = biome.Center.X + math.cos(angle) * radius
		local z = biome.Center.Z + math.sin(angle) * radius
		local wall = makePart(wallFolder, {
			Name = "GateWall",
			Size = Vector3.new(arc + 2, 110, 2),
			Color = biome.Color,
			Material = Enum.Material.ForceField,
			Transparency = 0.85,
			CanCollide = false, -- collision is applied LOCALLY per player
			CFrame = CFrame.new(Vector3.new(x, 40, z), Vector3.new(biome.Center.X, 40, biome.Center.Z)),
		})
		CollectionService:AddTag(wall, "BiomeWall")
		wall:SetAttribute("Biome", biome.Name)
	end

	-- Lock sign on the Forest-facing side so travelers know the deal
	local toOrigin = (Vector3.zero - biome.Center) * Vector3.new(1, 0, 1)
	local signPos = biome.Center + toOrigin.Unit * radius
	local anchor = makePart(wallFolder, {
		Size = Vector3.new(1, 1, 1),
		Transparency = 1,
		CanCollide = false,
		CFrame = CFrame.new(signPos.X, groundAt(signPos.X, signPos.Z) + 9, signPos.Z),
	})
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 260, 0, 60)
	billboard.MaxDistance = 220
	billboard.Adornee = anchor
	billboard.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "🔒 " .. biome.Emoji .. " " .. biome.Name .. "\n" .. biome.GateText
	label.TextColor3 = biome.Color
	label.Parent = billboard
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 20, 25)
	stroke.Thickness = 2.5
	stroke.Parent = label
	CollectionService:AddTag(anchor, "BiomeWallSign")
	anchor:SetAttribute("Biome", biome.Name)

	wallFolder.Parent = parent
end

-- ------------------------------------------------------------
-- Region decorators
-- ------------------------------------------------------------

local function addEggPoint(biomeName: string, pos: Vector3)
	eggPoints[biomeName] = eggPoints[biomeName] or {}
	table.insert(eggPoints[biomeName], pos)
end

local function collectGroundPoints(biome, rng: Random, count: number, minR: number, maxR: number)
	for _ = 1, count do
		local pos = randomGroundPoint(biome, rng, minR, maxR)
		if pos then
			addEggPoint(biome.Name, pos)
		end
	end
end

-- A stepped sandstone pyramid with a dark doorway — the desert's landmark.
local function buildPyramid(parent: Instance, baseCenter: Vector3, tiers: number, baseWidth: number)
	local sand = Color3.fromRGB(220, 192, 140)
	local trim = Color3.fromRGB(190, 160, 110)
	local tierHeight = 3.4
	for tier = 0, tiers - 1 do
		local width = baseWidth - tier * (baseWidth / tiers)
		makePart(parent, {
			Size = Vector3.new(width, tierHeight, width),
			Color = tier % 2 == 0 and sand or trim,
			Material = Enum.Material.Sandstone,
			CFrame = CFrame.new(baseCenter + Vector3.new(0, tierHeight / 2 + tier * tierHeight, 0)),
		})
	end
	-- Gold cap + dark doorway
	makePart(parent, {
		Size = Vector3.new(3, 2.6, 3),
		Color = Color3.fromRGB(255, 210, 90),
		Material = Enum.Material.Metal,
		Reflectance = 0.3,
		CFrame = CFrame.new(baseCenter + Vector3.new(0, tiers * tierHeight + 1.3, 0)) * CFrame.Angles(0, math.rad(45), 0),
	})
	makePart(parent, {
		Size = Vector3.new(3.4, 4.4, 1.2),
		Color = Color3.fromRGB(35, 30, 28),
		Material = Enum.Material.Slate,
		CanCollide = false,
		CFrame = CFrame.new(baseCenter + Vector3.new(0, 2.2, -baseWidth / 2 - 0.2)),
	})
	addEggPoint("Desert", baseCenter + Vector3.new(0, 0, -baseWidth / 2 - 6))
end

local function buildDesert(parent: Instance, biome, rng: Random)
	-- Cactus stands
	for _ = 1, 22 do
		local pos = randomGroundPoint(biome, rng, 30, biome.Radius - 40)
		if pos then
			local height = rng:NextNumber(3, 6)
			local green = Color3.fromRGB(90, 155, 80)
			standingCylinder(parent, height, 1, green, pos + Vector3.new(0, height / 2, 0), Enum.Material.Grass)
			for _, side in { -1, 1 } do
				if rng:NextNumber() < 0.6 then
					standingCylinder(parent, height * 0.4, 0.7, green, pos + Vector3.new(side * 0.85, height * 0.55, 0), Enum.Material.Grass)
				end
			end
		end
	end
	-- Weathered ruin circle
	local ruinsX, ruinsZ = biome.Center.X + 60, biome.Center.Z - 70
	local ruinsY = groundAt(ruinsX, ruinsZ)
	for i = 1, 6 do
		local angle = (i / 6) * math.pi * 2
		local height = rng:NextNumber(3, 8)
		standingCylinder(parent, height, 2, Color3.fromRGB(215, 190, 145),
			Vector3.new(ruinsX + math.cos(angle) * 9, ruinsY + height / 2 - 0.5, ruinsZ + math.sin(angle) * 9), Enum.Material.Sandstone)
	end
	makePart(parent, {
		Size = Vector3.new(11, 1.5, 2),
		Color = Color3.fromRGB(215, 190, 145),
		Material = Enum.Material.Sandstone,
		CFrame = CFrame.new(ruinsX, ruinsY + 8, ruinsZ) * CFrame.Angles(0, math.rad(25), math.rad(7)),
	})
	addEggPoint("Desert", Vector3.new(ruinsX, ruinsY, ruinsZ))

	-- THE pyramids (positions are constants — nudge freely)
	local p1x, p1z = biome.Center.X + 110, biome.Center.Z + 80
	local p2x, p2z = biome.Center.X - 40, biome.Center.Z - 120
	buildPyramid(parent, Vector3.new(p1x, groundAt(p1x, p1z) - 0.5, p1z), 9, 46)
	buildPyramid(parent, Vector3.new(p2x, groundAt(p2x, p2z) - 0.5, p2z), 6, 30)

	-- Sun-bleached rocks
	for _ = 1, 10 do
		local pos = randomGroundPoint(biome, rng, 30, biome.Radius - 40)
		if pos then
			local size = rng:NextNumber(1.5, 4)
			makeBall(parent, Vector3.new(size, size * 0.6, size), Color3.fromRGB(205, 185, 150),
				CFrame.new(pos + Vector3.new(0, size * 0.2, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0), Enum.Material.Sandstone)
		end
	end
	collectGroundPoints(biome, rng, 12, 25, biome.Radius - 50)
end

local function buildTundra(parent: Instance, biome, rng: Random)
	-- Snowy pines across the snowfields
	for _ = 1, 18 do
		local pos = randomGroundPoint(biome, rng, 25, 150)
		if pos then
			local height = rng:NextNumber(4, 8)
			standingCylinder(parent, height, 1, Color3.fromRGB(105, 78, 58), pos + Vector3.new(0, height / 2, 0), Enum.Material.Wood)
			for layer = 0, 2 do
				local size = 5.5 - layer * 1.4
				makeBall(parent, Vector3.new(size, size * 0.6, size), Color3.fromRGB(70, 120, 95),
					CFrame.new(pos + Vector3.new(0, height + layer * 1.4, 0)), Enum.Material.Grass)
			end
			makeBall(parent, Vector3.new(2.2, 1, 2.2), Color3.fromRGB(240, 245, 250), CFrame.new(pos + Vector3.new(0, height + 3.6, 0)))
		end
	end
	-- Ice spikes
	for _ = 1, 12 do
		local pos = randomGroundPoint(biome, rng, 25, 180)
		if pos then
			local height = rng:NextNumber(3, 9)
			local spike = makeBall(parent, Vector3.new(1.7, height, 1.7), Color3.fromRGB(190, 230, 250),
				CFrame.new(pos + Vector3.new(0, height / 2, 0)) * CFrame.Angles(rng:NextNumber(-0.1, 0.1), 0, rng:NextNumber(-0.1, 0.1)), Enum.Material.Ice)
			spike.Transparency = 0.2
		end
	end
	-- GIANT ice wall slabs up in the mountain ring (the "wow" up high)
	for i = 1, 10 do
		local angle = math.pi * 0.6 + (i / 10) * math.pi * 0.9 -- the western arc
		local radius = rng:NextNumber(170, 215)
		local x = biome.Center.X + math.cos(angle) * radius
		local z = biome.Center.Z + math.sin(angle) * radius
		local y = groundAt(x, z)
		local slab = makePart(parent, {
			Size = Vector3.new(rng:NextNumber(18, 30), rng:NextNumber(24, 40), rng:NextNumber(4, 7)),
			Color = Color3.fromRGB(175, 220, 245),
			Material = Enum.Material.Glacier,
			Transparency = 0.15,
			CFrame = CFrame.new(x, y + 10, z) * CFrame.Angles(rng:NextNumber(-0.08, 0.08), angle + math.rad(90), rng:NextNumber(-0.08, 0.08)),
		})
		slab.CastShadow = true -- these are big enough to earn shadows
	end
	-- Frozen pond near the heart
	local pondX, pondZ = biome.Center.X + 40, biome.Center.Z + 55
	workspace.Terrain:FillCylinder(CFrame.new(pondX, groundAt(pondX, pondZ) - 0.4, pondZ), 1.2, 14, Enum.Material.Glacier)
	addEggPoint("Tundra", Vector3.new(pondX, groundAt(pondX, pondZ), pondZ))

	collectGroundPoints(biome, rng, 12, 25, 170)
end

local function buildVolcanic(parent: Instance, biome, rng: Random)
	-- Obsidian spikes + dark boulders on the lower slopes
	for _ = 1, 14 do
		local pos = randomGroundPoint(biome, rng, 60, biome.Radius - 40)
		if pos then
			local height = rng:NextNumber(4, 10)
			makeBall(parent, Vector3.new(2.2, height, 2.2), Color3.fromRGB(45, 42, 48),
				CFrame.new(pos + Vector3.new(0, height / 2, 0)) * CFrame.Angles(rng:NextNumber(-0.15, 0.15), 0, rng:NextNumber(-0.15, 0.15)), Enum.Material.Slate)
		end
	end
	-- Ember vents
	for _ = 1, 6 do
		local pos = randomGroundPoint(biome, rng, 50, 160)
		if pos then
			local vent = makePart(parent, {
				Size = Vector3.new(2.4, 0.6, 2.4),
				Color = Color3.fromRGB(70, 60, 60),
				Material = Enum.Material.Slate,
				CFrame = CFrame.new(pos + Vector3.new(0, 0.3, 0)),
			})
			local fire = Instance.new("Fire")
			fire.Size = 4
			fire.Parent = vent
		end
	end
	-- Crater rim: a smoke column billowing from the volcano's throat
	local rimY = groundAt(biome.Center.X, biome.Center.Z - 12)
	local smokeAnchor = makePart(parent, {
		Size = Vector3.new(2, 2, 2),
		Transparency = 1,
		CanCollide = false,
		CFrame = CFrame.new(biome.Center.X, rimY + 6, biome.Center.Z),
	})
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(90, 85, 82), Color3.fromRGB(150, 145, 140))
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	smoke.Rate = 6
	smoke.Lifetime = NumberRange.new(4, 7)
	smoke.Speed = NumberRange.new(6, 10)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 14) })
	smoke.Parent = smokeAnchor

	-- Two lava falls: glowing streams down the flank
	for _, angle in { math.rad(140), math.rad(300) } do
		local dir = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local top = biome.Center + dir * 30
		local bottom = biome.Center + dir * 125
		local topY = groundAt(top.X, top.Z) - 1
		local bottomY = groundAt(bottom.X, bottom.Z) - 0.5
		local mid = (Vector3.new(top.X, topY, top.Z) + Vector3.new(bottom.X, bottomY, bottom.Z)) / 2
		local length = (Vector3.new(top.X, topY, top.Z) - Vector3.new(bottom.X, bottomY, bottom.Z)).Magnitude
		local stream = makePart(parent, {
			Size = Vector3.new(4, 0.8, length),
			Color = Color3.fromRGB(255, 120, 40),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CFrame = CFrame.lookAt(mid, Vector3.new(bottom.X, bottomY, bottom.Z)),
		})
		local glow = Instance.new("PointLight")
		glow.Color = Color3.fromRGB(255, 130, 50)
		glow.Brightness = 1.4
		glow.Range = 18
		glow.Parent = stream
		-- A lava pool where the fall lands
		workspace.Terrain:FillCylinder(CFrame.new(bottom.X, bottomY - 0.6, bottom.Z), 1.4, 8, Enum.Material.CrackedLava)
	end

	-- One brave egg point at the crater rim (the risky prize spot)
	addEggPoint("Volcanic", Vector3.new(biome.Center.X, groundAt(biome.Center.X, biome.Center.Z - 28), biome.Center.Z - 28))
	collectGroundPoints(biome, rng, 11, 50, 170)
end

local function buildSky(parent: Instance, biome, rng: Random)
	local c = biome.Center
	local discs = {
		{ Offset = Vector3.zero, Radius = 55 },
		{ Offset = Vector3.new(80, 8, 30), Radius = 26 },
		{ Offset = Vector3.new(-70, -6, -35), Radius = 22 },
	}
	for _, disc in discs do
		local center = c + disc.Offset
		workspace.Terrain:FillCylinder(CFrame.new(center.X, center.Y - 3, center.Z), 6, disc.Radius, Enum.Material.Grass)
		workspace.Terrain:FillBall(center - Vector3.new(0, 8, 0), disc.Radius * 0.55, Enum.Material.Rock)
		for _ = 1, 4 do
			local angle = rng:NextNumber(0, math.pi * 2)
			local puff = makeBall(parent, Vector3.new(8, 3.5, 8), Color3.fromRGB(250, 250, 255),
				CFrame.new(center + Vector3.new(math.cos(angle) * (disc.Radius + 6), rng:NextNumber(-4, 2), math.sin(angle) * (disc.Radius + 6))))
			puff.Transparency = 0.35
		end
	end
	for _, target in { discs[2], discs[3] } do
		local fromPos = c + (target.Offset.Unit * 50) + Vector3.new(0, 0.4, 0)
		local toPos = c + target.Offset - (target.Offset.Unit * (target.Radius - 3)) + Vector3.new(0, 0.4, 0)
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
	for _ = 1, 6 do
		local pos = c + Vector3.new(rng:NextNumber(-45, 45), rng:NextNumber(4, 12), rng:NextNumber(-45, 45))
		local crystal = makePart(parent, {
			Size = Vector3.new(1, 1.6, 1),
			Color = Color3.fromRGB(190, 215, 255),
			Material = Enum.Material.Neon,
			CanCollide = false,
			CFrame = CFrame.new(pos) * CFrame.Angles(math.rad(45), rng:NextNumber(0, 3), math.rad(45)),
		})
		crystal.Transparency = 0.25
	end
	for _ = 1, 8 do
		local angle = rng:NextNumber(0, math.pi * 2)
		local radius = rng:NextNumber(8, 45)
		addEggPoint("Sky", c + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius))
	end
	addEggPoint("Sky", c + discs[2].Offset)
	addEggPoint("Sky", c + discs[3].Offset)
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

-- Which biome does a world position belong to? (nearest center)
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

function BiomeGenerator.build()
	local rng = Random.new(GameConfig.Forest.Seed + 4)
	local regions = Instance.new("Model")
	regions.Name = "Biomes"

	local decorators = {
		Desert = buildDesert,
		Tundra = buildTundra,
		Volcanic = buildVolcanic,
		Sky = buildSky,
	}

	for _, biome in GameConfig.Biomes do
		local decorate = decorators[biome.Name]
		if decorate then
			decorate(regions, biome, rng)
		end

		buildSanctuaryPads(regions, biome)
		buildGateWall(regions, biome)

		local arrival = TerrainForge.getArrival(biome.Name)
		travelTargets[biome.Name] = CFrame.new(arrival + Vector3.new(0, 3, 0))
		if biome.Name == "Forest" then
			buildTravelHub(regions, "Forest", Vector3.new(16, 0, 20))
			buildGuideNPC(regions, "Forest", Vector3.new(-10, 0, 16))
		else
			buildTravelHub(regions, biome.Name, arrival + Vector3.new(8, 0, 6))
			buildGuideNPC(regions, biome.Name, arrival + Vector3.new(-8, 0, 4))
		end
	end

	regions.Parent = workspace
end

return BiomeGenerator
