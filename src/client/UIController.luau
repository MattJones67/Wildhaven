--[[
	UIController — builds and runs the whole HUD in code (no Studio setup):

	  * Coin counter that ticks up smoothly and "pops" when it gains
	  * Always-visible income/sec readout
	  * 🥚 EGGS button (with carried/capacity count) -> egg inventory panel
	    where each carried egg type has its own HATCH button
	  * 🏠 BASE button -> upgrades panel (functional + aesthetic, live prices)
	  * 🍀 LUCK BOOST button that becomes a countdown while active
	  * 📦 Collection panel: 3D model cards with rarity borders, mutation
	    AND size tags, and counts
	  * Toast stack ("+1 Forest Egg", errors) and the Mythic Egg announcement

	This module only RENDERS state the server sends and forwards button
	presses to handlers wired up by init.client. It never decides outcomes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local AnimalModels = require(ReplicatedStorage.AnimalModels)
local GameConfig = require(ReplicatedStorage.GameConfig)
local Sounds = require(script.Parent.Sounds)

local FONT = Enum.Font.FredokaOne
local PANEL_COLOR = Color3.fromRGB(40, 45, 55)
local ROW_COLOR = Color3.fromRGB(55, 62, 75)
local GOLD = Color3.fromRGB(255, 205, 80)
local GREEN = Color3.fromRGB(95, 200, 90)

local MUTATION_LABELS = {
	Shiny = { Text = "✨ Shiny", Color = Color3.fromRGB(230, 240, 255) },
	Golden = { Text = "✨ Golden", Color = GOLD },
	Rainbow = { Text = "🌈 Rainbow", Color = Color3.fromRGB(255, 110, 220) },
}

local UIController = {}

-- Live UI state (server-pushed; the render loop eases toward it)
local displayedCoins = 0
local targetCoins = 0
local luckSecondsLeft = 0
local luckMultiplier = 1
local eggCounts: { [string]: number } = {}
local eggTotal = 0
local eggCapacity = 3
local upgradeLevels: { [string]: number } = {}

local handlersRef: { onStartHatch: (string) -> (), onBuyLuck: () -> (), onBuyUpgrade: (string) -> () }

-- Instances
local coinsLabel: TextLabel
local coinsScale: UIScale
local incomeLabel: TextLabel
local eggsButton: TextButton
local eggsCountLabel: TextLabel
local luckButton: TextButton
local luckTitleLabel: TextLabel
local luckSubLabel: TextLabel
local collectionGrid: ScrollingFrame
local eggPanelRows: Frame
local upgradeRows: ScrollingFrame
local toastColumn: Frame
local announceLabel: TextLabel
local panels: { Frame } = {}

-- ------------------------------------------------------------
-- Small helpers
-- ------------------------------------------------------------

local function comma(n: number): string
	local s = tostring(math.floor(n + 0.5))
	while true do
		local replaced
		s, replaced = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
		if replaced == 0 then
			break
		end
	end
	return s
end

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
end

local function stroke(parent: Instance, color: Color3, thickness: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Parent = parent
	return s
end

local function addPressFeedback(button: GuiButton)
	local scale = Instance.new("UIScale")
	scale.Parent = button
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.08), { Scale = 0.92 }):Play()
	end)
	local function release()
		TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	button.MouseButton1Up:Connect(release)
	button.MouseLeave:Connect(release)
	button.Activated:Connect(function()
		Sounds.buttonPress()
	end)
end

local function makeLabel(parent: Instance, props: { [string]: any }): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = FONT
	label.TextScaled = true
	for key, value in props do
		(label :: any)[key] = value
	end
	label.Parent = parent
	return label
end

local function makeButton(parent: Instance, props: { [string]: any }): TextButton
	local button = Instance.new("TextButton")
	button.Font = FONT
	button.TextScaled = true
	button.AutoButtonColor = false
	button.TextColor3 = Color3.new(1, 1, 1)
	for key, value in props do
		(button :: any)[key] = value
	end
	button.Parent = parent
	round(button, 12)
	addPressFeedback(button)
	return button
end

-- Only one big panel open at a time (mobile screens are small)
local function registerPanel(panel: Frame)
	table.insert(panels, panel)
end

local function togglePanel(panel: Frame)
	local show = not panel.Visible
	for _, other in panels do
		other.Visible = false
	end
	panel.Visible = show
end

local function makePanel(gui: ScreenGui, title: string): Frame
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.45, 0)
	panel.Size = UDim2.new(0.84, 0, 0.66, 0)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.BackgroundTransparency = 0.08
	panel.Visible = false
	panel.Parent = gui
	round(panel, 18)
	stroke(panel, Color3.fromRGB(20, 22, 28), 3)
	makeLabel(panel, {
		Position = UDim2.new(0, 16, 0, 8),
		Size = UDim2.new(1, -32, 0, 38),
		Text = title,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	registerPanel(panel)
	return panel
end

-- ------------------------------------------------------------
-- HUD corners: coins + income (top-left)
-- ------------------------------------------------------------

local function buildCoinsCorner(gui: ScreenGui)
	local frame = Instance.new("Frame")
	frame.Position = UDim2.new(0, 12, 0, 12)
	frame.Size = UDim2.new(0, 230, 0, 96)
	frame.BackgroundColor3 = PANEL_COLOR
	frame.BackgroundTransparency = 0.25
	frame.Parent = gui
	round(frame, 14)

	coinsLabel = makeLabel(frame, {
		Position = UDim2.new(0, 12, 0, 6),
		Size = UDim2.new(1, -24, 0, 44),
		Text = "🪙 0",
		TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	coinsScale = Instance.new("UIScale")
	coinsScale.Parent = coinsLabel

	incomeLabel = makeLabel(frame, {
		Position = UDim2.new(0, 12, 0, 54),
		Size = UDim2.new(1, -24, 0, 32),
		Text = "+0 🪙/s",
		TextColor3 = GREEN,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
end

-- ------------------------------------------------------------
-- Bottom action bar: EGGS (center), LUCK (right), BASE (left)
-- ------------------------------------------------------------

local function buildActionButtons(gui: ScreenGui, eggPanel: Frame, upgradePanel: Frame)
	eggsButton = makeButton(gui, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -20),
		Size = UDim2.new(0, 230, 0, 88),
		BackgroundColor3 = GREEN,
		Text = "",
	})
	stroke(eggsButton, Color3.fromRGB(50, 120, 50), 3)
	makeLabel(eggsButton, {
		Position = UDim2.new(0, 0, 0, 8),
		Size = UDim2.new(1, 0, 0, 44),
		Text = "🥚 EGGS",
		TextColor3 = Color3.new(1, 1, 1),
	})
	eggsCountLabel = makeLabel(eggsButton, {
		Position = UDim2.new(0, 0, 0, 52),
		Size = UDim2.new(1, 0, 0, 28),
		Text = "0 / 3",
		TextColor3 = Color3.fromRGB(235, 255, 235),
	})
	eggsButton.Activated:Connect(function()
		togglePanel(eggPanel)
	end)

	luckButton = makeButton(gui, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 205, 1, -20),
		Size = UDim2.new(0, 160, 0, 88),
		BackgroundColor3 = Color3.fromRGB(90, 170, 220),
		Text = "",
	})
	stroke(luckButton, Color3.fromRGB(45, 100, 140), 3)
	luckTitleLabel = makeLabel(luckButton, {
		Position = UDim2.new(0, 4, 0, 8),
		Size = UDim2.new(1, -8, 0, 42),
		Text = "🍀 LUCK x" .. GameConfig.LuckBoost.Multiplier,
		TextColor3 = Color3.new(1, 1, 1),
	})
	luckSubLabel = makeLabel(luckButton, {
		Position = UDim2.new(0, 4, 0, 54),
		Size = UDim2.new(1, -8, 0, 26),
		Text = comma(GameConfig.LuckBoost.Cost) .. " 🪙",
		TextColor3 = Color3.fromRGB(230, 245, 255),
	})
	luckButton.Activated:Connect(function()
		handlersRef.onBuyLuck()
	end)

	local baseButton = makeButton(gui, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, -205, 1, -20),
		Size = UDim2.new(0, 160, 0, 88),
		BackgroundColor3 = Color3.fromRGB(215, 140, 80),
		Text = "🏠 BASE",
	})
	stroke(baseButton, Color3.fromRGB(140, 85, 45), 3)
	baseButton.Activated:Connect(function()
		togglePanel(upgradePanel)
	end)
end

-- ------------------------------------------------------------
-- Egg inventory panel: one row per egg type with its own HATCH button
-- ------------------------------------------------------------

local eggRowRefs: { [string]: { Count: TextLabel, Button: TextButton } } = {}

local function buildEggPanel(gui: ScreenGui): Frame
	local panel = makePanel(gui, "🥚 My Eggs")

	eggPanelRows = Instance.new("Frame")
	eggPanelRows.Position = UDim2.new(0, 12, 0, 52)
	eggPanelRows.Size = UDim2.new(1, -24, 1, -64)
	eggPanelRows.BackgroundTransparency = 1
	eggPanelRows.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = eggPanelRows

	for order, egg in GameConfig.Eggs do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 62)
		row.BackgroundColor3 = ROW_COLOR
		row.LayoutOrder = order
		row.Parent = eggPanelRows
		round(row, 12)
		stroke(row, egg.Color, 2)

		-- Color dot = the egg's look
		local dot = Instance.new("Frame")
		dot.Position = UDim2.new(0, 12, 0.5, -14)
		dot.Size = UDim2.new(0, 28, 0, 28)
		dot.BackgroundColor3 = egg.Color
		dot.Parent = row
		round(dot, 14)

		makeLabel(row, {
			Position = UDim2.new(0, 52, 0, 6),
			Size = UDim2.new(0.45, 0, 0, 30),
			Text = egg.Name,
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		makeLabel(row, {
			Position = UDim2.new(0, 52, 0, 34),
			Size = UDim2.new(0.45, 0, 0, 22),
			Text = math.floor(egg.HatchSeconds) .. "s hatch",
			TextColor3 = Color3.fromRGB(180, 188, 200),
			TextXAlignment = Enum.TextXAlignment.Left,
		})

		local count = makeLabel(row, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -130, 0.5, 0),
			Size = UDim2.new(0, 60, 0, 34),
			Text = "x0",
			TextColor3 = Color3.new(1, 1, 1),
		})

		local hatchButton = makeButton(row, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.new(0, 110, 0, 46),
			BackgroundColor3 = GREEN,
			Text = "HATCH",
		})
		hatchButton.Activated:Connect(function()
			handlersRef.onStartHatch(egg.Name)
		end)

		eggRowRefs[egg.Name] = { Count = count, Button = hatchButton }
	end

	return panel
end

local function refreshEggRows()
	for eggName, refs in eggRowRefs do
		local count = eggCounts[eggName] or 0
		refs.Count.Text = "x" .. count
		refs.Button.BackgroundColor3 = count > 0 and GREEN or Color3.fromRGB(110, 120, 115)
	end
	eggsCountLabel.Text = eggTotal .. " / " .. eggCapacity
end

-- ------------------------------------------------------------
-- Base upgrades panel: data-driven from GameConfig.BaseUpgrades
-- ------------------------------------------------------------

local upgradeRowRefs: { [string]: { Level: TextLabel, Effect: TextLabel, Button: TextButton } } = {}

local function describeValue(upgrade, level: number): string
	local value = upgrade.Values[math.clamp(level, 1, #upgrade.Values)]
	if typeof(value) == "boolean" then
		return value and "Owned" or "Not owned"
	end
	return upgrade.Describe:format(tostring(value))
end

local function buildUpgradePanel(gui: ScreenGui): Frame
	local panel = makePanel(gui, "🏠 Base Upgrades")

	upgradeRows = Instance.new("ScrollingFrame")
	upgradeRows.Position = UDim2.new(0, 12, 0, 52)
	upgradeRows.Size = UDim2.new(1, -24, 1, -64)
	upgradeRows.BackgroundTransparency = 1
	upgradeRows.BorderSizePixel = 0
	upgradeRows.ScrollBarThickness = 6
	upgradeRows.AutomaticCanvasSize = Enum.AutomaticSize.Y
	upgradeRows.CanvasSize = UDim2.new(0, 0, 0, 0)
	upgradeRows.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = upgradeRows

	for order, upgrade in GameConfig.BaseUpgrades do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 66)
		row.BackgroundColor3 = ROW_COLOR
		row.LayoutOrder = order
		row.Parent = upgradeRows
		round(row, 12)
		local accent = upgrade.Kind == "Aesthetic" and Color3.fromRGB(215, 140, 200) or Color3.fromRGB(120, 170, 230)
		stroke(row, accent, 2)

		makeLabel(row, {
			Position = UDim2.new(0, 12, 0, 6),
			Size = UDim2.new(0.5, 0, 0, 28),
			Text = upgrade.Title,
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local level = makeLabel(row, {
			Position = UDim2.new(0, 12, 0, 36),
			Size = UDim2.new(0.25, 0, 0, 22),
			Text = "Lv 1",
			TextColor3 = Color3.fromRGB(180, 188, 200),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local effect = makeLabel(row, {
			Position = UDim2.new(0.28, 0, 0, 36),
			Size = UDim2.new(0.4, 0, 0, 22),
			Text = "",
			TextColor3 = Color3.fromRGB(180, 220, 190),
			TextXAlignment = Enum.TextXAlignment.Left,
		})

		local buyButton = makeButton(row, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.new(0, 130, 0, 48),
			BackgroundColor3 = GOLD,
			TextColor3 = Color3.fromRGB(60, 45, 10),
			Text = "…",
		})
		buyButton.Activated:Connect(function()
			handlersRef.onBuyUpgrade(upgrade.Key)
		end)

		upgradeRowRefs[upgrade.Key] = { Level = level, Effect = effect, Button = buyButton }
	end

	return panel
end

local function refreshUpgradeRows()
	for _, upgrade in GameConfig.BaseUpgrades do
		local refs = upgradeRowRefs[upgrade.Key]
		local level = upgradeLevels[upgrade.Key] or 1
		local maxLevel = #upgrade.Values
		refs.Level.Text = "Lv " .. level .. "/" .. maxLevel
		if level >= maxLevel then
			refs.Effect.Text = describeValue(upgrade, level)
			refs.Button.Text = "MAX"
			refs.Button.BackgroundColor3 = Color3.fromRGB(110, 120, 115)
		else
			refs.Effect.Text = describeValue(upgrade, level) .. " → " .. describeValue(upgrade, level + 1)
			refs.Button.Text = comma(upgrade.Prices[level + 1]) .. " 🪙"
			refs.Button.BackgroundColor3 = GOLD
		end
	end
end

-- ------------------------------------------------------------
-- Collection panel (3D cards with rarity + mutation + SIZE tags)
-- ------------------------------------------------------------

local function buildCollectionUI(gui: ScreenGui): Frame
	local toggle = makeButton(gui, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 12),
		Size = UDim2.new(0, 150, 0, 56),
		BackgroundColor3 = Color3.fromRGB(150, 120, 210),
		Text = "📦 Pets",
	})
	stroke(toggle, Color3.fromRGB(90, 70, 140), 3)

	local panel = makePanel(gui, "📦 My Pets")

	collectionGrid = Instance.new("ScrollingFrame")
	collectionGrid.Position = UDim2.new(0, 12, 0, 52)
	collectionGrid.Size = UDim2.new(1, -24, 1, -64)
	collectionGrid.BackgroundTransparency = 1
	collectionGrid.BorderSizePixel = 0
	collectionGrid.ScrollBarThickness = 6
	collectionGrid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	collectionGrid.CanvasSize = UDim2.new(0, 0, 0, 0)
	collectionGrid.Parent = panel

	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0, 116, 0, 158)
	layout.CellPadding = UDim2.new(0, 10, 0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = collectionGrid

	toggle.Activated:Connect(function()
		togglePanel(panel)
	end)
	return panel
end

local function makeCard(group, layoutOrder: number)
	local animal = GameConfig.AnimalByName[group.Species]
	local rarity = GameConfig.RarityByName[animal.Rarity]

	local card = Instance.new("Frame")
	card.BackgroundColor3 = ROW_COLOR
	card.LayoutOrder = layoutOrder
	round(card, 12)
	stroke(card, rarity.Color, 3)

	local viewport = Instance.new("ViewportFrame")
	viewport.Position = UDim2.new(0, 6, 0, 6)
	viewport.Size = UDim2.new(1, -12, 0, 78)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(190, 190, 190)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-0.5, -1, -1)
	viewport.Parent = card

	local camera = Instance.new("Camera")
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	local model = AnimalModels.create(group.Species, group.Mutation)
	model.Parent = viewport
	local boxCF, boxSize = model:GetBoundingBox()
	local distance = math.max(boxSize.X, boxSize.Y, boxSize.Z) * 1.35 + 1
	camera.CFrame = CFrame.lookAt(boxCF.Position + Vector3.new(0, boxSize.Y * 0.12, -distance), boxCF.Position)

	makeLabel(card, {
		Position = UDim2.new(0, 4, 0, 86),
		Size = UDim2.new(1, -8, 0, 24),
		Text = group.Species,
		TextColor3 = rarity.Color,
	})

	-- Tag line: size + mutation, or the rarity name if plain
	local tags = {}
	if group.Size and group.Size ~= "Normal" then
		table.insert(tags, "⬆ " .. group.Size)
	end
	local mutationInfo = MUTATION_LABELS[group.Mutation]
	if mutationInfo then
		table.insert(tags, mutationInfo.Text)
	end
	makeLabel(card, {
		Position = UDim2.new(0, 4, 0, 110),
		Size = UDim2.new(1, -8, 0, 20),
		Text = #tags > 0 and table.concat(tags, " ") or rarity.Name,
		TextColor3 = mutationInfo and mutationInfo.Color or Color3.fromRGB(190, 195, 205),
	})

	makeLabel(card, {
		Position = UDim2.new(0, 4, 1, -24),
		Size = UDim2.new(1, -8, 0, 20),
		Text = "x" .. group.Count,
		TextColor3 = Color3.new(1, 1, 1),
	})

	card.Parent = collectionGrid
end

-- ------------------------------------------------------------
-- Toasts + Mythic announcement
-- ------------------------------------------------------------

local function buildToasts(gui: ScreenGui)
	toastColumn = Instance.new("Frame")
	toastColumn.AnchorPoint = Vector2.new(1, 1)
	toastColumn.Position = UDim2.new(1, -12, 1, -120)
	toastColumn.Size = UDim2.new(0, 260, 0, 300)
	toastColumn.BackgroundTransparency = 1
	toastColumn.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, 6)
	layout.Parent = toastColumn

	announceLabel = makeLabel(gui, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.new(0.8, 0, 0, 54),
		Text = "",
		TextColor3 = Color3.fromRGB(230, 130, 255),
		Visible = false,
	})
	stroke(announceLabel, Color3.fromRGB(20, 20, 25), 3)
	local scale = Instance.new("UIScale")
	scale.Parent = announceLabel
end

function UIController.showToast(text: string, kind: string?)
	local toast = Instance.new("TextLabel")
	toast.Size = UDim2.new(1, 0, 0, 40)
	toast.BackgroundColor3 = PANEL_COLOR
	toast.BackgroundTransparency = 0.2
	toast.Font = FONT
	toast.TextScaled = true
	toast.Text = text
	toast.TextColor3 = kind == "Error" and Color3.fromRGB(255, 120, 120) or Color3.fromRGB(200, 255, 200)
	toast.Parent = toastColumn
	round(toast, 10)
	task.delay(2.2, function()
		local fade = TweenService:Create(toast, TweenInfo.new(0.4), { TextTransparency = 1, BackgroundTransparency = 1 })
		fade:Play()
		fade.Completed:Once(function()
			toast:Destroy()
		end)
	end)
end

function UIController.announce(text: string, color: Color3?)
	announceLabel.Text = text
	announceLabel.TextColor3 = color or Color3.fromRGB(230, 130, 255)
	announceLabel.Visible = true
	local scale = announceLabel:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = 0.05
	TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(3.5, function()
		local out = TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.05 })
		out:Play()
		out.Completed:Once(function()
			announceLabel.Visible = false
		end)
	end)
end

-- ------------------------------------------------------------
-- Render loop
-- ------------------------------------------------------------

local function onHeartbeat(dt: number)
	if displayedCoins ~= targetCoins then
		local step = (targetCoins - displayedCoins) * math.min(dt * 7, 1)
		displayedCoins += step
		if math.abs(targetCoins - displayedCoins) < 0.6 then
			displayedCoins = targetCoins
		end
		coinsLabel.Text = "🪙 " .. comma(displayedCoins)
	end

	if luckSecondsLeft > 0 then
		luckSecondsLeft = math.max(0, luckSecondsLeft - dt)
		luckButton.BackgroundColor3 = Color3.fromRGB(60, 200, 130)
		luckTitleLabel.Text = "🍀 LUCK x" .. luckMultiplier
		luckSubLabel.Text = math.ceil(luckSecondsLeft) .. "s left"
	else
		luckButton.BackgroundColor3 = Color3.fromRGB(90, 170, 220)
		luckTitleLabel.Text = "🍀 LUCK x" .. GameConfig.LuckBoost.Multiplier
		luckSubLabel.Text = comma(GameConfig.LuckBoost.Cost) .. " 🪙"
	end
end

-- ------------------------------------------------------------
-- Public API (called by init.client)
-- ------------------------------------------------------------

function UIController.setState(state: { [string]: any })
	if state.Coins ~= nil and state.Coins ~= targetCoins then
		local gained = state.Coins > targetCoins
		targetCoins = state.Coins
		if gained then
			coinsScale.Scale = 1.18
			TweenService:Create(coinsScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			Sounds.coinBlip()
		end
	end
	if state.IncomePerSecond ~= nil then
		incomeLabel.Text = "+" .. comma(state.IncomePerSecond) .. " 🪙/s"
	end
	if state.LuckSecondsLeft ~= nil then
		luckSecondsLeft = state.LuckSecondsLeft
	end
	if state.LuckMultiplier ~= nil and state.LuckMultiplier > 1 then
		luckMultiplier = state.LuckMultiplier
	end
end

function UIController.setEggInventory(inventory: { string }, capacity: number)
	eggCounts = {}
	eggTotal = #inventory
	eggCapacity = capacity
	for _, eggName in inventory do
		eggCounts[eggName] = (eggCounts[eggName] or 0) + 1
	end
	refreshEggRows()
end

function UIController.setUpgrades(payload: { Upgrades: { [string]: number }, EggCapacity: number? })
	upgradeLevels = payload.Upgrades or {}
	if payload.EggCapacity then
		eggCapacity = payload.EggCapacity
		refreshEggRows()
	end
	refreshUpgradeRows()
end

function UIController.setCollection(collection: { { Species: string, Mutation: string, Size: string? } })
	for _, child in collectionGrid:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local groups: { [string]: any } = {}
	for _, entry in collection do
		local size = entry.Size or "Normal"
		local key = entry.Species .. "|" .. entry.Mutation .. "|" .. size
		if groups[key] then
			groups[key].Count += 1
		else
			groups[key] = { Species = entry.Species, Mutation = entry.Mutation, Size = size, Count = 1 }
		end
	end

	local sorted = {}
	for _, group in groups do
		local animal = GameConfig.AnimalByName[group.Species]
		if not animal then
			continue -- species no longer in the roster; skip quietly
		end
		local mutation = GameConfig.MutationByName[group.Mutation]
		local size = GameConfig.SizeByName[group.Size]
		group.SortScore = GameConfig.RarityByName[animal.Rarity].Order * 100
			+ (mutation and mutation.SpectacleOrder or 0) * 10
			+ (size and size.SpectacleOrder or 0)
		table.insert(sorted, group)
	end
	table.sort(sorted, function(a, b)
		return a.SortScore > b.SortScore
	end)

	for order, group in sorted do
		makeCard(group, order)
	end
end

function UIController.showError(message: string)
	UIController.showToast(message, "Error")
end

function UIController.init(handlers: { onStartHatch: (string) -> (), onBuyLuck: () -> (), onBuyUpgrade: (string) -> () })
	handlersRef = handlers
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "WildhavenHUD"
	gui.ResetOnSpawn = false

	buildCoinsCorner(gui)
	local eggPanel = buildEggPanel(gui)
	local upgradePanel = buildUpgradePanel(gui)
	buildCollectionUI(gui)
	buildActionButtons(gui, eggPanel, upgradePanel)
	buildToasts(gui)
	refreshEggRows()
	refreshUpgradeRows()

	gui.Parent = playerGui
	RunService.Heartbeat:Connect(onHeartbeat)
end

return UIController
