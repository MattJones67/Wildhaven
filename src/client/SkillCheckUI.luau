--[[
	SkillCheckUI — the DBD-style egg collection minigame (patch 6).

	A marker sweeps across a bar; tap (anywhere / Space) when it's inside
	the green zone. Both this UI and the server compute the marker from the
	SAME shared clock and formula, so what you see is what the server
	judges — this file predicts hit/miss instantly for feel, then sends the
	tap time; the server's verdict (EggSkillResult) is the one that counts.

	Misses: camera shake + crack burst on the actual egg + red flash.
	Finish: "COLLECTED!" with quality stars — flawless gets a fanfare.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Remotes)
local Sounds = require(script.Parent.Sounds)

local FONT = Enum.Font.FredokaOne

local SkillCheckUI = {}

local gui: ScreenGui
local panel: Frame
local titleLabel: TextLabel
local bar: Frame
local zoneFrame: Frame
local marker: Frame
local pipsFrame: Frame
local cracksLabel: TextLabel
local flashFrame: Frame
local resultLabel: TextLabel
local tapCatcher: TextButton

-- Active session (client copy)
local active = nil -- {Egg, StartAt, Speed, ZoneSize, Zones, Required, MaxCracks, Taps, Hits, Cracks}
local renderConnection: RBXScriptConnection? = nil

-- ------------------------------------------------------------
-- Feedback pieces
-- ------------------------------------------------------------

local function shake(intensity: number)
	local camera = workspace.CurrentCamera
	local elapsed = 0
	local shakeRng = Random.new()
	RunService:BindToRenderStep("EggCrackShake", Enum.RenderPriority.Camera.Value + 1, function(dt)
		elapsed += dt
		if elapsed >= 0.25 then
			RunService:UnbindFromRenderStep("EggCrackShake")
			return
		end
		local amount = math.rad(intensity) * (1 - elapsed / 0.25)
		camera.CFrame = camera.CFrame * CFrame.Angles(
			shakeRng:NextNumber(-amount, amount),
			shakeRng:NextNumber(-amount, amount),
			0
		)
	end)
end

local function flash(color: Color3)
	flashFrame.BackgroundColor3 = color
	flashFrame.BackgroundTransparency = 0.72
	TweenService:Create(flashFrame, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
end

-- A visible crack on the real world egg: dark shard burst + brief darken
local function crackEgg()
	if not active or not active.Egg or active.Egg.Parent == nil then
		return
	end
	local base = active.Egg.PrimaryPart or active.Egg:FindFirstChildWhichIsA("BasePart")
	if not base then
		return
	end
	local shards = Instance.new("ParticleEmitter")
	shards.Color = ColorSequence.new(Color3.fromRGB(60, 55, 50))
	shards.Lifetime = NumberRange.new(0.3, 0.7)
	shards.Speed = NumberRange.new(4, 9)
	shards.SpreadAngle = Vector2.new(180, 180)
	shards.Rate = 0
	shards.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	shards.Parent = base
	shards:Emit(14)
	task.delay(1, function()
		shards:Destroy()
	end)
end

local function refreshPips()
	for _, child in pipsFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for i = 1, active.Required do
		local pip = Instance.new("Frame")
		pip.Size = UDim2.new(0, 18, 0, 18)
		pip.BackgroundColor3 = i <= active.Hits and Color3.fromRGB(110, 230, 120) or Color3.fromRGB(70, 76, 90)
		pip.LayoutOrder = i
		pip.Parent = pipsFrame
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = pip
	end
	cracksLabel.Text = active.Cracks > 0 and ("💔 " .. active.Cracks) or ""
end

local function currentZone(): number
	return active.Zones[math.min(active.Taps + 1, #active.Zones)]
end

local function renderZone()
	local zoneStart = currentZone()
	zoneFrame.Position = UDim2.new(zoneStart, 0, 0, 0)
	zoneFrame.Size = UDim2.new(math.min(active.ZoneSize, 1 - zoneStart + 0.001), 0, 1, 0)
	-- (zones are generated ≤0.95 so the wrap case stays rare and readable)
end

-- ------------------------------------------------------------
-- The session
-- ------------------------------------------------------------

local function close()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	active = nil
	panel.Visible = false
	tapCatcher.Visible = false
end

local function onTap()
	if not active then
		return
	end
	local tapTime = workspace:GetServerTimeNow()
	if tapTime < active.StartAt then
		return -- marker hasn't started; don't waste a tap
	end
	-- Predict locally with the SAME formula the server uses (instant feel)
	local position = ((tapTime - active.StartAt) * active.Speed) % 1
	local zoneStart = currentZone()
	local hit = ((position - zoneStart) % 1) <= active.ZoneSize + GameConfig.SkillCheck.ZoneTolerance

	active.Taps += 1
	if hit then
		active.Hits += 1
		flash(Color3.fromRGB(120, 255, 140))
		Sounds.buttonPress()
	else
		active.Cracks += 1
		flash(Color3.fromRGB(255, 80, 70))
		Sounds.eggCrack()
		shake(0.55)
		crackEgg()
	end
	refreshPips()
	renderZone()

	Remotes.EggSkillTap:FireServer(tapTime) -- the server re-judges this
end

local function open(payload)
	active = {
		Egg = payload.Egg,
		StartAt = payload.StartAt,
		Speed = payload.Speed,
		ZoneSize = payload.ZoneSize,
		Zones = payload.Zones,
		Required = payload.Required,
		MaxCracks = payload.MaxCracks,
		Taps = 0,
		Hits = 0,
		Cracks = 0,
	}
	titleLabel.Text = "🥚 " .. payload.EggType
	resultLabel.Visible = false
	panel.Visible = true
	tapCatcher.Visible = true
	refreshPips()
	renderZone()

	renderConnection = RunService.RenderStepped:Connect(function()
		if not active then
			return
		end
		local now = workspace:GetServerTimeNow()
		if now < active.StartAt then
			marker.Position = UDim2.new(0, 0, 0, -4)
			titleLabel.Text = "🥚 Ready..."
		else
			titleLabel.Text = "🥚 TAP in the green!"
			local position = ((now - active.StartAt) * active.Speed) % 1
			marker.Position = UDim2.new(position, -2, 0, -4)
		end
	end)
end

local function onResult(payload)
	if payload.Canceled then
		close()
		return
	end
	if not payload.Collected then
		return
	end
	-- Land the celebration BEFORE closing: quality stars, flawless fanfare
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
	tapCatcher.Visible = false
	local stars = payload.Quality >= 0.99 and "✨ FLAWLESS! ✨"
		or string.rep("⭐", math.max(1, math.ceil(payload.Quality * 3)))
	if payload.Quality <= 0 then
		stars = "…in one piece. Barely."
	end
	resultLabel.Text = "COLLECTED!  " .. stars
	resultLabel.TextColor3 = payload.Quality >= 0.99 and Color3.fromRGB(255, 230, 130) or Color3.fromRGB(150, 255, 170)
	resultLabel.Visible = true
	if payload.Quality >= 0.99 then
		flash(Color3.fromRGB(255, 230, 130))
		Sounds.raritySting(5)
	else
		Sounds.raritySting(2)
	end
	task.delay(1.2, close)
end

-- ------------------------------------------------------------
-- Boot
-- ------------------------------------------------------------

function SkillCheckUI.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "WildhavenSkillCheck"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 9
	gui.IgnoreGuiInset = true

	-- Full-screen red/green flash layer
	flashFrame = Instance.new("Frame")
	flashFrame.Size = UDim2.new(1, 0, 1, 0)
	flashFrame.BackgroundTransparency = 1
	flashFrame.BorderSizePixel = 0
	flashFrame.Parent = gui

	-- The tap catcher: any tap/click anywhere counts (mobile-first)
	tapCatcher = Instance.new("TextButton")
	tapCatcher.Size = UDim2.new(1, 0, 1, 0)
	tapCatcher.BackgroundTransparency = 1
	tapCatcher.Text = ""
	tapCatcher.Visible = false
	tapCatcher.Parent = gui
	tapCatcher.Activated:Connect(onTap)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Space and active then
			onTap()
		end
	end)

	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 0.82, 0)
	panel.Size = UDim2.new(0, 440, 0, 128)
	panel.BackgroundColor3 = Color3.fromRGB(30, 34, 42)
	panel.BackgroundTransparency = 0.15
	panel.Visible = false
	panel.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 14)
	corner.Parent = panel

	titleLabel = Instance.new("TextLabel")
	titleLabel.Position = UDim2.new(0, 14, 0, 8)
	titleLabel.Size = UDim2.new(1, -110, 0, 26)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = FONT
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Text = ""
	titleLabel.Parent = panel

	cracksLabel = Instance.new("TextLabel")
	cracksLabel.AnchorPoint = Vector2.new(1, 0)
	cracksLabel.Position = UDim2.new(1, -52, 0, 8)
	cracksLabel.Size = UDim2.new(0, 80, 0, 26)
	cracksLabel.BackgroundTransparency = 1
	cracksLabel.Font = FONT
	cracksLabel.TextScaled = true
	cracksLabel.TextColor3 = Color3.fromRGB(255, 120, 110)
	cracksLabel.TextXAlignment = Enum.TextXAlignment.Right
	cracksLabel.Text = ""
	cracksLabel.Parent = panel

	-- Give-up button
	local cancelButton = Instance.new("TextButton")
	cancelButton.AnchorPoint = Vector2.new(1, 0)
	cancelButton.Position = UDim2.new(1, -10, 0, 6)
	cancelButton.Size = UDim2.new(0, 34, 0, 30)
	cancelButton.BackgroundColor3 = Color3.fromRGB(200, 100, 90)
	cancelButton.Font = FONT
	cancelButton.TextScaled = true
	cancelButton.TextColor3 = Color3.new(1, 1, 1)
	cancelButton.AutoButtonColor = false
	cancelButton.Text = "✕"
	cancelButton.Parent = panel
	local cancelCorner = Instance.new("UICorner")
	cancelCorner.CornerRadius = UDim.new(0, 8)
	cancelCorner.Parent = cancelButton
	cancelButton.Activated:Connect(function()
		Remotes.EggSkillCancel:FireServer()
		close()
	end)

	-- The bar + zone + marker
	bar = Instance.new("Frame")
	bar.Position = UDim2.new(0, 14, 0, 44)
	bar.Size = UDim2.new(1, -28, 0, 34)
	bar.BackgroundColor3 = Color3.fromRGB(52, 58, 72)
	bar.Parent = panel
	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 8)
	barCorner.Parent = bar

	zoneFrame = Instance.new("Frame")
	zoneFrame.Size = UDim2.new(0.2, 0, 1, 0)
	zoneFrame.BackgroundColor3 = Color3.fromRGB(95, 220, 110)
	zoneFrame.BackgroundTransparency = 0.15
	zoneFrame.BorderSizePixel = 0
	zoneFrame.Parent = bar
	local zoneCorner = Instance.new("UICorner")
	zoneCorner.CornerRadius = UDim.new(0, 8)
	zoneCorner.Parent = zoneFrame

	marker = Instance.new("Frame")
	marker.Size = UDim2.new(0, 4, 1, 8)
	marker.Position = UDim2.new(0, 0, 0, -4)
	marker.BackgroundColor3 = Color3.new(1, 1, 1)
	marker.BorderSizePixel = 0
	marker.ZIndex = 3
	marker.Parent = bar

	-- Progress pips (required hits)
	pipsFrame = Instance.new("Frame")
	pipsFrame.Position = UDim2.new(0, 14, 0, 90)
	pipsFrame.Size = UDim2.new(1, -28, 0, 22)
	pipsFrame.BackgroundTransparency = 1
	pipsFrame.Parent = panel
	local pipsLayout = Instance.new("UIListLayout")
	pipsLayout.FillDirection = Enum.FillDirection.Horizontal
	pipsLayout.Padding = UDim.new(0, 8)
	pipsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	pipsLayout.Parent = pipsFrame

	resultLabel = Instance.new("TextLabel")
	resultLabel.AnchorPoint = Vector2.new(0.5, 1)
	resultLabel.Position = UDim2.new(0.5, 0, 0, -8)
	resultLabel.Size = UDim2.new(1, 0, 0, 40)
	resultLabel.BackgroundTransparency = 1
	resultLabel.Font = FONT
	resultLabel.TextScaled = true
	resultLabel.Visible = false
	resultLabel.Text = ""
	resultLabel.Parent = panel
	local resultStroke = Instance.new("UIStroke")
	resultStroke.Color = Color3.fromRGB(20, 20, 25)
	resultStroke.Thickness = 2.5
	resultStroke.Parent = resultLabel

	Remotes.EggSkillStart.OnClientEvent:Connect(open)
	Remotes.EggSkillResult.OnClientEvent:Connect(onResult)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return SkillCheckUI
