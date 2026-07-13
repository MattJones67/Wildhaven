--[[
	AnimalModels — builds every animal out of basic Parts. No meshes, no
	toolbox assets. Each critter follows the same cute recipe: chunky body,
	oversized head, two big white eyes with dark pupils, and one or two
	silhouette features (ears / spikes / antlers) so you can tell them apart
	at a glance.

	Models are built ANCHORED and facing -Z (Roblox's "forward"), standing on
	y = 0, so callers can just :PivotTo() them wherever they want. They are
	display-only props — no collisions, no physics.

	Mutations restyle the model here too:
	  Shiny   -> glossy + sparkles
	  Golden  -> metallic gold
	  Rainbow -> parts tagged "RainbowPart"; a client-side loop cycles their hue
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local GameConfig = require(script.Parent.GameConfig)

local RAINBOW_TAG = "RainbowPart"
local GOLD = Color3.fromRGB(255, 200, 60)

local AnimalModels = {}

-- ------------------------------------------------------------
-- Part helpers
-- ------------------------------------------------------------

local function makePart(model: Model, props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Material = Enum.Material.SmoothPlastic
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = model
	return part
end

-- A sphere (Ball shape stays perfectly round; for stretched blobs we use a
-- normal Part with a sphere SpecialMesh so it can be egg/pill shaped).
local function ball(model: Model, name: string, size: Vector3, color: Color3, cframe: CFrame): Part
	local part = makePart(model, { Name = name, Size = size, Color = color, CFrame = cframe })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

local function cylinder(model: Model, name: string, size: Vector3, color: Color3, cframe: CFrame): Part
	local part = makePart(model, { Name = name, Size = size, Color = color, CFrame = cframe })
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- Two big white eyes + dark pupils on the front (-Z side) of a head part.
-- This is 80% of the cuteness. Eye parts are named so mutations skip them.
local function addEyes(model: Model, headCFrame: CFrame, headRadius: number, eyeScale: number?)
	local scale = eyeScale or 1
	local eyeSize = headRadius * 0.55 * scale
	local forward = -headRadius * 0.72
	for _, side in { -1, 1 } do
		local x = side * headRadius * 0.38
		local eyeCF = headCFrame * CFrame.new(x, headRadius * 0.12, forward)
		ball(model, "Eye", Vector3.new(eyeSize, eyeSize, eyeSize * 0.6), Color3.new(1, 1, 1), eyeCF)
		ball(
			model,
			"Pupil",
			Vector3.new(eyeSize * 0.45, eyeSize * 0.45, eyeSize * 0.3),
			Color3.fromRGB(25, 25, 30),
			eyeCF * CFrame.new(0, 0, -eyeSize * 0.22)
		)
	end
end

-- ------------------------------------------------------------
-- Species builders. Each stands on y = 0, faces -Z, ~2-3.5 studs tall.
-- ------------------------------------------------------------

local builders: { [string]: (Model) -> () } = {}

builders["Bunny"] = function(model)
	local white = Color3.fromRGB(245, 242, 238)
	local pink = Color3.fromRGB(250, 180, 195)
	local body = ball(model, "Body", Vector3.new(1.9, 1.7, 2.1), white, CFrame.new(0, 0.85, 0.3))
	model.PrimaryPart = body
	local headCF = CFrame.new(0, 2, -0.5)
	ball(model, "Head", Vector3.new(1.8, 1.7, 1.7), white, headCF)
	addEyes(model, headCF, 0.85)
	ball(model, "Nose", Vector3.new(0.22, 0.16, 0.16), pink, headCF * CFrame.new(0, -0.18, -0.83))
	-- Signature: two tall upright ears with pink inners
	for _, side in { -1, 1 } do
		local earCF = headCF * CFrame.new(side * 0.42, 1.25, 0.1) * CFrame.Angles(0, 0, math.rad(side * 8))
		ball(model, "Ear", Vector3.new(0.45, 1.5, 0.35), white, earCF)
		ball(model, "EarInner", Vector3.new(0.22, 1, 0.2), pink, earCF * CFrame.new(0, 0, -0.09))
	end
	ball(model, "Tail", Vector3.new(0.6, 0.6, 0.6), Color3.new(1, 1, 1), CFrame.new(0, 0.9, 1.35))
end

builders["Hedgehog"] = function(model)
	local brown = Color3.fromRGB(150, 105, 70)
	local darkBrown = Color3.fromRGB(95, 62, 40)
	local cream = Color3.fromRGB(235, 215, 185)
	local body = ball(model, "Body", Vector3.new(2, 1.6, 2.4), brown, CFrame.new(0, 0.8, 0.2))
	model.PrimaryPart = body
	local headCF = CFrame.new(0, 1.35, -1.1) * CFrame.Angles(math.rad(-10), 0, 0)
	ball(model, "Head", Vector3.new(1.5, 1.35, 1.5), cream, headCF)
	addEyes(model, headCF, 0.72)
	ball(model, "Nose", Vector3.new(0.28, 0.24, 0.24), Color3.fromRGB(50, 35, 30), headCF * CFrame.new(0, -0.25, -0.72))
	-- Signature: a back full of chunky spikes (cones made from stretched balls)
	for row = 0, 2 do
		for col = -row, row, 2 do
			local spikeCF = CFrame.new(col * 0.4, 1.5 + row * 0.12, 0.1 + row * 0.55)
				* CFrame.Angles(math.rad(20 + row * 15), 0, 0)
			ball(model, "Spike", Vector3.new(0.4, 1.1, 0.4), darkBrown, spikeCF)
		end
	end
end

builders["Fox"] = function(model)
	local orange = Color3.fromRGB(235, 125, 55)
	local white = Color3.fromRGB(248, 244, 238)
	local body = ball(model, "Body", Vector3.new(1.8, 1.6, 2.3), orange, CFrame.new(0, 0.85, 0.35))
	model.PrimaryPart = body
	local headCF = CFrame.new(0, 2, -0.55)
	ball(model, "Head", Vector3.new(1.7, 1.55, 1.6), orange, headCF)
	addEyes(model, headCF, 0.8)
	ball(model, "Snout", Vector3.new(0.6, 0.45, 0.6), white, headCF * CFrame.new(0, -0.32, -0.75))
	ball(model, "Nose", Vector3.new(0.2, 0.18, 0.18), Color3.fromRGB(40, 30, 30), headCF * CFrame.new(0, -0.24, -1))
	-- Signature: tall pointy ears + a big bushy tail with a white tip
	for _, side in { -1, 1 } do
		local earCF = headCF * CFrame.new(side * 0.5, 0.95, 0.05) * CFrame.Angles(0, 0, math.rad(side * 14))
		ball(model, "Ear", Vector3.new(0.5, 1, 0.3), orange, earCF)
	end
	local tailCF = CFrame.new(0, 1.15, 1.75) * CFrame.Angles(math.rad(35), 0, 0)
	ball(model, "TailBase", Vector3.new(0.8, 1.6, 0.8), orange, tailCF)
	ball(model, "TailTip", Vector3.new(0.55, 0.7, 0.55), white, tailCF * CFrame.new(0, 0.85, 0))
end

builders["Fawn"] = function(model)
	local tan = Color3.fromRGB(200, 150, 100)
	local cream = Color3.fromRGB(240, 225, 200)
	local body = ball(model, "Body", Vector3.new(1.7, 1.5, 2.3), tan, CFrame.new(0, 1.6, 0.3))
	model.PrimaryPart = body
	-- Signature: four slender legs + white back spots + big soft ears
	for _, dx in { -0.55, 0.55 } do
		for _, dz in { -0.5, 1 } do
			cylinder(
				model,
				"Leg",
				Vector3.new(1.7, 0.35, 0.35),
				tan,
				CFrame.new(dx, 0.85, dz + 0.3) * CFrame.Angles(0, 0, math.rad(90))
			)
		end
	end
	local headCF = CFrame.new(0, 3, -0.6)
	ball(model, "Head", Vector3.new(1.5, 1.4, 1.4), tan, headCF)
	addEyes(model, headCF, 0.72, 1.05)
	ball(model, "Snout", Vector3.new(0.55, 0.4, 0.5), cream, headCF * CFrame.new(0, -0.32, -0.65))
	for _, side in { -1, 1 } do
		local earCF = headCF * CFrame.new(side * 0.72, 0.5, 0.1) * CFrame.Angles(0, 0, math.rad(side * 45))
		ball(model, "Ear", Vector3.new(0.35, 0.9, 0.25), tan, earCF)
		ball(model, "EarInner", Vector3.new(0.18, 0.55, 0.15), cream, earCF * CFrame.new(0, 0, -0.07))
	end
	for i = 1, 6 do -- white fawn spots along the back
		local angle = (i / 6) * math.pi * 2
		ball(
			model,
			"SpotMark",
			Vector3.new(0.3, 0.12, 0.3),
			cream,
			CFrame.new(math.cos(angle) * 0.55, 2.28 + math.sin(i) * 0.06, 0.3 + math.sin(angle) * 0.7)
		)
	end
end

builders["Owl"] = function(model)
	local feather = Color3.fromRGB(140, 115, 95)
	local cream = Color3.fromRGB(235, 220, 195)
	local body = ball(model, "Body", Vector3.new(2, 2.5, 1.9), feather, CFrame.new(0, 1.35, 0))
	model.PrimaryPart = body
	ball(model, "Belly", Vector3.new(1.5, 1.8, 1.2), cream, CFrame.new(0, 1.15, -0.45))
	-- Owls are one round blob: eyes go straight on the body, extra large
	local faceCF = CFrame.new(0, 1.95, 0)
	addEyes(model, faceCF, 1, 1.35)
	ball(model, "Beak", Vector3.new(0.3, 0.45, 0.3), Color3.fromRGB(240, 170, 60), faceCF * CFrame.new(0, -0.25, -0.92))
	-- Signature: ear tufts + folded wings + little feet
	for _, side in { -1, 1 } do
		ball(
			model,
			"Tuft",
			Vector3.new(0.4, 0.7, 0.35),
			feather,
			CFrame.new(side * 0.75, 2.75, 0) * CFrame.Angles(0, 0, math.rad(side * 25))
		)
		ball(
			model,
			"Wing",
			Vector3.new(0.5, 1.7, 1.2),
			Color3.fromRGB(110, 88, 70),
			CFrame.new(side * 1, 1.35, 0.15) * CFrame.Angles(0, 0, math.rad(side * 10))
		)
		ball(model, "Foot", Vector3.new(0.5, 0.25, 0.6), Color3.fromRGB(240, 170, 60), CFrame.new(side * 0.45, 0.12, -0.2))
	end
end

builders["Golden Stag"] = function(model)
	local gold = Color3.fromRGB(230, 180, 70)
	local brightGold = Color3.fromRGB(255, 215, 110)
	local body = ball(model, "Body", Vector3.new(1.9, 1.7, 2.7), gold, CFrame.new(0, 1.9, 0.3))
	model.PrimaryPart = body
	for _, dx in { -0.6, 0.6 } do
		for _, dz in { -0.6, 1.1 } do
			cylinder(
				model,
				"Leg",
				Vector3.new(2, 0.4, 0.4),
				gold,
				CFrame.new(dx, 1, dz + 0.3) * CFrame.Angles(0, 0, math.rad(90))
			)
		end
	end
	local headCF = CFrame.new(0, 3.4, -0.75)
	ball(model, "Head", Vector3.new(1.5, 1.4, 1.5), gold, headCF)
	addEyes(model, headCF, 0.72)
	ball(model, "Snout", Vector3.new(0.55, 0.4, 0.55), brightGold, headCF * CFrame.new(0, -0.3, -0.68))
	-- Signature: branching antlers built from thin cylinders
	for _, side in { -1, 1 } do
		local base = headCF * CFrame.new(side * 0.45, 0.6, 0.15)
		cylinder(
			model,
			"Antler",
			Vector3.new(1.4, 0.18, 0.18),
			brightGold,
			base * CFrame.new(side * 0.25, 0.55, 0) * CFrame.Angles(0, 0, math.rad(90 - side * 25))
		)
		cylinder(
			model,
			"Antler",
			Vector3.new(0.8, 0.14, 0.14),
			brightGold,
			base * CFrame.new(side * 0.55, 1, 0) * CFrame.Angles(0, 0, math.rad(90 - side * 65))
		)
		cylinder(
			model,
			"Antler",
			Vector3.new(0.7, 0.14, 0.14),
			brightGold,
			base * CFrame.new(side * 0.1, 1.15, 0) * CFrame.Angles(0, 0, math.rad(90 + side * 10))
		)
	end
end

builders["Squirrel"] = function(model)
	local russet = Color3.fromRGB(190, 110, 60)
	local cream = Color3.fromRGB(240, 220, 190)
	local body = ball(model, "Body", Vector3.new(1.4, 1.3, 1.6), russet, CFrame.new(0, 0.65, 0.2))
	model.PrimaryPart = body
	ball(model, "Belly", Vector3.new(0.9, 0.9, 0.7), cream, CFrame.new(0, 0.6, -0.35))
	local headCF = CFrame.new(0, 1.6, -0.35)
	ball(model, "Head", Vector3.new(1.4, 1.3, 1.3), russet, headCF)
	addEyes(model, headCF, 0.65, 1.1)
	ball(model, "Nose", Vector3.new(0.18, 0.14, 0.14), Color3.fromRGB(60, 40, 35), headCF * CFrame.new(0, -0.16, -0.64))
	for _, side in { -1, 1 } do
		ball(model, "Ear", Vector3.new(0.3, 0.5, 0.2), russet, headCF * CFrame.new(side * 0.4, 0.68, 0.05))
	end
	-- Signature: a huge S-curved fluffy tail, stacked from three blobs
	ball(model, "TailBase", Vector3.new(0.8, 1, 0.8), russet, CFrame.new(0, 0.9, 1.1) * CFrame.Angles(math.rad(30), 0, 0))
	ball(model, "TailMid", Vector3.new(0.95, 1.1, 0.95), russet, CFrame.new(0, 1.7, 1.35))
	ball(model, "TailTip", Vector3.new(0.7, 0.85, 0.7), cream, CFrame.new(0, 2.45, 1.1) * CFrame.Angles(math.rad(-25), 0, 0))
end

builders["Raccoon"] = function(model)
	local grey = Color3.fromRGB(140, 140, 150)
	local darkGrey = Color3.fromRGB(60, 60, 70)
	local cream = Color3.fromRGB(230, 225, 215)
	local body = ball(model, "Body", Vector3.new(1.9, 1.6, 2.2), grey, CFrame.new(0, 0.85, 0.3))
	model.PrimaryPart = body
	local headCF = CFrame.new(0, 1.95, -0.5)
	ball(model, "Head", Vector3.new(1.7, 1.5, 1.6), grey, headCF)
	-- Signature: the bandit mask — a dark band behind big eyes
	ball(model, "Mask", Vector3.new(1.5, 0.55, 0.6), darkGrey, headCF * CFrame.new(0, 0.12, -0.55))
	addEyes(model, headCF, 0.8)
	ball(model, "Snout", Vector3.new(0.55, 0.4, 0.5), cream, headCF * CFrame.new(0, -0.32, -0.7))
	ball(model, "Nose", Vector3.new(0.2, 0.17, 0.17), Color3.fromRGB(35, 30, 30), headCF * CFrame.new(0, -0.25, -0.94))
	for _, side in { -1, 1 } do
		ball(model, "Ear", Vector3.new(0.45, 0.5, 0.25), darkGrey, headCF * CFrame.new(side * 0.55, 0.75, 0.05))
	end
	-- Ringed tail: alternating grey / dark segments
	for i = 0, 3 do
		local segColor = (i % 2 == 0) and grey or darkGrey
		ball(model, "TailRing", Vector3.new(0.65 - i * 0.08, 0.55, 0.65 - i * 0.08), segColor,
			CFrame.new(0, 1 + i * 0.38, 1.5 + i * 0.28) * CFrame.Angles(math.rad(40), 0, 0))
	end
end

builders["Boar"] = function(model)
	local brown = Color3.fromRGB(115, 80, 60)
	local darkBrown = Color3.fromRGB(75, 50, 40)
	local body = ball(model, "Body", Vector3.new(2.3, 1.8, 2.7), brown, CFrame.new(0, 0.95, 0.2))
	model.PrimaryPart = body
	-- Bristle ridge along the spine
	for i = 0, 3 do
		ball(model, "Bristle", Vector3.new(0.5, 0.5, 0.6), darkBrown, CFrame.new(0, 1.85 - i * 0.06, -0.5 + i * 0.5))
	end
	local headCF = CFrame.new(0, 1.35, -1.35)
	ball(model, "Head", Vector3.new(1.6, 1.4, 1.4), brown, headCF)
	addEyes(model, headCF, 0.72, 0.9)
	-- Signature: flat snout disc + little white tusks
	ball(model, "Snout", Vector3.new(0.6, 0.5, 0.35), Color3.fromRGB(180, 130, 110), headCF * CFrame.new(0, -0.25, -0.72))
	for _, side in { -1, 1 } do
		ball(model, "Tusk", Vector3.new(0.16, 0.4, 0.16), Color3.fromRGB(245, 240, 225),
			headCF * CFrame.new(side * 0.4, -0.45, -0.55) * CFrame.Angles(0, 0, math.rad(side * -20)))
		ball(model, "Ear", Vector3.new(0.4, 0.5, 0.25), darkBrown, headCF * CFrame.new(side * 0.55, 0.62, 0.1))
	end
end

builders["Wolf"] = function(model)
	local grey = Color3.fromRGB(150, 155, 165)
	local darkGrey = Color3.fromRGB(95, 100, 110)
	local cream = Color3.fromRGB(235, 232, 225)
	local body = ball(model, "Body", Vector3.new(1.9, 1.7, 2.5), grey, CFrame.new(0, 0.95, 0.35))
	model.PrimaryPart = body
	ball(model, "BackFur", Vector3.new(1.6, 0.9, 2), darkGrey, CFrame.new(0, 1.5, 0.35))
	local headCF = CFrame.new(0, 2.15, -0.65)
	ball(model, "Head", Vector3.new(1.7, 1.6, 1.7), grey, headCF)
	addEyes(model, headCF, 0.82)
	ball(model, "Snout", Vector3.new(0.65, 0.5, 0.7), cream, headCF * CFrame.new(0, -0.35, -0.75))
	ball(model, "Nose", Vector3.new(0.22, 0.18, 0.18), Color3.fromRGB(35, 32, 32), headCF * CFrame.new(0, -0.28, -1.05))
	-- Signature: tall alert ears + a thick straight tail
	for _, side in { -1, 1 } do
		ball(model, "Ear", Vector3.new(0.5, 0.95, 0.3), darkGrey,
			headCF * CFrame.new(side * 0.5, 0.9, 0.08) * CFrame.Angles(0, 0, math.rad(side * 10)))
	end
	ball(model, "Tail", Vector3.new(0.7, 1.5, 0.7), darkGrey, CFrame.new(0, 1.15, 1.75) * CFrame.Angles(math.rad(50), 0, 0))
end

builders["Bear"] = function(model)
	local brown = Color3.fromRGB(130, 90, 60)
	local tan = Color3.fromRGB(200, 165, 125)
	local body = ball(model, "Body", Vector3.new(2.6, 2.4, 2.6), brown, CFrame.new(0, 1.3, 0.1))
	model.PrimaryPart = body
	ball(model, "Belly", Vector3.new(1.7, 1.6, 1), tan, CFrame.new(0, 1.15, -0.85))
	local headCF = CFrame.new(0, 2.9, -0.4)
	ball(model, "Head", Vector3.new(1.9, 1.7, 1.8), brown, headCF)
	addEyes(model, headCF, 0.88)
	ball(model, "Snout", Vector3.new(0.75, 0.55, 0.65), tan, headCF * CFrame.new(0, -0.35, -0.78))
	ball(model, "Nose", Vector3.new(0.26, 0.2, 0.2), Color3.fromRGB(40, 32, 30), headCF * CFrame.new(0, -0.26, -1.08))
	-- Signature: perfectly round teddy ears + chunky paws
	for _, side in { -1, 1 } do
		ball(model, "Ear", Vector3.new(0.6, 0.6, 0.35), brown, headCF * CFrame.new(side * 0.72, 0.72, 0.1))
		ball(model, "Paw", Vector3.new(0.8, 0.55, 0.8), brown, CFrame.new(side * 0.85, 0.3, -0.8))
	end
end

builders["Spirit Lynx"] = function(model)
	local spirit = Color3.fromRGB(170, 230, 235)
	local glow = Color3.fromRGB(120, 255, 250)
	local body = ball(model, "Body", Vector3.new(1.8, 1.6, 2.4), spirit, CFrame.new(0, 1.35, 0.3))
	model.PrimaryPart = body
	for _, dx in { -0.55, 0.55 } do
		for _, dz in { -0.5, 1 } do
			cylinder(model, "Leg", Vector3.new(1.4, 0.35, 0.35), spirit,
				CFrame.new(dx, 0.7, dz + 0.3) * CFrame.Angles(0, 0, math.rad(90)))
		end
	end
	local headCF = CFrame.new(0, 2.6, -0.6)
	ball(model, "Head", Vector3.new(1.5, 1.4, 1.4), spirit, headCF)
	addEyes(model, headCF, 0.72, 1.1)
	ball(model, "Nose", Vector3.new(0.18, 0.14, 0.14), Color3.fromRGB(70, 120, 125), headCF * CFrame.new(0, -0.2, -0.66))
	-- Signature: tufted ears + glowing neon markings — a ghost of the forest
	for _, side in { -1, 1 } do
		ball(model, "Ear", Vector3.new(0.4, 0.6, 0.25), spirit,
			headCF * CFrame.new(side * 0.5, 0.62, 0.05) * CFrame.Angles(0, 0, math.rad(side * 12)))
		local tuft = ball(model, "Tuft", Vector3.new(0.14, 0.4, 0.12), glow,
			headCF * CFrame.new(side * 0.58, 1.02, 0.05) * CFrame.Angles(0, 0, math.rad(side * 18)))
		tuft.Material = Enum.Material.Neon
	end
	for i = 1, 4 do -- glowing spirit stripes along the flank
		local stripe = ball(model, "SpiritMark", Vector3.new(0.1, 0.35, 0.5), glow,
			CFrame.new((i % 2 == 0) and 0.85 or -0.85, 1.45, -0.5 + i * 0.4) * CFrame.Angles(math.rad(20), 0, 0))
		stripe.Material = Enum.Material.Neon
	end
	local tail = ball(model, "Tail", Vector3.new(0.35, 0.8, 0.35), glow, CFrame.new(0, 1.7, 1.6) * CFrame.Angles(math.rad(35), 0, 0))
	tail.Material = Enum.Material.Neon
end

-- ------------------------------------------------------------
-- Mutation styling
-- ------------------------------------------------------------

-- Parts we never recolor, so faces stay readable on any mutation.
local FACE_PARTS = { Eye = true, Pupil = true, Nose = true, Beak = true, Snout = true }

local function addSparkles(parent: BasePart, color: Color3, rate: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "MutationSparkle"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 1
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Lifetime = NumberRange.new(0.6, 1.2)
	emitter.Rate = rate
	emitter.Speed = NumberRange.new(0.5, 1.5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Transparency = NumberSequence.new(0.2)
	emitter.Parent = parent
end

local function applyMutation(model: Model, mutation: string)
	if mutation == "None" or mutation == nil then
		return
	end
	local body = model.PrimaryPart
	for _, part in model:GetDescendants() do
		if not part:IsA("BasePart") or FACE_PARTS[part.Name] then
			continue
		end
		if mutation == "Shiny" then
			part.Reflectance = 0.28 -- glossy sheen, keeps species colors
		elseif mutation == "Golden" then
			part.Color = GOLD
			part.Material = Enum.Material.Metal
			part.Reflectance = 0.35
		elseif mutation == "Rainbow" then
			-- Tag it; AnimalModels.startRainbowCycler() (client) cycles the hue.
			CollectionService:AddTag(part, RAINBOW_TAG)
		end
	end
	if body then
		if mutation == "Shiny" then
			addSparkles(body, Color3.new(1, 1, 1), 6)
		elseif mutation == "Golden" then
			addSparkles(body, GOLD, 10)
		elseif mutation == "Rainbow" then
			addSparkles(body, Color3.fromRGB(255, 150, 255), 18)
		end
	end
end

-- ------------------------------------------------------------
-- Public API
-- ------------------------------------------------------------

-- Build a display model for a species (+ optional mutation).
-- Stands on y = 0 facing -Z; position it with model:PivotTo(cframe).
function AnimalModels.create(species: string, mutation: string?): Model
	local model = Instance.new("Model")
	model.Name = species

	local builder = builders[species]
	if builder then
		builder(model)
	else
		-- Unknown species (future content?): friendly fallback blob.
		local body = ball(model, "Body", Vector3.new(2, 2, 2), Color3.fromRGB(200, 200, 210), CFrame.new(0, 1, 0))
		model.PrimaryPart = body
		addEyes(model, CFrame.new(0, 1.3, 0), 1)
	end

	applyMutation(model, mutation or "None")
	return model
end

-- CLIENT ONLY: one global loop that cycles the hue of every RainbowPart
-- (reveal models, collection viewport models — anything tagged).
-- Call once at client startup. Returns the connection in case you want to stop it.
function AnimalModels.startRainbowCycler(): RBXScriptConnection
	assert(not RunService:IsServer(), "Rainbow cycler is client-side only")
	local elapsed = 0
	return RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		for _, part in CollectionService:GetTagged(RAINBOW_TAG) do
			if part:IsA("BasePart") then
				-- Offset by height so the rainbow flows across the body
				local hue = (elapsed * 0.45 + part.Position.Y * 0.06) % 1
				part.Color = Color3.fromHSV(hue, 0.7, 1)
			end
		end
	end)
end

-- Rarity color helper used by UI + reveal (kept here so everything that
-- draws an animal gets colors from one place).
function AnimalModels.rarityColor(species: string): Color3
	local animal = GameConfig.AnimalByName[species]
	if animal then
		return GameConfig.RarityByName[animal.Rarity].Color
	end
	return Color3.new(1, 1, 1)
end

return AnimalModels
