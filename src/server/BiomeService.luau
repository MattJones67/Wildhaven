--[[
	BiomeService — who may travel where, and the travel itself.

	Gates are checked LIVE against saved stats (rebirths / lifetime coins),
	so no extra save field exists to corrupt: unlocking is just becoming
	strong enough. BiomeGenerator builds the travel pillars; this service
	attaches the prompts and validates every trip server-side.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Remotes)

local BiomeGenerator = require(script.Parent.BiomeGenerator)
local DataService = require(script.Parent.DataService)

local BiomeService = {}

local lastTravelAt: { [Player]: number } = {}

-- SECURITY: the single source of truth for "can this player enter here".
-- WORLD EXPANSION: unlocks are now PERSISTED in data.UnlockedRegions the
-- first time a gate's requirement is met — so future quest-based unlocks
-- (and one-time unlock celebrations) have a real save field to live in.
function BiomeService.isUnlocked(player: Player, biomeName: string): (boolean, string?)
	local biome = GameConfig.BiomeByName[biomeName]
	if not biome then
		return false, "Unknown biome"
	end
	local data = DataService.get(player)
	if not data then
		return false, "Still loading..."
	end
	data.UnlockedRegions = data.UnlockedRegions or { Forest = true }
	if data.UnlockedRegions[biomeName] then
		return true
	end
	local gate = biome.Gate
	if gate.Rebirths and (data.Rebirths or 0) < gate.Rebirths then
		return false, biome.GateText
	end
	if gate.TotalEarned and (data.TotalEarned or 0) < gate.TotalEarned then
		return false, biome.GateText
	end
	-- Requirement met: record the unlock permanently + celebrate once
	data.UnlockedRegions[biomeName] = true
	Remotes.Notify:FireClient(player, {
		Text = "🔓 " .. biome.Emoji .. " The " .. biomeName .. " is now open to you!",
		Kind = "Event",
	})
	return true
end

local function onTravel(player: Player, destination: string)
	-- SECURITY CHECK 1: rate limit (teleport spam)
	local now = os.clock()
	local last = lastTravelAt[player]
	if last and now - last < 2 then
		return
	end
	lastTravelAt[player] = now

	-- SECURITY CHECK 2: the gate
	local unlocked, gateText = BiomeService.isUnlocked(player, destination)
	local biome = GameConfig.BiomeByName[destination]
	if not unlocked then
		Remotes.Notify:FireClient(player, {
			Text = "🔒 " .. destination .. " — " .. (gateText or "locked"),
			Kind = "Error",
		})
		return
	end

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local target = BiomeGenerator.getTravelTarget(destination)
	if not root or not target then
		return
	end
	root.CFrame = target

	Remotes.Notify:FireClient(player, {
		Text = biome.Emoji .. " Welcome to the " .. destination .. "! " .. biome.PerkText,
		Kind = "Travel",
	})
end

-- SECURITY: the walls are only solid CLIENT-side (per-player collision),
-- so a hacked client can walk through them. This loop is the authority:
-- anyone standing in a biome they haven't unlocked gets sent home.
local function enforceGates()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			continue
		end
		local biomeName = BiomeGenerator.getBiomeAt(root.Position)
		local biome = GameConfig.BiomeByName[biomeName]
		if biomeName == "Forest" or not biome then
			continue
		end
		-- Only counts as "inside" within the biome's gated area
		local flatDistance = (Vector3.new(root.Position.X, 0, root.Position.Z)
			- Vector3.new(biome.Center.X, 0, biome.Center.Z)).Magnitude
		-- 12-stud grace so a locked player can stand AT the gate and read
		-- the sign without being bounced (the pane physically stops them)
		local insideRadius = (biome.GateRadius and biome.GateRadius - 12) or biome.Radius + 40
		if flatDistance > insideRadius then
			continue
		end
		local unlocked = BiomeService.isUnlocked(player, biomeName)
		if not unlocked then
			local home = BiomeGenerator.getTravelTarget("Forest")
			if home then
				root.CFrame = home
				Remotes.Notify:FireClient(player, {
					Text = "🔒 " .. biomeName .. " — " .. biome.GateText,
					Kind = "Error",
				})
			end
		end
	end
end

function BiomeService.init()
	task.spawn(function()
		while true do
			task.wait(2)
			enforceGates()
		end
	end)

	for _, pillar in BiomeGenerator.getTravelPillars() do
		local biome = GameConfig.BiomeByName[pillar.Dest]
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Travel"
		prompt.ObjectText = biome.Emoji .. " " .. pillar.Dest
		prompt.HoldDuration = 0.25 -- tiny hold so you don't warp by accident
		prompt.MaxActivationDistance = 8
		prompt.RequiresLineOfSight = false
		prompt.Parent = pillar.Part
		prompt.Triggered:Connect(function(player)
			onTravel(player, pillar.Dest)
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastTravelAt[player] = nil
	end)
end

return BiomeService
