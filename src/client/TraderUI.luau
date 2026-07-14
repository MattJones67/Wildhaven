--[[
	TraderUI — Barnaby's shop window (patch 5). Opens when the server fires
	TraderDialog (you pressed Shop at his stall): his name, a line of
	patter, a live "leaves in m:ss" countdown for urgency, and the visit's
	limited stock with GOLD prices and remaining quantities.

	Buying just asks the server; TraderService re-validates everything and
	returns the refreshed stock so sold-out rows update instantly.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Remotes = require(ReplicatedStorage.Remotes)
local Sounds = require(script.Parent.Sounds)

local FONT = Enum.Font.FredokaOne
local PANEL_COLOR = Color3.fromRGB(40, 45, 55)
local GOLD = Color3.fromRGB(255, 205, 80)

local TraderUI = {}

local gui: ScreenGui
local panel: Frame
local titleLabel: TextLabel
local lineLabel: TextLabel
local timerLabel: TextLabel
local rowsFrame: Frame

local leavesAt = 0
local busy = false

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

local function buyItem(index: number)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, result = pcall(function()
			return Remotes.BuyTraderItem:InvokeServer(index)
		end)
		if ok and result and result.Success then
			Sounds.goldGain()
			if result.Dialog then
				TraderUI.open(result.Dialog)
			end
		else
			Sounds.errorBuzz()
		end
		busy = false
	end)
end

function TraderUI.open(payload)
	titleLabel.Text = "🎒 " .. payload.Name
	lineLabel.Text = "\"" .. payload.Line .. "\""
	leavesAt = os.clock() + (payload.LeavesIn or 0)

	for _, child in rowsFrame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for order, item in payload.Stock do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, -8, 0, 58)
		row.BackgroundColor3 = Color3.fromRGB(55, 62, 75)
		row.LayoutOrder = order
		row.Parent = rowsFrame
		round(row, 10)

		makeLabel(row, {
			Position = UDim2.new(0, 10, 0, 6),
			Size = UDim2.new(1, -140, 0, 28),
			Text = item.Title,
			TextColor3 = Color3.new(1, 1, 1),
			TextXAlignment = Enum.TextXAlignment.Left,
		})
		makeLabel(row, {
			Position = UDim2.new(0, 10, 0, 34),
			Size = UDim2.new(1, -140, 0, 18),
			Text = item.Left > 0 and (item.Left .. " left this visit") or "SOLD OUT",
			TextColor3 = item.Left > 0 and Color3.fromRGB(190, 198, 210) or Color3.fromRGB(255, 130, 120),
			TextXAlignment = Enum.TextXAlignment.Left,
		})

		local buyButton = Instance.new("TextButton")
		buyButton.AnchorPoint = Vector2.new(1, 0.5)
		buyButton.Position = UDim2.new(1, -8, 0.5, 0)
		buyButton.Size = UDim2.new(0, 116, 0, 42)
		buyButton.BackgroundColor3 = item.Left > 0 and GOLD or Color3.fromRGB(110, 120, 135)
		buyButton.Font = FONT
		buyButton.TextScaled = true
		buyButton.TextColor3 = Color3.fromRGB(40, 35, 20)
		buyButton.AutoButtonColor = false
		buyButton.Text = item.Gold .. " 🌕"
		buyButton.Parent = row
		round(buyButton, 10)
		if item.Left > 0 then
			buyButton.Activated:Connect(function()
				Sounds.buttonPress()
				buyItem(item.Index)
			end)
		end
	end

	panel.Visible = true
	local scale = panel:FindFirstChildOfClass("UIScale") :: UIScale
	scale.Scale = 0.6
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

function TraderUI.init()
	gui = Instance.new("ScreenGui")
	gui.Name = "WildhavenTrader"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 8

	panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.45, 0)
	panel.Size = UDim2.new(0, 400, 0, 320)
	panel.BackgroundColor3 = PANEL_COLOR
	panel.Visible = false
	panel.Parent = gui
	round(panel, 16)
	local scale = Instance.new("UIScale")
	scale.Parent = panel

	titleLabel = makeLabel(panel, {
		Position = UDim2.new(0, 14, 0, 10),
		Size = UDim2.new(1, -120, 0, 32),
		Text = "🎒",
		TextColor3 = GOLD,
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	timerLabel = makeLabel(panel, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -52, 0, 12),
		Size = UDim2.new(0, 110, 0, 28),
		Text = "",
		TextColor3 = Color3.fromRGB(255, 160, 150),
		TextXAlignment = Enum.TextXAlignment.Right,
	})
	lineLabel = makeLabel(panel, {
		Position = UDim2.new(0, 14, 0, 46),
		Size = UDim2.new(1, -28, 0, 40),
		Text = "",
		TextColor3 = Color3.fromRGB(210, 216, 226),
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	local closeButton = Instance.new("TextButton")
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -10, 0, 10)
	closeButton.Size = UDim2.new(0, 34, 0, 32)
	closeButton.BackgroundColor3 = Color3.fromRGB(200, 100, 90)
	closeButton.Font = FONT
	closeButton.TextScaled = true
	closeButton.TextColor3 = Color3.new(1, 1, 1)
	closeButton.AutoButtonColor = false
	closeButton.Text = "✕"
	closeButton.Parent = panel
	round(closeButton, 10)
	closeButton.Activated:Connect(function()
		panel.Visible = false
	end)

	rowsFrame = Instance.new("Frame")
	rowsFrame.Position = UDim2.new(0, 14, 0, 92)
	rowsFrame.Size = UDim2.new(1, -28, 1, -104)
	rowsFrame.BackgroundTransparency = 1
	rowsFrame.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = rowsFrame

	-- Countdown ticks locally; closes when he's gone
	task.spawn(function()
		while true do
			task.wait(1)
			if panel.Visible then
				local left = math.max(0, math.floor(leavesAt - os.clock()))
				timerLabel.Text = ("⏳ %d:%02d"):format(math.floor(left / 60), left % 60)
				if left <= 0 then
					panel.Visible = false
				end
			end
		end
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

return TraderUI
