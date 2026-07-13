--[[
	HatchRevealController — the star of the show. Plays the hatch spectacle
	CLIENT-SIDE at your base's hatch pad, using the result the server rolled:

	  1. A local copy of the egg appears on the pad: three anticipation
	     wobbles that build, then a beat of stillness
	  2. Crack + scale-punch + rarity-colored particle burst
	  3. The pet springs out with squash-and-stretch — scaled up if it's
	     BIG or GIANT — and settles into a gentle idle bob with a name label
	  4. Escalation: Rare+ adds a light beam and rising sting; Legendary/
	     Mythic, Rainbow, or GIANT adds screen flash, camera shake, confetti,
	     a banner, and a slow-mo beat

	Reveals QUEUE: if three slots finish at once you get three full shows
	back to back, not a pile-up. Everything is visual-only — the pet is
	already in your collection before the first wobble.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local AnimalModels = require(ReplicatedStorage.AnimalModels)
local EggModels = require(ReplicatedStorage.EggModels)
local GameConfig = require(ReplicatedStorage.GameConfig)
local Sounds = require(script.Parent.Sounds)

local REVEAL = GameConfig.Reveal

local HatchRevealController = {}

local overlayGui: ScreenGui
local flashFrame: Frame
local bannerLabel: TextLabel
local bannerScale: UIScale

local queue = {} -- pending reveal results
local playing = false

-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------

local function tween(instance: Instance, info: TweenInfo, props: { [string]: any }): Tween
	local t = TweenService:Create(instance, info, props)
	t:Play()
	return t
end

local function waitTween(instance: Instance, info: TweenInfo, props: { [string]: any })
	tween(instance, info, props).Completed:Wait()
end

-- How big should the celebration be? The MAX of rarity, mutation flair,
-- and size flair — a Giant Rainbow Squirrel parties like a Mythic.
local function spectacleOrderFor(result): number
	local order = GameConfig.RarityByName[result.Rarity].Order
	local mutation = GameConfig.MutationByName[result.Mutation]
	if mutation then
		order = math.max(order, mutation.SpectacleOrder)
	end
	local size = GameConfig.SizeByName[result.Size or "Normal"]
	if size then
		order = math.max(order, size.SpectacleOrder)
	end
	return order
end

-- ------------------------------------------------------------
-- Effect pieces
-- ------------------------------------------------------------

local function burstParticles(part: BasePart, color: Color3, count: number)
	local emitter = Instance.new("ParticleEmitter")
	emitter.Color = ColorSequence.new(color, Color3.new(1, 1, 1))
	emitter.LightEmission = 1
	emitter.Lifetime = NumberRange.new(0.5, 1.1)
	emitter.Speed = NumberRange.new(6, 14)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Rate = 0
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Parent = part
	emitter:Emit(count)
	task.delay(2, function()
		emitter:Destroy()
	end)
end

local function lightBeam(position: Vector3, color: Color3)
	local beam = Instance.new("Part")
	beam.Shape = Enum.PartType.Cylinder
	beam.Size = Vector3.new(50, 3.5, 3.5)
	beam.CFrame = CFrame.new(position + Vector3.new(0, 25, 0)) * CFrame.Angles(0, 0, math.rad(90))
	beam.Color = color
	beam.Material = Enum.Material.Neon
	beam.Transparency = 0.35
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.Parent = workspace
	tween(beam, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }).Completed:Once(function()
		beam:Destroy()
	end)
end

local function screenFlash()
	flashFrame.BackgroundTransparency = 0.15
	tween(flashFrame, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 })
end

local function cameraShake()
	local camera = workspace.CurrentCamera
	local duration = REVEAL.CameraShakeSeconds
	local intensity = REVEAL.CameraShakeIntensity
	local elapsed = 0
	local rng = Random.new()
	RunService:BindToRenderStep("WildhavenCameraShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
		elapsed += dt
		if elapsed >= duration then
			RunService:UnbindFromRenderStep("WildhavenCameraShake")
			return
		end
		local falloff = 1 - elapsed / duration
		local amount = math.rad(intensity) * falloff
		camera.CFrame = camera.CFrame * CFrame.Angles(
			rng:NextNumber(-amount, amount),
			rng:NextNumber(-amount, amount),
			rng:NextNumber(-amount, amount)
		)
	end)
end

local function confetti(position: Vector3, color: Color3)
	local source = Instance.new("Part")
	source.Size = Vector3.new(1, 1, 1)
	source.Transparency = 1
	source.Anchored = true
	source.CanCollide = false
	source.CanQuery = false
	source.CFrame = CFrame.new(position + Vector3.new(0, 8, 0))
	source.Parent = workspace

	for _, confettiColor in { color, Color3.fromRGB(255, 215, 100), Color3.fromRGB(255, 255, 255) } do
		local emitter = Instance.new("ParticleEmitter")
		emitter.Color = ColorSequence.new(confettiColor)
		emitter.LightEmission = 0.6
		emitter.Lifetime = NumberRange.new(1.2, 2.2)
		emitter.Speed = NumberRange.new(12, 22)
		emitter.SpreadAngle = Vector2.new(65, 65)
		emitter.Acceleration = Vector3.new(0, -30, 0)
		emitter.Rotation = NumberRange.new(0, 360)
		emitter.RotSpeed = NumberRange.new(-200, 200)
		emitter.Rate = 0
		emitter.Size = NumberSequence.new(0.35)
		emitter.Parent = source
		emitter:Emit(60)
	end
	task.delay(3, function()
		source:Destroy()
	end)
end

local function showBanner(text: string, color: Color3)
	bannerLabel.Text = text
	bannerLabel.TextColor3 = color
	bannerLabel.Visible = true
	bannerScale.Scale = 0.05
	tween(bannerScale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
	task.delay(2, function()
		waitTween(bannerScale, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.05 })
		bannerLabel.Visible = false
	end)
end

local MUTATION_COLORS = {
	Shiny = Color3.fromRGB(235, 245, 255),
	Golden = Color3.fromRGB(255, 210, 80),
	Rainbow = Color3.fromRGB(255, 110, 220),
}

local function nameBillboard(model: Model, result)
	local rarity = GameConfig.RarityByName[result.Rarity]
	local _, boxSize = model:GetBoundingBox()

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 260, 0, 110)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, boxSize.Y + 1.6, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = model.PrimaryPart
	billboard.Parent = model

	local function line(text: string, color: Color3, y: number, height: number)
		local label = Instance.new("TextLabel")
		label.Position = UDim2.new(0, 0, 0, y)
		label.Size = UDim2.new(1, 0, 0, height)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.FredokaOne
		label.TextScaled = true
		label.Text = text
		label.TextColor3 = color
		label.Parent = billboard
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(20, 20, 25)
		stroke.Thickness = 2.5
		stroke.Parent = label
	end

	line(("%s — %s"):format(result.Species, result.Rarity), rarity.Color, 0, 46)
	local y = 46
	if result.Size and result.Size ~= "Normal" then
		line("⬆ " .. result.Size:upper() .. " ⬆", Color3.fromRGB(150, 255, 160), y, 30)
		y += 30
	end
	if result.Mutation ~= "None" then
		line("✨ " .. result.Mutation:upper() .. " ✨", MUTATION_COLORS[result.Mutation] or Color3.new(1, 1, 1), y, 30)
	end
end

-- ------------------------------------------------------------
-- The main sequence (one queued reveal)
-- ------------------------------------------------------------

local function playOne(result)
	local rarity = GameConfig.RarityByName[result.Rarity]
	local spectacle = spectacleOrderFor(result)
	local isRainbow = result.Mutation == "Rainbow"
	local celebrationColor = isRainbow and Color3.fromRGB(255, 110, 220) or rarity.Color
	local basePosition: Vector3 = result.Position

	-- A LOCAL egg appears on the pad (the server already removed the real one)
	local egg = EggModels.create(result.EggType or "Forest Egg")
	local eggHome = CFrame.new(basePosition)
	egg:PivotTo(eggHome)
	egg.Parent = workspace
	local shell = egg.PrimaryPart :: Part

	Sounds.hatchReady()

	-- 1) ANTICIPATION: three wobbles, each harder and faster, then stillness
	for i = 1, #REVEAL.WobbleAngles do
		local angle = math.rad(REVEAL.WobbleAngles[i])
		local third = REVEAL.WobbleTimes[i] / 3
		Sounds.eggWobble(i)
		local info = TweenInfo.new(third, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		waitTween(shell, info, { CFrame = shell.CFrame * CFrame.Angles(0, 0, angle) })
		waitTween(shell, info, { CFrame = shell.CFrame * CFrame.Angles(0, 0, -2 * angle) })
		waitTween(shell, info, { CFrame = shell.CFrame * CFrame.Angles(0, 0, angle) })
	end
	task.wait(REVEAL.SuspensePause)

	-- 2) POP: scale-punch, crack, rarity-tinted burst, egg gone
	Sounds.eggCrack()
	local originalSize = shell.Size
	waitTween(shell, TweenInfo.new(REVEAL.PopTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = originalSize * 1.22,
	})
	burstParticles(shell, celebrationColor, 20 + spectacle * 8)
	Sounds.hatchPop()
	egg:Destroy()

	if spectacle >= REVEAL.BeamMinOrder then
		lightBeam(basePosition, celebrationColor)
	end

	-- 3) THE PET springs out, scaled by its SIZE modifier
	local sizeDef = GameConfig.SizeByName[result.Size or "Normal"]
	local finalScale = sizeDef and sizeDef.Scale or 1

	local model = AnimalModels.create(result.Species, result.Mutation)
	local buildPivot = model:GetPivot()
	local camera = workspace.CurrentCamera
	-- Face the camera-side so the player sees the face, not the tail
	local toCamera = camera.CFrame.Position - basePosition
	local yaw = math.atan2(-toCamera.X, -toCamera.Z) + math.pi
	local standCFrame = CFrame.new(basePosition) * CFrame.Angles(0, yaw, 0)
	model:PivotTo(standCFrame * buildPivot)
	model:ScaleTo(0.05)
	model.Parent = workspace

	local scaleValue = Instance.new("NumberValue")
	scaleValue.Value = 0.05
	scaleValue.Changed:Connect(function(value)
		model:ScaleTo(math.max(value, 0.02))
	end)
	waitTween(scaleValue, TweenInfo.new(REVEAL.SpringInTime + REVEAL.SettleTime, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Value = finalScale,
	})

	Sounds.raritySting(spectacle)
	nameBillboard(model, result)

	-- 4) ESCALATION: Legendary/Mythic, Rainbow, or GIANT = full fireworks
	if spectacle >= REVEAL.BigEventMinOrder then
		screenFlash()
		cameraShake()
		confetti(basePosition, celebrationColor)

		local bannerWords = {}
		if result.Size == "Giant" then
			table.insert(bannerWords, "GIANT")
		end
		if rarity.Order >= REVEAL.BigEventMinOrder then
			table.insert(bannerWords, result.Rarity:upper())
		end
		if isRainbow then
			table.insert(bannerWords, "RAINBOW")
		end
		showBanner("✨ " .. table.concat(bannerWords, " ") .. "! ✨", celebrationColor)

		task.wait(REVEAL.SlowMoBeatSeconds)
	end

	-- Idle bob while the name lingers, then wave goodbye
	local bobBase = model:GetPivot()
	local elapsed = 0
	local bobConnection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		model:PivotTo(bobBase * CFrame.new(0, math.sin(elapsed * 4) * 0.12, 0) * CFrame.Angles(0, math.sin(elapsed * 2) * 0.04, 0))
	end)

	task.wait(REVEAL.NameShowSeconds)

	bobConnection:Disconnect()
	waitTween(scaleValue, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Value = 0.02 })
	model:Destroy()
	scaleValue:Destroy()
end

-- ------------------------------------------------------------
-- Public API
-- ------------------------------------------------------------

-- Queue a reveal (called for each HatchComplete event). Returns immediately;
-- reveals play one after another so simultaneous hatches don't overlap.
function HatchRevealController.play(result)
	table.insert(queue, result)
	if playing then
		return
	end
	playing = true
	task.spawn(function()
		while #queue > 0 do
			local nextResult = table.remove(queue, 1)
			local ok, err = pcall(playOne, nextResult)
			if not ok then
				warn("[HatchReveal] " .. tostring(err))
			end
		end
		playing = false
	end)
end

function HatchRevealController.init()
	overlayGui = Instance.new("ScreenGui")
	overlayGui.Name = "WildhavenReveal"
	overlayGui.ResetOnSpawn = false
	overlayGui.IgnoreGuiInset = true
	overlayGui.DisplayOrder = 10

	flashFrame = Instance.new("Frame")
	flashFrame.Size = UDim2.new(1, 0, 1, 0)
	flashFrame.BackgroundColor3 = Color3.new(1, 1, 1)
	flashFrame.BackgroundTransparency = 1
	flashFrame.BorderSizePixel = 0
	flashFrame.Parent = overlayGui

	bannerLabel = Instance.new("TextLabel")
	bannerLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	bannerLabel.Position = UDim2.new(0.5, 0, 0.3, 0)
	bannerLabel.Size = UDim2.new(0.9, 0, 0, 90)
	bannerLabel.BackgroundTransparency = 1
	bannerLabel.Font = Enum.Font.FredokaOne
	bannerLabel.TextScaled = true
	bannerLabel.Visible = false
	bannerLabel.Parent = overlayGui
	local bannerStroke = Instance.new("UIStroke")
	bannerStroke.Color = Color3.fromRGB(20, 20, 25)
	bannerStroke.Thickness = 4
	bannerStroke.Parent = bannerLabel
	bannerScale = Instance.new("UIScale")
	bannerScale.Parent = bannerLabel

	overlayGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return HatchRevealController
