--[[
	WheelUI — the Lucky Block prize carousel (patch 6).

	The SERVER already rolled the prize; this just performs the theater: a
	case-opening-style strip of prize cards scrolls past a center pointer,
	decelerating until the predetermined card lands under it. Ticks as
	cards pass, a heartbeat of suspense at the end, and a big celebration
	if the slot is one of the rare ones.

	Nothing here affects the outcome — close the game mid-spin and the
	server still grants the same prize.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Sounds = require(script.Parent.Sounds)
local Remotes = require(ReplicatedStorage.Remotes)

local FONT = Enum.Font.FredokaOne
local CARD_WIDTH = 110
local WHEEL = GameConfig.LuckyWheel

local WheelUI = {}

local gui: ScreenGui
local backdrop: Frame
local windowFrame: Frame
local strip: Frame
local titleLabel: TextLabel
local flashFrame: Frame

local spinning = false

local function makeCard(entry, order: number, golden: boolean)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(0, CARD_WIDTH - 8, 1, -16)
	card.Position = UDim2.new(0, (order - 1) * CARD_WIDTH + 4, 0, 8)
	card.BackgroundColor3 = entry.Big
		and (golden and Color3.fromRGB(120, 90, 40) or Color3.fromRGB(105, 70, 90))
		or Color3.fromRGB(55, 62, 75)
	card.Parent = strip
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = card
	local strokeInstance = Instance.new("UIStroke")
	strokeInstance.Color = entry.Big and Color3.fromRGB(255, 210, 100) or Color3.fromRGB(30, 33, 40)
	strokeInstance.Thickness = 2
	strokeInstance.Parent = card

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -10, 1, -10)
	label.Position = UDim2.new(0, 5, 0, 5)
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextScaled = true
	label.TextWrapped = true
	label.Text = entry.Label
	label.TextColor3 = entry.Big and Color3.fromRGB(255, 225, 140) or Color3.new(1, 1, 1)
	label.Parent = card
	return card
end

function WheelUI.spin(payload)
	if spinning then
		return
	end
	spinning = true

	titleLabel.Text = payload.Golden and "🌟 GOLDEN LUCKY BLOCK" or "🧧 LUCKY BLOCK"
	titleLabel.TextColor3 = payload.Golden and Color3.fromRGB(255, 215, 100) or Color3.fromRGB(255, 150, 170)
	for _, child in strip:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	-- Build the card run: random filler from the pool, with the REAL prize
	-- sitting at TargetCard (and a juicy Big card right before it for the
	-- near-miss tease when the real prize is a common one)
	local cardRng = Random.new()
	local cards = {}
	for i = 1, WHEEL.Cards do
		cards[i] = payload.Entries[cardRng:NextInteger(1, #payload.Entries)]
	end
	local prize = payload.Entries[payload.PrizeIndex]
	cards[WHEEL.TargetCard] = prize
	if not prize.Big then
		for _, entry in payload.Entries do
			if entry.Big then
				cards[WHEEL.TargetCard - 1] = entry -- soooo close...
				break
			end
		end
	end
	local targetCard
	for order, entry in cards do
		local card = makeCard(entry, order, payload.Golden)
		if order == WHEEL.TargetCard then
			targetCard = card
		end
	end
	strip.Size = UDim2.new(0, WHEEL.Cards * CARD_WIDTH, 1, 0)

	backdrop.Visible = true

	-- Land the target card dead-center under the pointer (tiny random
	-- offset inside the card so it doesn't look robotic)
	local windowWidth = windowFrame.AbsoluteSize.X
	local jitter = cardRng:NextNumber(-CARD_WIDTH * 0.25, CARD_WIDTH * 0.25)
	local finalX = -((WHEEL.TargetCard - 0.5) * CARD_WIDTH) + windowWidth / 2 + jitter
	strip.Position = UDim2.new(0, 0, 0, 0)
	local tween = TweenService:Create(strip, TweenInfo.new(WHEEL.SpinSeconds, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, finalX, 0, 0),
	})

	-- Tick as each card passes the pointer
	local lastIndex = 0
	local tickConnection = RunService.RenderStepped:Connect(function()
		local passed = math.floor((windowWidth / 2 - strip.Position.X.Offset) / CARD_WIDTH)
		if passed ~= lastIndex then
			lastIndex = passed
			Sounds.buttonPress()
		end
	end)

	tween:Play()
	tween.Completed:Wait()
	tickConnection:Disconnect()

	-- The landing
	local isBig = prize.Big
	if targetCard then
		local pop = Instance.new("UIScale")
		pop.Scale = 1
		pop.Parent = targetCard
		TweenService:Create(pop, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.18 }):Play()
	end
	if isBig then
		flashFrame.BackgroundTransparency = 0.2
		TweenService:Create(flashFrame, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
		Sounds.mythicAnnounce()
		Sounds.raritySting(6)
	else
		Sounds.raritySting(3)
	end

	task.wait(isBig and 2.4 or 1.6)
	backdrop.Visible = false
	spinning = false
end

function WheelUI.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "WildhavenWheel"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 10
	gui.IgnoreGuiInset = true

	backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.fromRGB(10, 12, 16)
	backdrop.BackgroundTransparency = 0.35
	backdrop.Visible = false
	backdrop.Parent = gui

	titleLabel = Instance.new("TextLabel")
	titleLabel.AnchorPoint = Vector2.new(0.5, 1)
	titleLabel.Position = UDim2.new(0.5, 0, 0.34, 0)
	titleLabel.Size = UDim2.new(0, 420, 0, 42)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = FONT
	titleLabel.TextScaled = true
	titleLabel.Text = ""
	titleLabel.Parent = backdrop
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Color = Color3.fromRGB(20, 20, 25)
	titleStroke.Thickness = 2.5
	titleStroke.Parent = titleLabel

	-- The viewing window the strip scrolls behind
	windowFrame = Instance.new("Frame")
	windowFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	windowFrame.Position = UDim2.new(0.5, 0, 0.45, 0)
	windowFrame.Size = UDim2.new(0, 460, 0, 120)
	windowFrame.BackgroundColor3 = Color3.fromRGB(30, 34, 42)
	windowFrame.ClipsDescendants = true
	windowFrame.Parent = backdrop
	local windowCorner = Instance.new("UICorner")
	windowCorner.CornerRadius = UDim.new(0, 14)
	windowCorner.Parent = windowFrame

	strip = Instance.new("Frame")
	strip.BackgroundTransparency = 1
	strip.Size = UDim2.new(0, 1000, 1, 0)
	strip.Parent = windowFrame

	-- Center pointer (a neon needle over the window)
	local pointer = Instance.new("Frame")
	pointer.AnchorPoint = Vector2.new(0.5, 0.5)
	pointer.Position = UDim2.new(0.5, 0, 0.45, 0)
	pointer.Size = UDim2.new(0, 4, 0, 136)
	pointer.BackgroundColor3 = Color3.fromRGB(255, 230, 130)
	pointer.BorderSizePixel = 0
	pointer.ZIndex = 5
	pointer.Parent = backdrop

	flashFrame = Instance.new("Frame")
	flashFrame.Size = UDim2.new(1, 0, 1, 0)
	flashFrame.BackgroundColor3 = Color3.new(1, 1, 1)
	flashFrame.BackgroundTransparency = 1
	flashFrame.BorderSizePixel = 0
	flashFrame.ZIndex = 8
	flashFrame.Parent = gui

	Remotes.LuckyWheel.OnClientEvent:Connect(function(payload)
		task.spawn(WheelUI.spin, payload)
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return WheelUI
