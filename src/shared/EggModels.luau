--[[
	EggModels — builds every egg from primitives, styled per egg type from
	GameConfig (color, glow intensity). Used three ways:
	  * server: world eggs scattered around the island
	  * server: incubating eggs sitting on hatchery slot pads
	  * client: the temporary egg that wobbles and pops in the hatch reveal

	Models stand on y = 0; position with :PivotTo(). Rarer egg types glow
	and shimmer harder so spotting one across a clearing is a thrill.
]]

local GameConfig = require(script.Parent.GameConfig)

local EggModels = {}

-- Speckle offsets (fractions of the shell size) — same pattern every egg,
-- which reads as a deliberate design rather than noise.
local SPECKLES = {
	Vector3.new(0.25, 0.2, -0.32),
	Vector3.new(-0.3, 0.05, -0.28),
	Vector3.new(0.05, -0.18, -0.38),
	Vector3.new(-0.15, 0.32, 0.28),
	Vector3.new(0.3, -0.05, 0.3),
}

function EggModels.create(eggName: string): Model
	local egg = GameConfig.EggByName[eggName]
	assert(egg, "Unknown egg type: " .. tostring(eggName))

	local model = Instance.new("Model")
	model.Name = eggName
	model:SetAttribute("EggType", eggName)

	local shell = Instance.new("Part")
	shell.Name = "Shell"
	shell.Size = Vector3.new(1.8, 2.3, 1.8)
	shell.Color = egg.Color
	shell.Material = Enum.Material.SmoothPlastic
	shell.Reflectance = 0.05
	shell.Anchored = true
	shell.CanCollide = false
	shell.CanQuery = true -- ProximityPrompts need to be able to see it
	shell.CFrame = CFrame.new(0, 1.15, 0)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = shell
	shell.Parent = model
	model.PrimaryPart = shell

	-- Darker speckles so eggs read as "natural" at a glance
	local speckleColor = Color3.new(egg.Color.R * 0.6, egg.Color.G * 0.6, egg.Color.B * 0.6)
	for i, offset in SPECKLES do
		local speckle = Instance.new("Part")
		speckle.Name = "Speckle"
		speckle.Size = Vector3.new(0.35, 0.28, 0.12)
		speckle.Color = speckleColor
		speckle.Material = Enum.Material.SmoothPlastic
		speckle.Anchored = true
		speckle.CanCollide = false
		speckle.CanQuery = false
		speckle.CFrame = shell.CFrame
			* CFrame.new(offset.X * shell.Size.X, offset.Y * shell.Size.Y, offset.Z * shell.Size.Z)
			* CFrame.Angles(0, math.rad(i * 37), 0)
		local speckleMesh = Instance.new("SpecialMesh")
		speckleMesh.MeshType = Enum.MeshType.Sphere
		speckleMesh.Parent = speckle
		speckle.Parent = model
	end

	-- Glow + shimmer scale with the egg's rarity (GlowIntensity from config)
	local glow = egg.GlowIntensity
	local light = Instance.new("PointLight")
	light.Color = egg.Color
	light.Brightness = 0.6 * glow
	light.Range = 6 + 3 * glow
	light.Parent = shell

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Name = "Shimmer"
	sparkle.Color = ColorSequence.new(egg.Color, Color3.new(1, 1, 1))
	sparkle.LightEmission = 1
	sparkle.Rate = 2 + 4 * glow
	sparkle.Lifetime = NumberRange.new(0.8, 1.6)
	sparkle.Speed = NumberRange.new(0.4, 1.2)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2 + 0.08 * glow),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparkle.Parent = shell

	return model
end

return EggModels
