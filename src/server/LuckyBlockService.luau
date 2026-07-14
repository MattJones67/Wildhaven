--[[
	LuckyBlockService — patch 5's shared world event: a glowing striped
	block periodically FALLS FROM THE SKY somewhere on the continent, with
	a server-wide announcement. First player to reach it and open it claims
	the reward; unopened blocks despawn on a timer.

	A rare GOLDEN variant carries a much better reward table.

	SECURITY: the server picks spawns, owns the claim (first prompt wins,
	distance re-checked), rolls the reward table, and grants through the
	shared Rewards module. There is nothing for a client to fake.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Remotes)

local BiomeGenerator = require(script.Parent.BiomeGenerator)
local Rewards = require(script.Parent.Rewards)

local BLOCKS = GameConfig.LuckyBlocks

local LuckyBlockService = {}

local rng = Random.new()
local activeBlock: Model? = nil
local claimed = false

-- ------------------------------------------------------------
-- Building the block (striped gift-box look, from primitives)
-- ------------------------------------------------------------

local function buildBlock(golden: boolean): Model
	local model = Instance.new("Model")
	model.Name = golden and "GoldenLuckyBlock" or "LuckyBlock"

	local body = Instance.new("Part")
	body.Size = Vector3.new(4, 4, 4)
	body.Color = golden and Color3.fromRGB(255, 200, 60) or Color3.fromRGB(235, 90, 120)
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.Parent = model
	model.PrimaryPart = body

	-- Ribbon stripes
	for _, rotation in { CFrame.Angles(0, 0, 0), CFrame.Angles(0, math.rad(90), 0) } do
		local ribbon = Instance.new("Part")
		ribbon.Size = Vector3.new(4.2, 4.2, 1.1)
		ribbon.Color = golden and Color3.fromRGB(255, 250, 220) or Color3.fromRGB(255, 220, 90)
		ribbon.Material = Enum.Material.Neon
		ribbon.Anchored = true
		ribbon.CanCollide = false
		ribbon.CFrame = body.CFrame * rotation
		ribbon.Parent = model
	end

	local light = Instance.new("PointLight")
	light.Color = golden and Color3.fromRGB(255, 220, 120) or Color3.fromRGB(255, 150, 170)
	light.Brightness = golden and 2.4 or 1.6
	light.Range = golden and 24 or 16
	light.Parent = body

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Color = ColorSequence.new(golden and Color3.fromRGB(255, 225, 130) or Color3.fromRGB(255, 170, 200))
	sparkle.LightEmission = 1
	sparkle.Rate = golden and 14 or 7
	sparkle.Lifetime = NumberRange.new(0.8, 1.6)
	sparkle.Speed = NumberRange.new(1, 3)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Parent = body

	return model
end

local function rollReward(golden: boolean)
	local pool = golden and BLOCKS.GoldenRewards or BLOCKS.Rewards
	local totalWeight = 0
	for _, entry in pool do
		totalWeight += entry.Weight
	end
	local ticket = rng:NextNumber() * totalWeight
	local runningTotal = 0
	for _, entry in pool do
		runningTotal += entry.Weight
		if ticket <= runningTotal then
			return entry
		end
	end
	return pool[1]
end

-- ------------------------------------------------------------
-- The drop
-- ------------------------------------------------------------

local function spawnBlock()
	-- Pick a random LAND biome and one of its egg-spawn points (already
	-- curated to be reachable, sensible spots)
	local landBiomes = {}
	for _, biome in GameConfig.Biomes do
		table.insert(landBiomes, biome)
	end
	local biome = landBiomes[rng:NextInteger(1, #landBiomes)]
	local points = BiomeGenerator.getEggSpawnPoints(biome.Name)
	if #points == 0 then
		return
	end
	local landPos = points[rng:NextInteger(1, #points)] + Vector3.new(0, 2.2, 0)

	local golden = rng:NextNumber() < BLOCKS.GoldenChance
	local block = buildBlock(golden)
	block:PivotTo(CFrame.new(landPos + Vector3.new(0, BLOCKS.FallHeight, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0))
	block.Parent = workspace
	activeBlock = block
	claimed = false

	-- Announce to EVERYONE — this is the "drop what you're doing" moment
	Remotes.Notify:FireAllClients({
		Text = (golden and "🌟 A GOLDEN Lucky Block" or "🧧 A Lucky Block") .. " fell in the " .. biome.Name .. "!",
		Kind = "Event",
	})

	-- The suspenseful descent (server tween: everyone sees the same fall)
	local body = block.PrimaryPart :: Part
	local fallTween = TweenService:Create(body, TweenInfo.new(BLOCKS.FallSeconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		CFrame = CFrame.new(landPos) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
	})
	-- Ribbons follow the body each frame of the tween
	local ribbons = {}
	for _, child in block:GetChildren() do
		if child:IsA("Part") and child ~= body then
			table.insert(ribbons, { Part = child, Offset = body.CFrame:ToObjectSpace(child.CFrame) })
		end
	end
	local followConnection = game:GetService("RunService").Heartbeat:Connect(function()
		for _, ribbon in ribbons do
			ribbon.Part.CFrame = body.CFrame * ribbon.Offset
		end
	end)
	fallTween:Play()
	fallTween.Completed:Wait()
	followConnection:Disconnect()
	for _, ribbon in ribbons do
		ribbon.Part.CFrame = body.CFrame * ribbon.Offset
	end

	-- Landing shockwave puff
	local thud = Instance.new("ParticleEmitter")
	thud.Color = ColorSequence.new(Color3.fromRGB(200, 190, 170))
	thud.Lifetime = NumberRange.new(0.4, 0.9)
	thud.Speed = NumberRange.new(8, 14)
	thud.SpreadAngle = Vector2.new(85, 85)
	thud.Rate = 0
	thud.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
	thud.Parent = body
	thud:Emit(30)

	-- Open prompt: FIRST claim wins
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Open"
	prompt.ObjectText = golden and "Golden Lucky Block" or "Lucky Block"
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = body
	prompt.Triggered:Connect(function(player)
		-- SECURITY: single-claim race guard + real proximity check
		if claimed or activeBlock ~= block then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or (root.Position - body.Position).Magnitude > BLOCKS.OpenMaxDistance then
			return
		end
		claimed = true

		local entry = rollReward(golden)
		Rewards.grant(player, entry.Reward)
		Remotes.Notify:FireClient(player, { Text = "🧧 " .. entry.Label, Kind = "Gold" })
		Remotes.Notify:FireAllClients({
			Text = player.DisplayName .. " opened the " .. (golden and "GOLDEN " or "") .. "Lucky Block! (" .. entry.Label .. ")",
			Kind = "Quest",
		})

		-- Pop! burst then vanish
		local burst = Instance.new("ParticleEmitter")
		burst.Color = ColorSequence.new(golden and Color3.fromRGB(255, 220, 100) or Color3.fromRGB(255, 150, 180), Color3.new(1, 1, 1))
		burst.LightEmission = 1
		burst.Lifetime = NumberRange.new(0.5, 1.2)
		burst.Speed = NumberRange.new(10, 18)
		burst.SpreadAngle = Vector2.new(180, 180)
		burst.Rate = 0
		burst.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
		burst.Parent = body
		burst:Emit(golden and 120 or 60)
		for _, child in block:GetDescendants() do
			if child:IsA("BasePart") then
				child.Transparency = 1
			elseif child:IsA("Light") then
				child.Enabled = false
			end
		end
		task.delay(1.5, function()
			if activeBlock == block then
				activeBlock = nil
			end
			block:Destroy()
		end)
	end)

	-- Unopened? It fades away quietly
	task.delay(BLOCKS.DespawnSeconds, function()
		if activeBlock == block and not claimed then
			activeBlock = nil
			block:Destroy()
		end
	end)
end

function LuckyBlockService.init()
	task.spawn(function()
		while true do
			task.wait(BLOCKS.SpawnIntervalSeconds)
			-- Only one block at a time, and only sometimes — scarcity is the fun
			if activeBlock == nil and rng:NextNumber() < BLOCKS.SpawnChance then
				task.spawn(spawnBlock)
			end
		end
	end)
end

return LuckyBlockService
