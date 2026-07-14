--[[
	BiomeWallController — makes the gate walls REAL for players who haven't
	unlocked a biome, and invisible air for players who have.

	How modern games do per-player walls: the wall parts replicate with
	CanCollide = false. Each client flips collision ON locally for biomes
	that are locked *for them*. Physics of your own character runs on your
	client, so a locally-solid wall genuinely stops you — while an unlocked
	friend walks through the same spot freely.

	(A hacked client could turn this off — which is why BiomeService also
	teleports out anyone standing in a locked biome. This controller is the
	polite fence; the server is the law.)
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)

local BiomeWallController = {}

local rebirths = 0
local totalEarned = 0

local function isUnlockedLocally(biomeName: string): boolean
	local biome = GameConfig.BiomeByName[biomeName]
	if not biome then
		return true
	end
	local gate = biome.Gate
	if gate.Rebirths and rebirths < gate.Rebirths then
		return false
	end
	if gate.TotalEarned and totalEarned < gate.TotalEarned then
		return false
	end
	return true
end

local function refreshWall(wall: BasePart)
	local biomeName = wall:GetAttribute("Biome")
	if typeof(biomeName) ~= "string" then
		return
	end
	if isUnlockedLocally(biomeName) then
		wall.CanCollide = false
		wall.Transparency = 1 -- unlocked: the barrier melts away entirely
	else
		wall.CanCollide = true
		wall.Transparency = 0.5 -- locked: shimmering, solid barrier
	end
end

local function refreshSign(sign: BasePart)
	local biomeName = sign:GetAttribute("Biome")
	if typeof(biomeName) ~= "string" then
		return
	end
	local billboard = sign:FindFirstChildOfClass("BillboardGui")
	if billboard then
		billboard.Enabled = not isUnlockedLocally(biomeName)
	end
end

local function refreshAll()
	for _, wall in CollectionService:GetTagged("BiomeWall") do
		if wall:IsA("BasePart") then
			refreshWall(wall)
		end
	end
	for _, sign in CollectionService:GetTagged("BiomeWallSign") do
		if sign:IsA("BasePart") then
			refreshSign(sign)
		end
	end
end

-- Fed from StateUpdate: when progression changes, walls re-evaluate.
function BiomeWallController.setState(state: { [string]: any })
	local changed = false
	if state.Rebirths ~= nil and state.Rebirths ~= rebirths then
		rebirths = state.Rebirths
		changed = true
	end
	if state.TotalEarned ~= nil and state.TotalEarned ~= totalEarned then
		totalEarned = state.TotalEarned
		changed = true
	end
	if changed then
		refreshAll()
	end
end

function BiomeWallController.init()
	CollectionService:GetInstanceAddedSignal("BiomeWall"):Connect(function(wall)
		if wall:IsA("BasePart") then
			refreshWall(wall)
		end
	end)
	refreshAll()
end

return BiomeWallController
