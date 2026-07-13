--[[
	BaseBuilder — constructs one player cabin (a "base") at a village plot.

	Called by BaseUpgradeService whenever a base needs (re)building: on claim,
	and after buying any aesthetic upgrade or extra hatch slot. The whole cabin
	is rebuilt from scratch each time — simple, and it makes upgrades feel
	dramatic because the building visibly transforms.

	Tiers (GameConfig.BaseUpgrades "BaseTier"):
	  1 Starter Cabin  — snug box + gable roof
	  2 Cozy Cabin     — bigger, porch with posts, chimney, flower boxes
	  3 Grand Treehouse Annex — adds a tower with its own mini-canopy

	Also builds the row of HATCH PADS in front (one per unlocked slot) and
	returns their world positions so HatchService knows where eggs sit.
]]

local BaseBuilder = {}

local WOOD = Color3.fromRGB(150, 108, 70)
local DARK_WOOD = Color3.fromRGB(108, 75, 50)
local ROOF = Color3.fromRGB(165, 80, 60)
local STONE = Color3.fromRGB(150, 148, 145)

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

local function makeWedge(parent: Instance, props: { [string]: any }): WedgePart
	local wedge = Instance.new("WedgePart")
	wedge.Anchored = true
	wedge.Material = Enum.Material.Wood
	for key, value in props do
		(wedge :: any)[key] = value
	end
	wedge.Parent = parent
	return wedge
end

local function addLight(parent: BasePart, color: Color3, range: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = 1.2
	light.Range = range
	light.Parent = parent
end

-- One glowing lantern hung at an offset from the cabin origin
local function buildLantern(parent: Instance, origin: CFrame, offset: Vector3)
	local lantern = makePart(parent, {
		Size = Vector3.new(0.6, 0.8, 0.6),
		Color = Color3.fromRGB(255, 215, 130),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CFrame = origin * CFrame.new(offset),
	})
	addLight(lantern, Color3.fromRGB(255, 210, 140), 10)
end

-- The main cabin body: shared by all tiers, scaled up per tier
local function buildCabinBody(model: Model, origin: CFrame, tier: number)
	local width = 8 + (tier - 1) * 2 -- 8 / 10 / 12
	local depth = 7 + (tier - 1) * 1.5
	local height = 5.5 + (tier - 1)

	-- Walls (one box), floor slab, door, window
	makePart(model, {
		Size = Vector3.new(width, height, depth),
		Color = WOOD,
		CFrame = origin * CFrame.new(0, height / 2, -depth / 2 - 2),
	})
	makePart(model, {
		Name = "Door",
		Size = Vector3.new(2.2, 3.6, 0.3),
		Color = DARK_WOOD,
		CanCollide = false,
		CFrame = origin * CFrame.new(0, 1.8, -1.95),
	})
	makePart(model, {
		Name = "Window",
		Size = Vector3.new(1.8, 1.8, 0.3),
		Color = Color3.fromRGB(255, 235, 170),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CFrame = origin * CFrame.new(width / 4 + 0.5, 3.2, -1.95),
	})

	-- Gable roof: two big wedges leaning together
	for _, side in { -1, 1 } do
		makeWedge(model, {
			Size = Vector3.new(width + 1.2, 2.6, (depth + 1.2) / 2),
			Color = ROOF,
			Material = Enum.Material.SmoothPlastic,
			CFrame = origin
				* CFrame.new(0, height + 1.3, -depth / 2 - 2 + side * (depth + 1.2) / 4)
				* CFrame.Angles(0, side == 1 and math.pi or 0, 0),
		})
	end

	return width, depth, height
end

-- Tier 2+: porch with posts and an awning
local function buildPorch(model: Model, origin: CFrame, width: number)
	makePart(model, {
		Size = Vector3.new(width, 0.4, 3.4),
		Color = DARK_WOOD,
		CFrame = origin * CFrame.new(0, 0.35, 0),
	})
	for _, side in { -1, 1 } do
		makePart(model, {
			Size = Vector3.new(0.4, 3.4, 0.4),
			Color = DARK_WOOD,
			CFrame = origin * CFrame.new(side * (width / 2 - 0.5), 2.1, 1.3),
		})
	end
	makePart(model, {
		Size = Vector3.new(width + 0.6, 0.3, 3.8),
		Color = ROOF,
		Material = Enum.Material.SmoothPlastic,
		CFrame = origin * CFrame.new(0, 4, 0.4) * CFrame.Angles(math.rad(-8), 0, 0),
	})
	-- Flower boxes for coziness
	for _, side in { -1, 1 } do
		makePart(model, {
			Size = Vector3.new(1.6, 0.5, 0.6),
			Color = DARK_WOOD,
			CanCollide = false,
			CFrame = origin * CFrame.new(side * 2.6, 0.85, 0.8),
		})
		for f = -1, 1 do
			local flower = makePart(model, {
				Size = Vector3.new(0.35, 0.35, 0.35),
				Color = f == 0 and Color3.fromRGB(255, 130, 150) or Color3.fromRGB(255, 205, 95),
				Material = Enum.Material.SmoothPlastic,
				CanCollide = false,
				CFrame = origin * CFrame.new(side * 2.6 + f * 0.45, 1.25, 0.8),
			})
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = flower
		end
	end
end

-- Tier 2+: a little stone chimney with smoke
local function buildChimney(model: Model, origin: CFrame, width: number, height: number)
	local chimney = makePart(model, {
		Size = Vector3.new(1.6, height + 3.4, 1.6),
		Color = STONE,
		Material = Enum.Material.Slate,
		CFrame = origin * CFrame.new(width / 2 - 0.4, (height + 3.4) / 2, -5),
	})
	local smoke = Instance.new("ParticleEmitter")
	smoke.Color = ColorSequence.new(Color3.fromRGB(200, 198, 195))
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	smoke.Rate = 2
	smoke.Lifetime = NumberRange.new(2, 3)
	smoke.Speed = NumberRange.new(1.5, 2.5)
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2.2) })
	smoke.Parent = chimney
end

-- Tier 3: the treehouse annex tower with its own mini-canopy
local function buildAnnexTower(model: Model, origin: CFrame, width: number)
	local towerX = -(width / 2 + 2.2)
	makePart(model, {
		Size = Vector3.new(4, 11, 4),
		Color = WOOD,
		CFrame = origin * CFrame.new(towerX, 5.5, -5),
	})
	makePart(model, {
		Name = "TowerWindow",
		Size = Vector3.new(1.4, 1.4, 0.3),
		Color = Color3.fromRGB(255, 235, 170),
		Material = Enum.Material.Neon,
		CanCollide = false,
		CFrame = origin * CFrame.new(towerX, 8.6, -2.9),
	})
	-- Mini canopy on top — the "treehouse" in the annex
	for _, offset in { Vector3.new(0, 12.6, 0), Vector3.new(1.6, 12, -1), Vector3.new(-1.4, 12.2, 1) } do
		local leaves = makePart(model, {
			Size = Vector3.new(5, 3.4, 5),
			Color = Color3.fromRGB(95, 165, 88),
			Material = Enum.Material.Grass,
			CanCollide = false,
			CFrame = origin * CFrame.new(towerX + offset.X, offset.Y, -5 + offset.Z),
		})
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = leaves
	end
end

-- ------------------------------------------------------------
-- Public: build (or rebuild) a full base at a plot
-- ------------------------------------------------------------

export type BaseLook = {
	Tier: number, -- BaseTier level (1..3)
	Slots: number, -- number of hatch pads to lay out
	Lanterns: boolean,
	Banner: boolean,
	FancyFirepit: boolean,
}

-- plotCFrame: position at the plot, facing the village center.
-- Returns the model and the world positions of the hatch pads (index = slot).
function BaseBuilder.build(parent: Instance, plotCFrame: CFrame, look: BaseLook, ownerName: string?): (Model, { Vector3 })
	local model = Instance.new("Model")
	model.Name = "Base"

	-- Cabin sits BEHIND the plot point (away from the village), pads in front
	local origin = plotCFrame * CFrame.Angles(0, math.pi, 0) -- door faces the village

	local width, _, height = buildCabinBody(model, origin, look.Tier)
	if look.Tier >= 2 then
		buildPorch(model, origin, width)
		buildChimney(model, origin, width, height)
	end
	if look.Tier >= 3 then
		buildAnnexTower(model, origin, width)
	end

	-- Owner sign beside the door
	local sign = makePart(model, {
		Size = Vector3.new(2.6, 1, 0.25),
		Color = DARK_WOOD,
		CFrame = origin * CFrame.new(-width / 4 - 0.6, 2.6, -1.9),
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 235, 200)
	label.Text = ownerName and (ownerName .. "'s Base") or "Unclaimed"
	label.Parent = gui

	-- Decor unlocks
	if look.Lanterns then
		buildLantern(model, origin, Vector3.new(2, 4.2, -1.6))
		buildLantern(model, origin, Vector3.new(-2, 4.2, -1.6))
	end
	if look.Banner then
		makePart(model, {
			Size = Vector3.new(0.25, 6.5, 0.25),
			Color = DARK_WOOD,
			CFrame = origin * CFrame.new(width / 2 + 1.4, 3.25, 0.5),
		})
		makePart(model, {
			Size = Vector3.new(0.15, 2.6, 1.6),
			Color = Color3.fromRGB(90, 170, 220),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			CFrame = origin * CFrame.new(width / 2 + 1.4, 5.2, 1.45),
		})
	end
	if look.FancyFirepit then
		local pitPos = origin * CFrame.new(width / 2 + 3, 0, 2)
		for i = 1, 6 do
			local angle = (i / 6) * math.pi * 2
			local stone = makePart(model, {
				Size = Vector3.new(0.9, 0.7, 0.7),
				Color = STONE,
				Material = Enum.Material.Slate,
				CanCollide = false,
				CFrame = pitPos * CFrame.new(math.cos(angle) * 1.3, 0.3, math.sin(angle) * 1.3),
			})
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = stone
		end
		local core = makePart(model, {
			Size = Vector3.new(0.8, 0.8, 0.8),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CFrame = pitPos * CFrame.new(0, 0.7, 0),
		})
		local fire = Instance.new("Fire")
		fire.Size = 4
		fire.Parent = core
		addLight(core, Color3.fromRGB(255, 170, 90), 14)
	end

	-- Hatch pads: a row of glowing stone discs in FRONT of the cabin
	-- (between the cabin and the village walkway) — one per unlocked slot
	local padPositions: { Vector3 } = {}
	for slot = 1, look.Slots do
		local offsetX = (slot - (look.Slots + 1) / 2) * 3.2
		local padCFrame = origin * CFrame.new(offsetX, 0, 3.6)
		-- Cylinder axis runs along X, so X = thickness, Y/Z = diameter
		local pad = makePart(model, {
			Name = "HatchPad" .. slot,
			Size = Vector3.new(0.4, 2.6, 2.6),
			Color = Color3.fromRGB(210, 205, 195),
			Material = Enum.Material.Slate,
			CFrame = padCFrame * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
		})
		pad.Shape = Enum.PartType.Cylinder
		local ring = makePart(model, {
			Size = Vector3.new(0.1, 3, 3),
			Color = Color3.fromRGB(255, 235, 160),
			Material = Enum.Material.Neon,
			Transparency = 0.5,
			CanCollide = false,
			CFrame = padCFrame * CFrame.new(0, 0.42, 0) * CFrame.Angles(0, 0, math.rad(90)),
		})
		ring.Shape = Enum.PartType.Cylinder
		table.insert(padPositions, padCFrame.Position + Vector3.new(0, 0.45, 0))
	end

	model.Parent = parent
	return model, padPositions
end

return BaseBuilder
