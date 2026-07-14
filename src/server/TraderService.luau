--[[
	WanderingTraderService — Barnaby, the roaming GOLD vendor (patch 5).

	Every so often he appears at a random biome's arrival area with a
	server-wide announcement, carrying a LIMITED, randomly-drawn stock
	(potions, rare eggs, exclusive decor). He stays DwellSeconds — a live
	countdown floats over his head — then wanders off.

	SECURITY: the server owns whether he exists, where he is, what's in
	stock and how many are left. Purchases re-check distance, gold, and
	remaining quantity; grants go through the shared Rewards module.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Remotes)

local BiomeGenerator = require(script.Parent.BiomeGenerator)
local DataService = require(script.Parent.DataService)
local IncomeService = require(script.Parent.IncomeService)
local Rewards = require(script.Parent.Rewards)
local TerrainForge = require(script.Parent.TerrainForge)

local TRADER = GameConfig.Trader

local TraderService = {}

local rng = Random.new()
local lastBuyAt: { [Player]: number } = {}

-- Active visit state (nil when he's off wandering)
local visit: {
	Model: Model,
	Position: Vector3,
	Biome: string,
	LeavesAt: number,
	Stock: { { Title: string, Gold: number, Left: number, Reward: any } },
}? = nil

-- ------------------------------------------------------------
-- The trader himself (cloaked wanderer with a big backpack)
-- ------------------------------------------------------------

local function makePart(parent: Instance, props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		(part :: any)[key] = value
	end
	part.Parent = parent
	return part
end

local function makeBall(parent: Instance, size: Vector3, color: Color3, cframe: CFrame, material: Enum.Material?): Part
	local part = makePart(parent, { Size = size, Color = color, CFrame = cframe, Material = material or Enum.Material.SmoothPlastic })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

local function buildTrader(position: Vector3): (Model, TextLabel)
	local cloak = Color3.fromRGB(90, 70, 110)
	local model = Instance.new("Model")
	model.Name = "WanderingTrader"

	-- Robe: a wide teardrop body
	local body = makeBall(model, Vector3.new(2.2, 3, 1.9), cloak, CFrame.new(position + Vector3.new(0, 1.7, 0)))
	body.Name = "Body"
	body.CanQuery = true
	-- Hooded head
	local headCF = CFrame.new(position + Vector3.new(0, 3.6, 0))
	makeBall(model, Vector3.new(1.4, 1.3, 1.3), cloak, headCF)
	makeBall(model, Vector3.new(1.05, 0.95, 1), Color3.fromRGB(245, 215, 180), headCF * CFrame.new(0, -0.08, -0.28))
	for _, side in { -1, 1 } do
		makeBall(model, Vector3.new(0.24, 0.24, 0.16), Color3.new(1, 1, 1), headCF * CFrame.new(side * 0.2, 0, -0.62))
		makeBall(model, Vector3.new(0.12, 0.12, 0.09), Color3.fromRGB(30, 30, 35), headCF * CFrame.new(side * 0.2, 0, -0.68))
	end
	-- Enormous backpack with a bedroll
	makePart(model, {
		Size = Vector3.new(1.9, 2.3, 1.2),
		Color = Color3.fromRGB(140, 100, 60),
		Material = Enum.Material.Fabric,
		CFrame = CFrame.new(position + Vector3.new(0, 2.4, 1.35)),
	})
	local bedroll = makePart(model, {
		Size = Vector3.new(2.2, 0.8, 0.8),
		Color = Color3.fromRGB(180, 90, 80),
		Material = Enum.Material.Fabric,
		CFrame = CFrame.new(position + Vector3.new(0, 3.8, 1.35)),
	})
	bedroll.Shape = Enum.PartType.Cylinder
	-- Walking staff with a lantern
	makePart(model, {
		Size = Vector3.new(0.25, 4.6, 0.25),
		Color = Color3.fromRGB(110, 78, 52),
		Material = Enum.Material.Wood,
		CFrame = CFrame.new(position + Vector3.new(1.4, 2.3, -0.3)) * CFrame.Angles(0, 0, math.rad(8)),
	})
	local lanternGlow = makePart(model, {
		Size = Vector3.new(0.55, 0.7, 0.55),
		Color = Color3.fromRGB(255, 215, 130),
		Material = Enum.Material.Neon,
		CFrame = CFrame.new(position + Vector3.new(1.75, 4.4, -0.35)),
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 215, 140)
	light.Brightness = 1.4
	light.Range = 14
	light.Parent = lanternGlow

	-- Name + countdown billboard
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 190, 0, 56)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 5.4, 0)
	billboard.AlwaysOnTop = true
	billboard.Adornee = body
	billboard.Parent = model
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0, 30)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.FredokaOne
	nameLabel.TextScaled = true
	nameLabel.Text = "🎒 " .. TRADER.Name
	nameLabel.TextColor3 = Color3.fromRGB(255, 220, 130)
	nameLabel.Parent = billboard
	local nameStroke = Instance.new("UIStroke")
	nameStroke.Color = Color3.fromRGB(20, 20, 25)
	nameStroke.Thickness = 2
	nameStroke.Parent = nameLabel
	local timerLabel = Instance.new("TextLabel")
	timerLabel.Position = UDim2.new(0, 0, 0, 30)
	timerLabel.Size = UDim2.new(1, 0, 0, 24)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Font = Enum.Font.FredokaOne
	timerLabel.TextScaled = true
	timerLabel.Text = ""
	timerLabel.TextColor3 = Color3.fromRGB(255, 160, 150)
	timerLabel.Parent = billboard
	local timerStroke = Instance.new("UIStroke")
	timerStroke.Color = Color3.fromRGB(20, 20, 25)
	timerStroke.Thickness = 2
	timerStroke.Parent = timerLabel

	return model, timerLabel
end

-- ------------------------------------------------------------
-- Dialog payload
-- ------------------------------------------------------------

local function dialogPayload()
	if not visit then
		return nil
	end
	local stock = {}
	for index, item in visit.Stock do
		table.insert(stock, { Index = index, Title = item.Title, Gold = item.Gold, Left = item.Left })
	end
	return {
		Name = TRADER.Name,
		Line = TRADER.Lines[rng:NextInteger(1, #TRADER.Lines)],
		Stock = stock,
		LeavesIn = math.max(0, visit.LeavesAt - os.time()),
	}
end

-- ------------------------------------------------------------
-- The visit
-- ------------------------------------------------------------

local function startVisit()
	-- Land somewhere with an arrival area (skip nothing — even locked
	-- biomes: spotting him somewhere you can't reach yet is a tease)
	local biome = GameConfig.Biomes[rng:NextInteger(1, #GameConfig.Biomes)]
	local arrival = TerrainForge.getArrival(biome.Name)
	if not arrival then
		return
	end
	local position = arrival + Vector3.new(-6, 0, 10)

	local model, timerLabel = buildTrader(position)
	model.Parent = workspace

	-- Draw this visit's stock: StockPerVisit distinct items from the pool
	local pool = table.clone(TRADER.Stock)
	local stock = {}
	for _ = 1, math.min(TRADER.StockPerVisit, #pool) do
		local pick = table.remove(pool, rng:NextInteger(1, #pool))
		table.insert(stock, { Title = pick.Title, Gold = pick.Gold, Left = pick.Qty, Reward = pick.Reward })
	end

	visit = {
		Model = model,
		Position = position,
		Biome = biome.Name,
		LeavesAt = os.time() + TRADER.DwellSeconds,
		Stock = stock,
	}

	Remotes.Notify:FireAllClients({
		Text = "🎒 " .. TRADER.Name .. " the Wandering Trader has appeared in the " .. biome.Name .. "!",
		Kind = "Event",
	})

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Shop"
	prompt.ObjectText = TRADER.Name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = model:FindFirstChild("Body")
	prompt.Triggered:Connect(function(player)
		local payload = dialogPayload()
		if payload then
			Remotes.TraderDialog:FireClient(player, payload)
		end
	end)

	-- Countdown + departure
	task.spawn(function()
		local thisVisit = visit
		while visit == thisVisit and visit and os.time() < visit.LeavesAt do
			local left = visit.LeavesAt - os.time()
			timerLabel.Text = ("leaves in %d:%02d"):format(math.floor(left / 60), left % 60)
			task.wait(1)
		end
		if visit == thisVisit and visit then
			Remotes.Notify:FireAllClients({
				Text = "🎒 " .. TRADER.Name .. " has wandered off...",
				Kind = "Quest",
			})
			visit.Model:Destroy()
			visit = nil
		end
	end)
end

-- ------------------------------------------------------------
-- Purchases
-- ------------------------------------------------------------

local function onBuyTraderItem(player: Player, index: any)
	-- SECURITY: rate limit
	local now = os.clock()
	local last = lastBuyAt[player]
	if last and now - last < 1 then
		return { Success = false, Error = "Too fast!" }
	end
	lastBuyAt[player] = now

	-- SECURITY: he must actually be here, and so must you
	if not visit or os.time() >= visit.LeavesAt then
		return { Success = false, Error = "The trader has left!" }
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or (root.Position - visit.Position).Magnitude > TRADER.BuyMaxDistance then
		return { Success = false, Error = "Walk up to the trader first!" }
	end

	local item = typeof(index) == "number" and visit.Stock[index] or nil
	if not item then
		return { Success = false, Error = "No such item" }
	end
	-- SECURITY: limited stock + gold affordability
	if item.Left < 1 then
		return { Success = false, Error = "Sold out!" }
	end
	local data = DataService.get(player)
	if not data then
		return { Success = false, Error = "Still loading..." }
	end
	if data.Gold < item.Gold then
		return { Success = false, Error = "Not enough gold!" }
	end

	data.Gold -= item.Gold
	item.Left -= 1
	Rewards.grant(player, item.Reward)
	IncomeService.pushState(player)

	return { Success = true, Gold = data.Gold, Dialog = dialogPayload() }
end

function TraderService.init()
	Remotes.BuyTraderItem.OnServerInvoke = onBuyTraderItem

	Players.PlayerRemoving:Connect(function(player)
		lastBuyAt[player] = nil
	end)

	task.spawn(function()
		while true do
			task.wait(TRADER.SpawnIntervalSeconds)
			if visit == nil and rng:NextNumber() < TRADER.SpawnChance then
				startVisit()
			end
		end
	end)
end

return TraderService
