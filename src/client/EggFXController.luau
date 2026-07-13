--[[
	EggFXController — client-side life for every egg in the world.

	The server keeps eggs perfectly still (it only cares where they ARE);
	this controller makes them feel alive locally:

	  * "WorldEgg" tag  -> gentle bob + slow spin, so eggs catch your eye
	  * "SlotEgg" tag   -> a floating countdown label, plus a wobble that
	                       gets more excited as the hatch timer runs out
	                       (reads HatchEndsAt/HatchDuration attributes)

	Pure rendering: nothing here affects gameplay, so it needs no remotes.
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local EggFXController = {}

type Tracked = { Model: Model, Base: CFrame, Timer: TextLabel? }

local worldEggs: { [Model]: Tracked } = {}
local slotEggs: { [Model]: Tracked } = {}

local function trackWorldEgg(model: Model)
	if model:IsA("Model") and model.PrimaryPart then
		worldEggs[model] = { Model = model, Base = model:GetPivot() }
	end
end

local function trackSlotEgg(model: Model)
	if not (model:IsA("Model") and model.PrimaryPart) then
		return
	end
	-- Floating countdown label above the incubating egg
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 90, 0, 34)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = model.PrimaryPart
	billboard.Parent = model

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 240, 200)
	label.Parent = billboard
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 20, 25)
	stroke.Thickness = 2
	stroke.Parent = label

	slotEggs[model] = { Model = model, Base = model:GetPivot(), Timer = label }
end

local function onHeartbeat()
	local clock = os.clock()
	local now = os.time()

	for model, tracked in worldEggs do
		if model.Parent == nil then
			worldEggs[model] = nil
			continue
		end
		-- Soft bob + lazy spin: "I'm collectible!"
		local bob = math.sin(clock * 2 + tracked.Base.Position.X) * 0.35
		model:PivotTo(tracked.Base * CFrame.new(0, 0.4 + bob, 0) * CFrame.Angles(0, clock * 0.8, 0))
	end

	for model, tracked in slotEggs do
		if model.Parent == nil then
			slotEggs[model] = nil
			continue
		end
		local endsAt = model:GetAttribute("HatchEndsAt") or 0
		local remaining = math.max(0, endsAt - now)
		if tracked.Timer then
			tracked.Timer.Text = remaining > 0 and (tostring(math.ceil(remaining)) .. "s") or "..."
		end
		-- Wobble builds as the moment approaches: calm -> trembling
		local duration = model:GetAttribute("HatchDuration") or 60
		local progress = 1 - math.clamp(remaining / math.max(duration, 1), 0, 1)
		local intensity = 0.02 + progress * 0.12
		local speed = 3 + progress * 12
		model:PivotTo(tracked.Base * CFrame.Angles(0, 0, math.sin(clock * speed) * intensity))
	end
end

function EggFXController.init()
	for _, model in CollectionService:GetTagged("WorldEgg") do
		trackWorldEgg(model)
	end
	CollectionService:GetInstanceAddedSignal("WorldEgg"):Connect(trackWorldEgg)

	for _, model in CollectionService:GetTagged("SlotEgg") do
		trackSlotEgg(model)
	end
	CollectionService:GetInstanceAddedSignal("SlotEgg"):Connect(trackSlotEgg)

	RunService.Heartbeat:Connect(onHeartbeat)
end

return EggFXController
