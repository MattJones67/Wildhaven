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

-- SECURITY: the single source of truth for "can this player enter here"
function BiomeService.isUnlocked(player: Player, biomeName: string): (boolean, string?)
	local biome = GameConfig.BiomeByName[biomeName]
	if not biome then
		return false, "Unknown biome"
	end
	local data = DataService.get(player)
	if not data then
		return false, "Still loading..."
	end
	local gate = biome.Gate
	if gate.Rebirths and (data.Rebirths or 0) < gate.Rebirths then
		return false, biome.GateText
	end
	if gate.TotalEarned and (data.TotalEarned or 0) < gate.TotalEarned then
		return false, biome.GateText
	end
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

function BiomeService.init()
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
