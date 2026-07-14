--[[
	SanctuaryBuilder — primitive-part models for every placeable sanctuary
	object in GameConfig.SanctuaryObjects.

	SHARED on purpose: the SERVER builds the real objects; the CLIENT builds
	translucent GHOST copies for placement previews. One builder, no drift.

	Every model stands on y = 0 at its own center, facing -Z, so callers
	just :PivotTo() it. Habitats expose "PetSpot" parts — the server parks
	placed pets on them.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.GameConfig)

local SanctuaryBuilder = {}

local WOOD = Color3.fromRGB(150, 108, 70)
local DARK_WOOD = Color3.fromRGB(110, 78, 52)

local function makePart(model: Instance, props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CastShadow = false
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = model
	return part
end

local function makeBall(model: Instance, size: Vector3, color: Color3, cframe: CFrame, material: Enum.Material?): Part
	local part = makePart(model, {
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

local function tile(model: Instance, color: Color3, material: Enum.Material, size: number?)
	local width = size or 8
	makePart(model, {
		Size = Vector3.new(width, 0.4, width),
		Color = color,
		Material = material,
		CFrame = CFrame.new(0, 0.2, 0),
	})
end

-- Fenced habitat pen: themed floor + 4 rails + pet spots
local function pen(model: Instance, floorColor: Color3, floorMaterial: Enum.Material, accentBuilder: ((Instance) -> ())?)
	makePart(model, {
		Size = Vector3.new(12, 0.5, 12),
		Color = floorColor,
		Material = floorMaterial,
		CFrame = CFrame.new(0, 0.25, 0),
	})
	for _, side in { -1, 1 } do
		for _, axis in { "X", "Z" } do
			local cf = axis == "X" and CFrame.new(side * 6, 1.3, 0) or CFrame.new(0, 1.3, side * 6)
			local size = axis == "X" and Vector3.new(0.4, 0.4, 12.4) or Vector3.new(12.4, 0.4, 0.4)
			makePart(model, { Size = size, Color = WOOD, Material = Enum.Material.Wood, CFrame = cf, CanCollide = false })
		end
	end
	for _, dx in { -6, 6 } do
		for _, dz in { -6, 6 } do
			makePart(model, {
				Size = Vector3.new(0.7, 2, 0.7),
				Color = DARK_WOOD,
				Material = Enum.Material.Wood,
				CFrame = CFrame.new(dx, 1, dz),
				CanCollide = false,
			})
		end
	end
	-- Where placed pets stand (capacity comes from GameConfig)
	for i = 1, GameConfig.Sanctuary.HabitatCapacity do
		local spot = makePart(model, {
			Name = "PetSpot",
			Size = Vector3.new(1, 0.2, 1),
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CFrame = CFrame.new((i - (GameConfig.Sanctuary.HabitatCapacity + 1) / 2) * 5, 0.6, 0),
		})
		spot:SetAttribute("SpotIndex", i)
	end
	if accentBuilder then
		accentBuilder(model)
	end
end

-- ------------------------------------------------------------
-- The catalog: one builder per SanctuaryObjects key
-- ------------------------------------------------------------

local builders: { [string]: (Model) -> () } = {}

-- Terrain tiles
builders.GrassTile = function(m) tile(m, Color3.fromRGB(95, 170, 90), Enum.Material.Grass) end
builders.SandTile = function(m) tile(m, Color3.fromRGB(228, 200, 140), Enum.Material.Sand) end
builders.SnowTile = function(m) tile(m, Color3.fromRGB(235, 240, 248), Enum.Material.Snow) end
builders.PathTile = function(m) tile(m, Color3.fromRGB(165, 160, 150), Enum.Material.Slate, 6) end
builders.WaterTile = function(m)
	local water = makePart(m, {
		Size = Vector3.new(8, 0.5, 8),
		Color = Color3.fromRGB(90, 160, 210),
		Material = Enum.Material.Glass,
		Transparency = 0.35,
		CFrame = CFrame.new(0, 0.25, 0),
	})
	water.CanCollide = true
end
builders.Hill = function(m)
	makeBall(m, Vector3.new(11, 3.5, 11), Color3.fromRGB(100, 172, 92), CFrame.new(0, 0.6, 0), Enum.Material.Grass).CanCollide = true
end

-- Habitats (matched-biome pens)
builders.ForestPen = function(m)
	pen(m, Color3.fromRGB(95, 170, 90), Enum.Material.Grass, function(inner)
		makeBall(inner, Vector3.new(2.2, 2.8, 2.2), Color3.fromRGB(76, 145, 76), CFrame.new(4, 1.6, -4), Enum.Material.Grass)
	end)
end
builders.DesertPen = function(m)
	pen(m, Color3.fromRGB(228, 200, 140), Enum.Material.Sand, function(inner)
		local cactus = makePart(inner, { Size = Vector3.new(0.9, 2.6, 0.9), Color = Color3.fromRGB(90, 155, 80), Material = Enum.Material.Grass, CFrame = CFrame.new(4, 1.5, -4), CanCollide = false })
		cactus.Shape = Enum.PartType.Cylinder
		cactus.CFrame = CFrame.new(4, 1.5, -4) * CFrame.Angles(0, 0, math.rad(90))
	end)
end
builders.TundraPen = function(m)
	pen(m, Color3.fromRGB(235, 240, 248), Enum.Material.Snow, function(inner)
		local spike = makeBall(inner, Vector3.new(1.2, 3, 1.2), Color3.fromRGB(190, 230, 250), CFrame.new(4, 1.6, -4), Enum.Material.Ice)
		spike.Transparency = 0.2
	end)
end
builders.VolcanicPen = function(m)
	pen(m, Color3.fromRGB(70, 62, 62), Enum.Material.Basalt, function(inner)
		local ember = makeBall(inner, Vector3.new(1.6, 1.2, 1.6), Color3.fromRGB(255, 120, 40), CFrame.new(4, 0.9, -4), Enum.Material.Neon)
		ember.Transparency = 0.2
	end)
end
builders.SkyPen = function(m)
	pen(m, Color3.fromRGB(200, 225, 255), Enum.Material.Grass, function(inner)
		makeBall(inner, Vector3.new(2.6, 1.2, 2.6), Color3.fromRGB(250, 250, 255), CFrame.new(4, 2.6, -4)).Transparency = 0.3
	end)
end

-- Decor
builders.TreeProp = function(m)
	local trunk = makePart(m, { Size = Vector3.new(4.5, 1.2, 1.2), Color = Color3.fromRGB(115, 82, 58), Material = Enum.Material.Wood, CFrame = CFrame.new(0, 2.25, 0) * CFrame.Angles(0, 0, math.rad(90)) })
	trunk.Shape = Enum.PartType.Cylinder
	makeBall(m, Vector3.new(5, 4, 5), Color3.fromRGB(88, 158, 82), CFrame.new(0, 5.2, 0), Enum.Material.Grass)
	makeBall(m, Vector3.new(3.4, 2.8, 3.4), Color3.fromRGB(104, 176, 90), CFrame.new(0.8, 6.6, 0.6), Enum.Material.Grass)
end
builders.CactusProp = function(m)
	local trunk = makePart(m, { Size = Vector3.new(4, 1, 1), Color = Color3.fromRGB(90, 155, 80), Material = Enum.Material.Grass, CFrame = CFrame.new(0, 2, 0) * CFrame.Angles(0, 0, math.rad(90)) })
	trunk.Shape = Enum.PartType.Cylinder
	local arm = makePart(m, { Size = Vector3.new(1.6, 0.7, 0.7), Color = Color3.fromRGB(90, 155, 80), Material = Enum.Material.Grass, CFrame = CFrame.new(0.85, 2.2, 0) * CFrame.Angles(0, 0, math.rad(90)), CanCollide = false })
	arm.Shape = Enum.PartType.Cylinder
end
builders.IceSpike = function(m)
	local spike = makeBall(m, Vector3.new(1.7, 6, 1.7), Color3.fromRGB(190, 230, 250), CFrame.new(0, 3, 0), Enum.Material.Ice)
	spike.Transparency = 0.2
	spike.CanCollide = true
end
builders.EmberRock = function(m)
	makeBall(m, Vector3.new(3, 2, 3), Color3.fromRGB(55, 50, 54), CFrame.new(0, 0.9, 0), Enum.Material.Slate).CanCollide = true
	makeBall(m, Vector3.new(1.4, 0.8, 1.4), Color3.fromRGB(255, 120, 40), CFrame.new(0, 2, 0), Enum.Material.Neon)
end
builders.CloudPuff = function(m)
	makeBall(m, Vector3.new(4.5, 2, 4.5), Color3.fromRGB(250, 250, 255), CFrame.new(0, 2.4, 0)).Transparency = 0.3
end
builders.RockProp = function(m)
	makeBall(m, Vector3.new(3.4, 2.2, 3), Color3.fromRGB(145, 145, 150), CFrame.new(0, 1, 0), Enum.Material.Slate).CanCollide = true
end
builders.Fence = function(m)
	makePart(m, { Size = Vector3.new(6, 0.35, 0.35), Color = WOOD, Material = Enum.Material.Wood, CFrame = CFrame.new(0, 1.4, 0), CanCollide = false })
	makePart(m, { Size = Vector3.new(6, 0.35, 0.35), Color = WOOD, Material = Enum.Material.Wood, CFrame = CFrame.new(0, 0.7, 0), CanCollide = false })
	for _, dx in { -2.8, 2.8 } do
		makePart(m, { Size = Vector3.new(0.6, 2, 0.6), Color = DARK_WOOD, Material = Enum.Material.Wood, CFrame = CFrame.new(dx, 1, 0) })
	end
end
builders.Bench = function(m)
	makePart(m, { Size = Vector3.new(4, 0.4, 1.4), Color = WOOD, Material = Enum.Material.Wood, CFrame = CFrame.new(0, 1, 0) })
	for _, dx in { -1.6, 1.6 } do
		makePart(m, { Size = Vector3.new(0.5, 1, 1.2), Color = DARK_WOOD, Material = Enum.Material.Wood, CFrame = CFrame.new(dx, 0.5, 0) })
	end
end
builders.LanternProp = function(m)
	makePart(m, { Size = Vector3.new(0.35, 3.6, 0.35), Color = DARK_WOOD, Material = Enum.Material.Wood, CFrame = CFrame.new(0, 1.8, 0) })
	local glow = makePart(m, { Size = Vector3.new(0.9, 1, 0.9), Color = Color3.fromRGB(255, 220, 130), Material = Enum.Material.Neon, CFrame = CFrame.new(0, 3.9, 0), CanCollide = false })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 215, 140)
	light.Brightness = 1
	light.Range = 12
	light.Parent = glow
end
builders.SignProp = function(m)
	makePart(m, { Size = Vector3.new(0.4, 2.6, 0.4), Color = DARK_WOOD, Material = Enum.Material.Wood, CFrame = CFrame.new(0, 1.3, 0) })
	makePart(m, { Size = Vector3.new(2.6, 1.2, 0.3), Color = WOOD, Material = Enum.Material.Wood, CFrame = CFrame.new(0, 2.4, 0), CanCollide = false })
end
builders.Arch = function(m)
	for _, dx in { -2.4, 2.4 } do
		makePart(m, { Size = Vector3.new(0.8, 5, 0.8), Color = WOOD, Material = Enum.Material.Wood, CFrame = CFrame.new(dx, 2.5, 0) })
	end
	makePart(m, { Size = Vector3.new(6.4, 0.8, 0.8), Color = DARK_WOOD, Material = Enum.Material.Wood, CFrame = CFrame.new(0, 5.2, 0), CanCollide = false })
	makeBall(m, Vector3.new(1.4, 1, 1.4), Color3.fromRGB(120, 190, 100), CFrame.new(-2.4, 5.7, 0), Enum.Material.Grass)
	makeBall(m, Vector3.new(1.4, 1, 1.4), Color3.fromRGB(120, 190, 100), CFrame.new(2.4, 5.7, 0), Enum.Material.Grass)
end

-- ------------------------------------------------------------
-- Public API
-- ------------------------------------------------------------

function SanctuaryBuilder.create(key: string): Model?
	local builder = builders[key]
	if not builder then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = key
	builder(model)
	-- A primary part helps PivotTo behave predictably
	model.PrimaryPart = model:FindFirstChildWhichIsA("BasePart")
	return model
end

-- Ghost version for the client's placement preview
function SanctuaryBuilder.createGhost(key: string): Model?
	local model = SanctuaryBuilder.create(key)
	if not model then
		return nil
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.Transparency = math.clamp(0.55 + descendant.Transparency * 0.4, 0.55, 0.95)
		elseif descendant:IsA("Light") or descendant:IsA("ParticleEmitter") then
			descendant:Destroy()
		end
	end
	return model
end

return SanctuaryBuilder
