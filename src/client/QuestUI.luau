--[[
	QuestUI — two pieces:

	  * The GUIDE DIALOG: opens when a guide NPC "talks" (QuestDialog from
	    the server). Shows the guide's greeting and their quests, each with
	    an Accept / progress / TURN IN button by status.
	  * The HUD TRACKER: a slim strip under the goal bar listing every
	    accepted quest with live progress, so you always know what you're
	    hunting while exploring.

	Buttons only *ask*; QuestService validates accepts and turn-ins.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Remotes)
local Sounds = require(script.Parent.Sounds)

local FONT = Enum.Font.FredokaOne
local PANEL_COLOR = Color3.fromRGB(40, 45, 55)
local ROW_COLOR = Color3.fromRGB(55, 62, 75)
local GREEN = Color3.fromRGB(95, 200, 90)
local GOLD = Color3.fromRGB(255, 205, 80)

local QuestUI = {}

local gui: ScreenGui
local trackerFrame: Frame
local dialogPanel: Frame
local dialogTitle: TextLabel
local dialogGreeting: TextLabel
local dialogRows: Frame

local busy = false

-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------

local function round(parent: Instance, radius: number)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
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
	round(button, 10)
	button.Activated:Connect(function()
		Sounds.buttonPress()
	end)
	return button
end

-- ------------------------------------------------------------
-- HUD tracker
-- ------------------------------------------------------------

function QuestUI.setTracker(payload)
	for _, child in trackerFrame:GetChildren() do
		if child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local active = payload and payload.Active or {}
	trackerFrame.Visible = #active > 0
	for order, quest in active do
		if order > 3 then
			break -- keep the HUD tidy; the rest still count silently
		end
		makeLabel(trackerFrame, {
			Size = UDim2.new(1, -12, 0, 22),
			Text = ("%s  %d/%d"):format(quest.Text, quest.Progress, quest.Count),
			TextColor3 = quest.Progress >= quest.Count and GREEN or Color3.fromRGB(230, 235, 245),
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = order,
		})
	end
	trackerFrame.Size = UDim2.new(0, 300, 0, 8 + math.min(#active, 3) * 24)
end

-- ------------------------------------------------------------
-- Guide dialog
-- ------------------------------------------------------------

local function questAction(questId: string, turnIn: boolean)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, result = pcall(function()
			if turnIn then
				return Remotes.TurnInQuest:InvokeServer(questId)
			end
			return Remotes.AcceptQuest:InvokeServer(questId)
		end)
		if ok and result and result.Success then
			if turnIn then
				Sounds.raritySting(4) -- the turn-in fanfare
			else
				Sounds.equipPop()
			end
			if result.Dialog then
				QuestUI.open(result.Dialog) -- refresh the conversation
			end
		else
			Sounds.errorBuzz()
		end
		busy = false
	end)
end

function QuestUI.open(payload)
	dialogTitle.Text = payload.Emoji .. " " .. payload.GuideName
	dialogGreeting.Text = "\"" .. payload.Greeting .. "\""

	for _, child in dialogRows:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	if payload.ChainDone and #payload.Quests <= 1 then
		dialogGreeting.Text ..= "\n(You've done everything I asked — you're a legend here!)"
	end

	for order, quest in payload.Quests do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 74)
		row.BackgroundColor3 = ROW_COLOR
		row.LayoutOrder = order
		row.Parent = dialogRows
		round(row, 10)

		makeLabel(row, {
			Position = UDim2.new(0, 10, 0, 6),
			Size = UDim2.new(1, -130, 0, 30),
			Text = quest.Text,
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		makeLabel(row, {
			Position = UDim2.new(0, 10, 0, 40),
			Size = UDim2.new(1, -130, 0, 24),
			Text = "Reward: " .. quest.RewardText,
			TextColor3 = GOLD,
			TextXAlignment = Enum.TextXAlignment.Left,
		})

		local actionButton = makeButton(row, {
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.new(0, 106, 0, 48),
			BackgroundColor3 = GREEN,
			Text = "Accept",
		})
		if quest.Status == "available" then
			actionButton.Activated:Connect(function()
				questAction(quest.Id, false)
			end)
		elseif quest.Status == "active" then
			actionButton.Text = ("%d/%d"):format(quest.Progress, quest.Count)
			actionButton.BackgroundColor3 = Color3.fromRGB(110, 120, 135)
		elseif quest.Status == "ready" then
			actionButton.Text = "TURN IN ✓"
			actionButton.BackgroundColor3 = GOLD
			actionButton.Activated:Connect(function()
				questAction(quest.Id, true)
			end)
		elseif quest.Status == "cooldown" then
			actionButton.Text = "Tomorrow!"
			actionButton.BackgroundColor3 = Color3.fromRGB(110, 120, 135)
		end
	end

	dialogPanel.Visible = true
	local scale = dialogPanel:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = 0.6
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- ------------------------------------------------------------
-- Boot
-- ------------------------------------------------------------

function QuestUI.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "WildhavenQuests"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 7

	-- Tracker: slim strip under the goal bar
	trackerFrame = Instance.new("Frame")
	trackerFrame.AnchorPoint = Vector2.new(0.5, 0)
	trackerFrame.Position = UDim2.new(0.5, 0, 0, 60)
	trackerFrame.Size = UDim2.new(0, 300, 0, 32)
	trackerFrame.BackgroundColor3 = PANEL_COLOR
	trackerFrame.BackgroundTransparency = 0.45
	trackerFrame.Visible = false
	trackerFrame.Parent = gui
	round(trackerFrame, 10)
	local trackerLayout = Instance.new("UIListLayout")
	trackerLayout.Padding = UDim.new(0, 2)
	trackerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	trackerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	trackerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	trackerLayout.Parent = trackerFrame

	-- Dialog panel
	dialogPanel = Instance.new("Frame")
	dialogPanel.AnchorPoint = Vector2.new(0.5, 0.5)
	dialogPanel.Position = UDim2.new(0.5, 0, 0.45, 0)
	dialogPanel.Size = UDim2.new(0, 420, 0, 320)
	dialogPanel.BackgroundColor3 = PANEL_COLOR
	dialogPanel.Visible = false
	dialogPanel.Parent = gui
	round(dialogPanel, 16)
	local panelScale = Instance.new("UIScale")
	panelScale.Parent = dialogPanel

	dialogTitle = makeLabel(dialogPanel, {
		Position = UDim2.new(0, 14, 0, 10),
		Size = UDim2.new(1, -60, 0, 34),
		Text = "",
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	dialogGreeting = makeLabel(dialogPanel, {
		Position = UDim2.new(0, 14, 0, 46),
		Size = UDim2.new(1, -28, 0, 52),
		Text = "",
		TextColor3 = Color3.fromRGB(210, 216, 226),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	local closeButton = makeButton(dialogPanel, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -10, 0, 10),
		Size = UDim2.new(0, 36, 0, 34),
		BackgroundColor3 = Color3.fromRGB(200, 100, 90),
		Text = "✕",
	})
	closeButton.Activated:Connect(function()
		dialogPanel.Visible = false
	end)

	dialogRows = Instance.new("Frame")
	dialogRows.Position = UDim2.new(0, 14, 0, 104)
	dialogRows.Size = UDim2.new(1, -28, 1, -118)
	dialogRows.BackgroundTransparency = 1
	dialogRows.Parent = dialogPanel
	local rowsLayout = Instance.new("UIListLayout")
	rowsLayout.Padding = UDim.new(0, 8)
	rowsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowsLayout.Parent = dialogRows

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return QuestUI
