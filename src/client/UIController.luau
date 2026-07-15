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
-- (patch 5: "coins" vars now mean SILVER; gold is its own smaller counter)
local displayedCoins = 0
local targetCoins = 0
local targetGold = 0
local potionCounts: { [string]: number } = {}
local activeBuffs: { { Kind: string, Key: string, Mult: number, SecondsLeft: number } } = {}
local eggCounts: { [string]: number } = {}
local eggTotal = 0
local eggCapacity = 3
local upgradeLevels: { [string]: number } = {}
local collectionCache: { { Species: string, Mutation: string, Size: string?, Id: number? } } = {}
local equippedIds: { [number]: boolean } = {}
local equippedCount = 0
local equipSlots = 2
local autoHatchUnlocked = false
local autoHatchEnabled = false

local handlersRef: {
	onStartHatch: (string) -> (),
	onBuyPotion: (string) -> (),
	onUsePotion: (string) -> (),
	onRedeemCode: (string) -> (),
	onBuyUpgrade: (string) -> (),
	onToggleEquip: (number) -> (),
	onToggleAutoHatch: () -> (),
}

-- Instances
local coinsLabel: TextLabel
local coinsScale: UIScale
local goldLabel: TextLabel
local goldScale: UIScale
local incomeLabel: TextLabel
local eggsButton: TextButton
local eggsCountLabel: TextLabel
local potionButton: TextButton
local potionPanel: Frame
local potionRows: Frame
local buffChipsFrame: Frame
local vignette: UIStroke
local codeBox: TextBox
local codeResultLabel: TextLabel
local collectionGrid: ScrollingFrame
local collectionSlotsLabel: TextLabel
local autoHatchButton: TextButton
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
	frame.Size = UDim2.new(0, 230, 0, 128) -- taller: two currencies now
	frame.BackgroundColor3 = PANEL_COLOR
	frame.BackgroundTransparency = 0.25
	frame.Parent = gui
	round(frame, 14)

	-- SILVER: the everyday balance (the old coin counter)
	coinsLabel = makeLabel(frame, {
		Position = UDim2.new(0, 12, 0, 6),
		Size = UDim2.new(1, -24, 0, 40),
		Text = "🪙 0",
		TextColor3 = Color3.fromRGB(210, 215, 225), -- silver, not gold, now
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	coinsScale = Instance.new("UIScale")
	coinsScale.Parent = coinsLabel

	-- GOLD: rare and shiny — smaller line, richer color
	goldLabel = makeLabel(frame, {
		Position = UDim2.new(0, 12, 0, 48),
		Size = UDim2.new(1, -24, 0, 32),
		Text = "🌕 0",
		TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	goldScale = Instance.new("UIScale")
	goldScale.Parent = goldLabel

	incomeLabel = makeLabel(frame, {
		Position = UDim2.new(0, 12, 0, 86),
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

	-- PATCH 5: the x2 Luck button is GONE — this opens the potion bag/shop
	potionButton = makeButton(gui, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 205, 1, -20),
		Size = UDim2.new(0, 160, 0, 88),
		BackgroundColor3 = Color3.fromRGB(150, 110, 200),
		Text = "🧪 POTIONS",
	})
	stroke(potionButton, Color3.fromRGB(90, 60, 130), 3)
	potionButton.Activated:Connect(function()
		togglePanel(potionPanel)
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

	-- AUTO-HATCH toggle (rebirth 2 unlock): satchel eggs hatch themselves
	local autoRow = Instance.new("Frame")
	autoRow.Size = UDim2.new(1, 0, 0, 54)
	autoRow.BackgroundColor3 = Color3.fromRGB(45, 50, 62)
	autoRow.LayoutOrder = 99
	autoRow.Parent = eggPanelRows
	round(autoRow, 12)
	makeLabel(autoRow, {
		Position = UDim2.new(0, 12, 0, 6),
		Size = UDim2.new(0.55, 0, 1, -12),
		Text = "🤖 Auto-Hatch",
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	autoHatchButton = makeButton(autoRow, {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.new(0, 130, 0, 40),
		BackgroundColor3 = Color3.fromRGB(110, 120, 115),
		Text = "🔒 Rebirth 2",
	})
	autoHatchButton.Activated:Connect(function()
		handlersRef.onToggleAutoHatch()
	end)

	return panel
end

local function refreshAutoHatch()
	if not autoHatchUnlocked then
		autoHatchButton.Text = "🔒 Rebirth 2"
		autoHatchButton.BackgroundColor3 = Color3.fromRGB(110, 120, 115)
	elseif autoHatchEnabled then
		autoHatchButton.Text = "ON"
		autoHatchButton.BackgroundColor3 = GREEN
	else
		autoHatchButton.Text = "OFF"
		autoHatchButton.BackgroundColor3 = Color3.fromRGB(140, 120, 110)
	end
end

function UIController.setAutoHatch(unlocked: boolean, enabled: boolean)
	autoHatchUnlocked = unlocked
	autoHatchEnabled = enabled
	refreshAutoHatch()
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

-- THE single source-of-truth renderer for upgrade rows (bug fix, patch 4).
-- It reads ONLY server-pushed state (upgradeLevels) + the live coin count,
-- and is re-run after every purchase AND whenever coins change — so the
-- level, price, and affordability can never go stale until a menu reopen.
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
			local price = upgrade.Prices[level + 1]
			refs.Effect.Text = describeValue(upgrade, level) .. " → " .. describeValue(upgrade, level + 1)
			-- PATCH 5 currency split: Aesthetic = GOLD 🌕, functional = SILVER 🪙
			local isGoldPriced = upgrade.Kind == "Aesthetic"
			refs.Button.Text = comma(price) .. (isGoldPriced and " 🌕" or " 🪙")
			local canAfford = isGoldPriced and targetGold >= price or (not isGoldPriced and targetCoins >= price)
			refs.Button.BackgroundColor3 = canAfford and GOLD or Color3.fromRGB(150, 135, 95)
		end
	end
end

-- ------------------------------------------------------------
-- Potion panel (patch 5): your bag on top, the silver shop below
-- ------------------------------------------------------------

function UIController.refreshPotionRows()
	if not potionRows then
		return
	end
	for _, child in potionRows:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local order = 0
	local function addRow(potion, owned: number, isShop: boolean)
		order += 1
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 56)
		row.BackgroundColor3 = ROW_COLOR
		row.LayoutOrder = order
		row.Parent = potionRows
		round(row, 10)
		stroke(row, potion.Color, 2)
		makeLabel(row, {
			Position = UDim2.new(0, 10, 0, 6),
			Size = UDim2.new(1, -140, 0, 26),
			Text = potion.Emoji .. " " .. potion.Title .. (isShop and "" or ("  x" .. owned)),
			TextColor3 = potion.Color,
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		-- Hatch potions multiply hatch TIME, so describe them as "% faster"
		local effect
		if potion.Kind == "Luck" then
			effect = "x" .. tostring(potion.Mult) .. " luck"
		else
			effect = math.floor((1 - potion.Mult) * 100 + 0.5) .. "% faster hatches"
		end
		makeLabel(row, {
			Position = UDim2.new(0, 10, 0, 32),
			Size = UDim2.new(1, -140, 0, 18),
			Text = ("%s for %d:%02d"):format(effect, math.floor(potion.DurationSeconds / 60), potion.DurationSeconds % 60),
			TextColor3 = Color3.fromRGB(190, 198, 210),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		local actionButton = makeButton(row, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -8, 0.5, 0),
			Size = UDim2.new(0, 116, 0, 40),
			BackgroundColor3 = isShop and GOLD or GREEN,
			Text = isShop and (comma(potion.SilverCost) .. " 🪙") or "DRINK",
		})
		actionButton.Activated:Connect(function()
			if isShop then
				handlersRef.onBuyPotion(potion.Key)
			else
				handlersRef.onUsePotion(potion.Key)
			end
		end)
	end

	-- Your bag first (anything owned, shop or not)
	for _, potion in GameConfig.Potions do
		if (potionCounts[potion.Key] or 0) > 0 then
			addRow(potion, potionCounts[potion.Key], false)
		end
	end
	-- Then the silver shop (basic tiers only; Majors come from the trader)
	order += 1
	local header = makeLabel(potionRows, {
		Size = UDim2.new(1, -8, 0, 24),
		Text = "— Shop (silver) · rarer potions: Lucky Blocks & the Trader —",
		TextColor3 = Color3.fromRGB(160, 168, 180),
		LayoutOrder = order,
	})
	header.TextScaled = true
	for _, potion in GameConfig.Potions do
		if potion.SilverCost then
			addRow(potion, 0, true)
		end
	end
end

local function buildPotionPanel(gui: ScreenGui)
	potionPanel = makePanel(gui, "🧪 Potions")
	potionRows = Instance.new("ScrollingFrame")
	potionRows.Position = UDim2.new(0, 12, 0, 52)
	potionRows.Size = UDim2.new(1, -24, 1, -64)
	potionRows.BackgroundTransparency = 1
	potionRows.BorderSizePixel = 0
	potionRows.ScrollBarThickness = 6
	potionRows.AutomaticCanvasSize = Enum.AutomaticSize.Y
	potionRows.CanvasSize = UDim2.new(0, 0, 0, 0)
	potionRows.Parent = potionPanel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = potionRows
end

-- ------------------------------------------------------------
-- Codes panel (patch 5): the gold faucet with a text box
-- ------------------------------------------------------------

local function buildCodesUI(gui: ScreenGui)
	local toggle = makeButton(gui, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 76),
		Size = UDim2.new(0, 150, 0, 44),
		BackgroundColor3 = Color3.fromRGB(120, 160, 120),
		Text = "🎁 Codes",
	})
	stroke(toggle, Color3.fromRGB(70, 100, 70), 3)

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.35, 0)
	panel.Size = UDim2.new(0, 340, 0, 190)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.Visible = false
	panel.Parent = gui
	round(panel, 14)
	table.insert(panels, panel)

	makeLabel(panel, {
		Position = UDim2.new(0, 14, 0, 8),
		Size = UDim2.new(1, -28, 0, 30),
		Text = "🎁 Redeem a Code",
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	codeBox = Instance.new("TextBox")
	codeBox.Position = UDim2.new(0, 14, 0, 48)
	codeBox.Size = UDim2.new(1, -28, 0, 44)
	codeBox.BackgroundColor3 = Color3.fromRGB(28, 31, 38)
	codeBox.Font = Enum.Font.FredokaOne
	codeBox.TextSize = 22
	codeBox.TextColor3 = Color3.new(1, 1, 1)
	codeBox.PlaceholderText = "TYPE CODE HERE"
	codeBox.PlaceholderColor3 = Color3.fromRGB(120, 126, 138)
	codeBox.Text = ""
	codeBox.ClearTextOnFocus = false
	codeBox.Parent = panel
	round(codeBox, 10)

	local redeemButton = makeButton(panel, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 102),
		Size = UDim2.new(0, 180, 0, 44),
		BackgroundColor3 = GREEN,
		Text = "REDEEM",
	})
	redeemButton.Activated:Connect(function()
		handlersRef.onRedeemCode(codeBox.Text)
	end)

	codeResultLabel = makeLabel(panel, {
		Position = UDim2.new(0, 14, 1, -36),
		Size = UDim2.new(1, -28, 0, 26),
		Text = "",
		TextColor3 = Color3.fromRGB(190, 198, 210),
	})

	toggle.Activated:Connect(function()
		togglePanel(panel)
	end)
end

-- Called by init.client with each redeem outcome
function UIController.setCodeResult(text: string, success: boolean)
	codeResultLabel.Text = text
	codeResultLabel.TextColor3 = success and Color3.fromRGB(150, 255, 170) or Color3.fromRGB(255, 130, 120)
	if success then
		codeBox.Text = ""
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

	-- Live "2/2 equipped" readout in the panel header
	collectionSlotsLabel = makeLabel(panel, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -16, 0, 12),
		Size = UDim2.new(0, 190, 0, 30),
		Text = "⭐ 0/2 equipped",
		TextColor3 = Color3.fromRGB(255, 225, 150),
		TextXAlignment = Enum.TextXAlignment.Right,
	})

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
	layout.CellSize = UDim2.new(0, 116, 0, 192)
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
		Position = UDim2.new(0, 4, 0, 130),
		Size = UDim2.new(1, -8, 0, 18),
		Text = "x" .. group.Count,
		TextColor3 = Color3.new(1, 1, 1),
	})

	-- EQUIP CONTROLS: which of this group's pets are on the team?
	local equippedHere = 0
	local equipTargetId, unequipTargetId
	for _, id in group.Ids do
		if equippedIds[id] then
			equippedHere += 1
			unequipTargetId = id
		elseif not equipTargetId then
			equipTargetId = id
		end
	end

	if equippedHere > 0 then
		-- Star badge in the corner + green glow on the border
		makeLabel(card, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -4, 0, 2),
			Size = UDim2.new(0, 44, 0, 22),
			Text = "⭐" .. (equippedHere > 1 and equippedHere or ""),
			TextColor3 = Color3.fromRGB(255, 225, 150),
		})
	end

	local equipButton = makeButton(card, {
		Position = UDim2.new(0, 6, 1, -38),
		Size = UDim2.new(equippedHere > 0 and 0.55 or 1, equippedHere > 0 and -8 or -12, 0, 32),
		BackgroundColor3 = equipTargetId and GREEN or Color3.fromRGB(110, 120, 115),
		Text = "EQUIP",
	})
	equipButton.Activated:Connect(function()
		if equipTargetId then
			handlersRef.onToggleEquip(equipTargetId)
		end
	end)

	if equippedHere > 0 then
		local unequipButton = makeButton(card, {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -6, 1, -38),
			Size = UDim2.new(0.4, -4, 0, 32),
			BackgroundColor3 = Color3.fromRGB(200, 110, 100),
			Text = "－",
		})
		unequipButton.Activated:Connect(function()
			if unequipTargetId then
				handlersRef.onToggleEquip(unequipTargetId)
			end
		end)
	end

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

-- Buff chips: "🍀 x1.5 3:21" pills under the currency corner, plus a
-- colored screen-edge vignette while anything is active (patch 5 juice)
local function refreshBuffChips()
	for _, child in buffChipsFrame:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local vignetteColor = nil
	for order, buff in activeBuffs do
		local potion = GameConfig.PotionByKey[buff.Key]
		local minutes = math.floor(buff.SecondsLeft / 60)
		local seconds = buff.SecondsLeft % 60
		local effect = buff.Kind == "Hatch"
			and ("+" .. math.floor((1 - buff.Mult) * 100 + 0.5) .. "%")
			or ("x" .. tostring(buff.Mult))
		local chip = makeLabel(buffChipsFrame, {
			Size = UDim2.new(0, 118, 0, 28),
			Text = ("%s %s %d:%02d"):format(potion and potion.Emoji or "✨", effect, minutes, seconds),
			TextColor3 = potion and potion.Color or Color3.new(1, 1, 1),
			BackgroundColor3 = Color3.fromRGB(30, 34, 42),
			BackgroundTransparency = 0.25,
			LayoutOrder = order,
		})
		round(chip, 8)
		vignetteColor = vignetteColor or (potion and potion.Color)
	end
	buffChipsFrame.Visible = #activeBuffs > 0
	if vignetteColor then
		vignette.Color = vignetteColor
		vignette.Transparency = 0.65
	else
		vignette.Transparency = 1
	end
end

local function onHeartbeat(dt: number)
	if displayedCoins ~= targetCoins then
		local step = (targetCoins - displayedCoins) * math.min(dt * 7, 1)
		displayedCoins += step
		if math.abs(targetCoins - displayedCoins) < 0.6 then
			displayedCoins = targetCoins
		end
		coinsLabel.Text = "🪙 " .. comma(displayedCoins)
	end
end

-- ------------------------------------------------------------
-- Public API (called by init.client)
-- ------------------------------------------------------------

function UIController.setState(state: { [string]: any })
	if state.Silver ~= nil and state.Silver ~= targetCoins then
		local gained = state.Silver > targetCoins
		targetCoins = state.Silver
		if gained then
			coinsScale.Scale = 1.18
			TweenService:Create(coinsScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			Sounds.coinBlip()
		end
		-- Silver changed -> re-evaluate every price button (part of the
		-- "always render from authoritative state" bug fix)
		refreshUpgradeRows()
	end
	if state.Gold ~= nil and state.Gold ~= targetGold then
		local gained = state.Gold > targetGold
		targetGold = state.Gold
		goldLabel.Text = "🌕 " .. comma(targetGold)
		if gained then
			-- Gold is rare: bigger pop, richer sound
			goldScale.Scale = 1.35
			TweenService:Create(goldScale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			Sounds.goldGain()
		end
		refreshUpgradeRows()
	end
	if state.IncomePerSecond ~= nil then
		incomeLabel.Text = "+" .. comma(state.IncomePerSecond) .. " 🪙/s"
	end
	if state.Buffs ~= nil then
		activeBuffs = state.Buffs
		refreshBuffChips()
	end
end

-- Potion inventory changed (bought / used / rewarded)
function UIController.setPotions(potions: { [string]: number })
	potionCounts = potions or {}
	UIController.refreshPotionRows()
end

function UIController.setEggInventory(inventory: { any }, capacity: number)
	eggCounts = {}
	eggTotal = #inventory
	eggCapacity = capacity
	for _, egg in inventory do
		-- patch 6: entries are {Type, Quality} tables (old saves migrated)
		local eggName = typeof(egg) == "table" and egg.Type or egg
		eggCounts[eggName] = (eggCounts[eggName] or 0) + 1
	end
	refreshEggRows()
end

function UIController.setUpgrades(payload: { Upgrades: { [string]: number }, EggCapacity: number?, EquipSlots: number? })
	upgradeLevels = payload.Upgrades or {}
	if payload.EggCapacity then
		eggCapacity = payload.EggCapacity
		refreshEggRows()
	end
	if payload.EquipSlots then
		equipSlots = payload.EquipSlots
		rebuildCollection()
	end
	refreshUpgradeRows()
end

local function rebuildCollection()
	for _, child in collectionGrid:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local groups: { [string]: any } = {}
	for _, entry in collectionCache do
		local size = entry.Size or "Normal"
		local key = entry.Species .. "|" .. entry.Mutation .. "|" .. size
		if groups[key] then
			groups[key].Count += 1
			table.insert(groups[key].Ids, entry.Id)
		else
			groups[key] = { Species = entry.Species, Mutation = entry.Mutation, Size = size, Count = 1, Ids = { entry.Id } }
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
	collectionSlotsLabel.Text = ("⭐ %d/%d equipped"):format(equippedCount, equipSlots)
end

function UIController.setCollection(collection: { { Species: string, Mutation: string, Size: string?, Id: number? } })
	collectionCache = collection or {}
	rebuildCollection()
end

-- Called on EquipUpdate: refresh which cards show as equipped
function UIController.setEquipped(payload: { Equipped: { number }, Slots: number? })
	equippedIds = {}
	equippedCount = 0
	for _, id in payload.Equipped or {} do
		equippedIds[id] = true
		equippedCount += 1
	end
	if payload.Slots then
		equipSlots = payload.Slots
	end
	rebuildCollection()
end

function UIController.showError(message: string)
	UIController.showToast(message, "Error")
end

function UIController.init(handlers)
	handlersRef = handlers
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local gui = Instance.new("ScreenGui")
	gui.Name = "WildhavenHUD"
	gui.ResetOnSpawn = false

	buildCoinsCorner(gui)
	local eggPanel = buildEggPanel(gui)
	local upgradePanel = buildUpgradePanel(gui)
	buildPotionPanel(gui) -- before the action bar (its button toggles this)
	buildCollectionUI(gui)
	buildActionButtons(gui, eggPanel, upgradePanel)
	buildCodesUI(gui)
	buildToasts(gui)

	-- Buff chips row under the currency corner
	buffChipsFrame = Instance.new("Frame")
	buffChipsFrame.Position = UDim2.new(0, 12, 0, 250)
	buffChipsFrame.Size = UDim2.new(0, 260, 0, 30)
	buffChipsFrame.BackgroundTransparency = 1
	buffChipsFrame.Visible = false
	buffChipsFrame.Parent = gui
	local chipsLayout = Instance.new("UIListLayout")
	chipsLayout.FillDirection = Enum.FillDirection.Horizontal
	chipsLayout.Padding = UDim.new(0, 6)
	chipsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	chipsLayout.Parent = buffChipsFrame

	-- Screen-edge vignette while a buff runs (color = the potion's)
	local vignetteFrame = Instance.new("Frame")
	vignetteFrame.Size = UDim2.new(1, 0, 1, 0)
	vignetteFrame.BackgroundTransparency = 1
	vignetteFrame.ZIndex = 0
	vignetteFrame.Parent = gui
	vignette = Instance.new("UIStroke")
	vignette.Thickness = 7
	vignette.Transparency = 1
	vignette.Parent = vignetteFrame

	refreshEggRows()
	refreshUpgradeRows()
	UIController.refreshPotionRows()

	gui.Parent = playerGui
	RunService.Heartbeat:Connect(onHeartbeat)
end

return UIController
