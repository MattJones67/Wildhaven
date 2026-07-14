--[[
	ProgressUI — the meta-progression layer of the HUD, kept separate from
	UIController so neither becomes a god-script:

	  * 🎯 Goal strip (top-center): always shows your next objective
	  * 📖 Index button + completion % chip -> the Collection Index panel
	    (silhouette cards fill in as you discover pets; set bonuses listed)
	  * 🔄 Rebirth button -> rebirth panel with progress bar and the trade
	  * Center popups: "Welcome back!", daily reward, with a happy bounce
	  * The full-screen REBIRTH celebration

	Renders server truth only; the one button that acts (REBIRTH) calls a
	handler wired in init.client, and the server re-validates everything.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local AnimalModels = require(ReplicatedStorage.AnimalModels)
local GameConfig = require(ReplicatedStorage.GameConfig)
local IndexUtil = require(ReplicatedStorage.IndexUtil)
local Sounds = require(script.Parent.Sounds)

local FONT = Enum.Font.FredokaOne
local PANEL_COLOR = Color3.fromRGB(40, 45, 55)
local ROW_COLOR = Color3.fromRGB(55, 62, 75)

local ProgressUI = {}

local handlersRef: { onRebirth: () -> () }

-- Server-pushed state
local totalEarned = 0
local nextRequirement = math.huge
local rebirths = 0
local discovered: { [string]: boolean } = {}

-- Instances
local gui: ScreenGui
local goalLabel: TextLabel
local goalScale: UIScale
local indexButton: TextButton
local dexPanel: Frame
local dexGrid: ScrollingFrame
local rebirthPanel: Frame
local rebirthCountLabel: TextLabel
local rebirthBarFill: Frame
local rebirthBarText: TextLabel
local rebirthGoButton: TextButton
local popupFrame: Frame
local popupTitle: TextLabel
local popupBody: TextLabel
local flashFrame: Frame
local celebrateLabel: TextLabel

local panels: { Frame } = {}

-- ------------------------------------------------------------
-- Helpers (small local set; ProgressUI owns its own gui)
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

local function stroke(parent: Instance, color: Color3, thickness: number)
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Parent = parent
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
	return button
end

local function togglePanel(panel: Frame)
	local show = not panel.Visible
	for _, other in panels do
		other.Visible = false
	end
	panel.Visible = show
end

-- ------------------------------------------------------------
-- Goal strip
-- ------------------------------------------------------------

local function buildGoalStrip()
	local strip = Instance.new("Frame")
	strip.AnchorPoint = Vector2.new(0.5, 0)
	strip.Position = UDim2.new(0.5, 0, 0, 10)
	strip.Size = UDim2.new(0, 340, 0, 44)
	strip.BackgroundColor3 = PANEL_COLOR
	strip.BackgroundTransparency = 0.3
	strip.Parent = gui
	round(strip, 12)

	goalLabel = makeLabel(strip, {
		Position = UDim2.new(0, 10, 0, 4),
		Size = UDim2.new(1, -20, 1, -8),
		Text = "🎯 …",
		TextColor3 = Color3.fromRGB(255, 240, 200),
	})
	goalScale = Instance.new("UIScale")
	goalScale.Parent = strip
end

function ProgressUI.setGoal(goal)
	if not goal then
		return
	end
	if goal.Done then
		goalLabel.Text = "🏆 All goals complete!"
		return
	end
	goalLabel.Text = ("🎯 %s  %s/%s"):format(goal.Text, comma(goal.Progress), comma(goal.Target))
	-- Little pop whenever the strip content changes
	goalScale.Scale = 1.08
	TweenService:Create(goalScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- ------------------------------------------------------------
-- Collection Index (dex)
-- ------------------------------------------------------------

local function makePanel(title: string): Frame
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
	table.insert(panels, panel)
	return panel
end

local function buildDex()
	indexButton = makeButton(gui, {
		Position = UDim2.new(0, 12, 0, 114),
		Size = UDim2.new(0, 140, 0, 44),
		BackgroundColor3 = Color3.fromRGB(120, 150, 100),
		Text = "📖 0%",
	})
	stroke(indexButton, Color3.fromRGB(70, 95, 60), 3)

	dexPanel = makePanel("📖 Collection Index")
	dexGrid = Instance.new("ScrollingFrame")
	dexGrid.Position = UDim2.new(0, 12, 0, 52)
	dexGrid.Size = UDim2.new(1, -24, 1, -64)
	dexGrid.BackgroundTransparency = 1
	dexGrid.BorderSizePixel = 0
	dexGrid.ScrollBarThickness = 6
	dexGrid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	dexGrid.CanvasSize = UDim2.new(0, 0, 0, 0)
	dexGrid.Parent = dexPanel
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.new(0, 108, 0, 132)
	layout.CellPadding = UDim2.new(0, 10, 0, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = dexGrid

	indexButton.Activated:Connect(function()
		togglePanel(dexPanel)
	end)
end

local function refreshDex()
	for _, child in dexGrid:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	-- Cards in rarity order (roster is already sorted Common -> Mythic)
	for order, animal in GameConfig.Animals do
		local rarity = GameConfig.RarityByName[animal.Rarity]
		local found = discovered[animal.Name] == true

		local card = Instance.new("Frame")
		card.BackgroundColor3 = found and ROW_COLOR or Color3.fromRGB(32, 35, 42)
		card.LayoutOrder = order
		round(card, 12)
		stroke(card, found and rarity.Color or Color3.fromRGB(60, 64, 72), 3)

		if found then
			local viewport = Instance.new("ViewportFrame")
			viewport.Position = UDim2.new(0, 6, 0, 6)
			viewport.Size = UDim2.new(1, -12, 0, 74)
			viewport.BackgroundTransparency = 1
			viewport.Ambient = Color3.fromRGB(190, 190, 190)
			viewport.LightColor = Color3.new(1, 1, 1)
			viewport.LightDirection = Vector3.new(-0.5, -1, -1)
			viewport.Parent = card
			local camera = Instance.new("Camera")
			camera.Parent = viewport
			viewport.CurrentCamera = camera
			local model = AnimalModels.create(animal.Name, "None")
			model.Parent = viewport
			local boxCF, boxSize = model:GetBoundingBox()
			local distance = math.max(boxSize.X, boxSize.Y, boxSize.Z) * 1.35 + 1
			camera.CFrame = CFrame.lookAt(boxCF.Position + Vector3.new(0, boxSize.Y * 0.12, -distance), boxCF.Position)

			makeLabel(card, {
				Position = UDim2.new(0, 4, 0, 82),
				Size = UDim2.new(1, -8, 0, 24),
				Text = animal.Name,
				TextColor3 = rarity.Color,
			})
		else
			-- Greyed-out mystery silhouette
			makeLabel(card, {
				Position = UDim2.new(0, 0, 0, 10),
				Size = UDim2.new(1, 0, 0, 66),
				Text = "?",
				TextColor3 = Color3.fromRGB(75, 80, 90),
			})
			makeLabel(card, {
				Position = UDim2.new(0, 4, 0, 82),
				Size = UDim2.new(1, -8, 0, 24),
				Text = "???",
				TextColor3 = Color3.fromRGB(110, 115, 125),
			})
		end
		makeLabel(card, {
			Position = UDim2.new(0, 4, 1, -24),
			Size = UDim2.new(1, -8, 0, 20),
			Text = rarity.Name,
			TextColor3 = rarity.Color,
		})
		card.Parent = dexGrid
	end

	-- Set-bonus summary rows at the end of the grid
	for i, reward in GameConfig.IndexRewards do
		local done = IndexUtil.isSetComplete(discovered, reward.Rarity)
		local row = Instance.new("Frame")
		row.BackgroundColor3 = done and Color3.fromRGB(50, 75, 55) or Color3.fromRGB(38, 42, 50)
		row.LayoutOrder = 100 + i
		round(row, 12)
		makeLabel(row, {
			Position = UDim2.new(0, 6, 0, 8),
			Size = UDim2.new(1, -12, 1, -16),
			Text = (done and "✅ " or "🔒 ") .. reward.Label,
			TextColor3 = done and Color3.fromRGB(190, 255, 200) or Color3.fromRGB(140, 146, 156),
			TextWrapped = true,
		})
		row.Parent = dexGrid
	end

	indexButton.Text = "📖 " .. IndexUtil.completionPercent(discovered) .. "%"
end

function ProgressUI.setDiscovered(map: { [string]: boolean })
	discovered = map or {}
	refreshDex()
end

-- ------------------------------------------------------------
-- Rebirth
-- ------------------------------------------------------------

local function buildRebirth()
	local button = makeButton(gui, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 76),
		Size = UDim2.new(0, 150, 0, 52),
		BackgroundColor3 = Color3.fromRGB(230, 110, 120),
		Text = "🔄 Rebirth",
	})
	stroke(button, Color3.fromRGB(150, 60, 70), 3)

	rebirthPanel = makePanel("🔄 Rebirth")

	rebirthCountLabel = makeLabel(rebirthPanel, {
		Position = UDim2.new(0, 16, 0, 50),
		Size = UDim2.new(1, -32, 0, 30),
		Text = "Rebirths: 0",
		TextColor3 = Color3.fromRGB(255, 200, 210),
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	makeLabel(rebirthPanel, {
		Position = UDim2.new(0, 16, 0, 86),
		Size = UDim2.new(1, -32, 0, 110),
		Text = "KEEP: pets, discoveries, eggs, hatches\nRESET: coins + all base upgrades\nGAIN forever: +50% income, +25% luck,\n5% faster hatches, +2 satchel — plus unlocks!",
		TextColor3 = Color3.fromRGB(210, 216, 226),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
	})

	-- Progress bar toward the next rebirth
	local barBack = Instance.new("Frame")
	barBack.Position = UDim2.new(0, 16, 1, -120)
	barBack.Size = UDim2.new(1, -32, 0, 34)
	barBack.BackgroundColor3 = Color3.fromRGB(28, 31, 38)
	barBack.Parent = rebirthPanel
	round(barBack, 10)
	rebirthBarFill = Instance.new("Frame")
	rebirthBarFill.Size = UDim2.new(0, 0, 1, 0)
	rebirthBarFill.BackgroundColor3 = Color3.fromRGB(230, 110, 120)
	rebirthBarFill.Parent = barBack
	round(rebirthBarFill, 10)
	rebirthBarText = makeLabel(barBack, {
		Size = UDim2.new(1, 0, 1, 0),
		Text = "",
		TextColor3 = Color3.new(1, 1, 1),
	})

	rebirthGoButton = makeButton(rebirthPanel, {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.new(0, 260, 0, 62),
		BackgroundColor3 = Color3.fromRGB(120, 126, 136),
		Text = "REBIRTH",
	})
	rebirthGoButton.Activated:Connect(function()
		handlersRef.onRebirth()
	end)

	button.Activated:Connect(function()
		togglePanel(rebirthPanel)
	end)
end

local function refreshRebirth()
	rebirthCountLabel.Text = ("Rebirths: %d   (each = +%d%% income, +%d%% luck)"):format(
		rebirths,
		GameConfig.Rebirth.IncomePerRebirth * 100,
		GameConfig.Rebirth.LuckPerRebirth * 100
	)
	local fraction = math.clamp(totalEarned / math.max(nextRequirement, 1), 0, 1)
	rebirthBarFill.Size = UDim2.new(fraction, 0, 1, 0)
	rebirthBarText.Text = ("%s / %s lifetime 🪙"):format(comma(totalEarned), comma(nextRequirement))
	local ready = totalEarned >= nextRequirement
	rebirthGoButton.BackgroundColor3 = ready and Color3.fromRGB(230, 110, 120) or Color3.fromRGB(120, 126, 136)
	rebirthGoButton.Text = ready and "⭐ REBIRTH NOW! ⭐" or "Keep earning..."
end

function ProgressUI.setState(state: { [string]: any })
	if state.TotalEarned ~= nil then
		totalEarned = state.TotalEarned
	end
	if state.NextRebirthRequirement ~= nil then
		nextRequirement = state.NextRebirthRequirement
	end
	if state.Rebirths ~= nil then
		rebirths = state.Rebirths
	end
	refreshRebirth()
end

-- The big moment: flash, banner, triumphant noise
function ProgressUI.celebrateRebirth(payload)
	flashFrame.BackgroundTransparency = 0.1
	TweenService:Create(flashFrame, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()

	celebrateLabel.Text = ("⭐ REBIRTH #%d! ⭐"):format(payload.Count)
	celebrateLabel.Visible = true
	local scale = celebrateLabel:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = 0.05
	TweenService:Create(scale, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	Sounds.mythicAnnounce()
	Sounds.raritySting(6)

	task.delay(2.6, function()
		local out = TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.05 })
		out:Play()
		out.Completed:Once(function()
			celebrateLabel.Visible = false
		end)
	end)
	if payload.UnlockLabel then
		task.delay(1.2, function()
			ProgressUI.popup("Unlocked!", payload.UnlockLabel)
		end)
	end
	rebirthPanel.Visible = false
end

-- ------------------------------------------------------------
-- Center popups (welcome back / daily reward)
-- ------------------------------------------------------------

local popupQueue = {}
local popupShowing = false

local function showNextPopup()
	local next = table.remove(popupQueue, 1)
	if not next then
		popupShowing = false
		return
	end
	popupShowing = true
	popupTitle.Text = next.Title
	popupBody.Text = next.Body
	popupFrame.Visible = true
	local scale = popupFrame:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = 0.05
	TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	Sounds.hatchReady()
	task.delay(4, function()
		if popupFrame.Visible and popupTitle.Text == next.Title then
			popupFrame.Visible = false
			showNextPopup()
		end
	end)
end

function ProgressUI.popup(title: string, body: string)
	table.insert(popupQueue, { Title = title, Body = body })
	if not popupShowing then
		showNextPopup()
	end
end

local function buildPopups()
	popupFrame = Instance.new("Frame")
	popupFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	popupFrame.Position = UDim2.new(0.5, 0, 0.32, 0)
	popupFrame.Size = UDim2.new(0, 340, 0, 130)
	popupFrame.BackgroundColor3 = PANEL_COLOR
	popupFrame.Visible = false
	popupFrame.Parent = gui
	round(popupFrame, 16)
	stroke(popupFrame, Color3.fromRGB(255, 210, 120), 3)
	local popupScale = Instance.new("UIScale")
	popupScale.Parent = popupFrame

	popupTitle = makeLabel(popupFrame, {
		Position = UDim2.new(0, 12, 0, 10),
		Size = UDim2.new(1, -24, 0, 40),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 225, 150),
	})
	popupBody = makeLabel(popupFrame, {
		Position = UDim2.new(0, 12, 0, 54),
		Size = UDim2.new(1, -24, 0, 60),
		Text = "",
		TextColor3 = Color3.new(1, 1, 1),
		TextWrapped = true,
	})
	-- Tap to dismiss
	local dismiss = Instance.new("TextButton")
	dismiss.Size = UDim2.new(1, 0, 1, 0)
	dismiss.BackgroundTransparency = 1
	dismiss.Text = ""
	dismiss.Parent = popupFrame
	dismiss.Activated:Connect(function()
		popupFrame.Visible = false
		showNextPopup()
	end)

	-- Full-screen flash + banner for the rebirth celebration
	flashFrame = Instance.new("Frame")
	flashFrame.Size = UDim2.new(1, 0, 1, 0)
	flashFrame.BackgroundColor3 = Color3.new(1, 1, 1)
	flashFrame.BackgroundTransparency = 1
	flashFrame.BorderSizePixel = 0
	flashFrame.ZIndex = 5
	flashFrame.Parent = gui

	celebrateLabel = makeLabel(gui, {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.35, 0),
		Size = UDim2.new(0.9, 0, 0, 100),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 120, 130),
		Visible = false,
	})
	celebrateLabel.ZIndex = 6
	stroke(celebrateLabel, Color3.fromRGB(20, 20, 25), 4)
	local celebrateScale = Instance.new("UIScale")
	celebrateScale.Parent = celebrateLabel
end

-- ------------------------------------------------------------
-- Boot
-- ------------------------------------------------------------

function ProgressUI.init(handlers: { onRebirth: () -> () })
	handlersRef = handlers
	gui = Instance.new("ScreenGui")
	gui.Name = "WildhavenMeta"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5

	buildGoalStrip()
	buildDex()
	buildRebirth()
	buildPopups()
	refreshDex()
	refreshRebirth()

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return ProgressUI
