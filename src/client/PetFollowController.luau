--[[
	PetFollowController — renders equipped pets floating behind their
	owners, Pet-Sim style: an arc of hover spots behind the character,
	smooth chasing, a gentle bob, and a little hop when the owner moves.

	Pure visuals. The server's EquipBroadcast says who has what equipped
	(for EVERY player, so you see other people's teams too); this just
	builds the models locally and animates them every frame. Nothing here
	can affect income or equip state.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AnimalModels = require(ReplicatedStorage.AnimalModels)
local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Remotes)

local EQUIP = GameConfig.Equip

local PetFollowController = {}

type FollowPet = {
	Model: Model,
	Pivot: CFrame, -- current smoothed position
	BuildPivot: CFrame, -- model's own pivot offset (feet on ground)
	Seed: number, -- desyncs the bob so pets don't move in lockstep
}

-- userId -> list of follow pets
local crews: { [number]: { FollowPet } } = {}

-- Fan the team out in an arc behind the character: first pet straight
-- behind, then alternating left/right.
local ARC_ANGLES = { 180, 150, 210, 120, 240, 90, 270 }

local function clearCrew(userId: number)
	local crew = crews[userId]
	if crew then
		for _, pet in crew do
			pet.Model:Destroy()
		end
		crews[userId] = nil
	end
end

local function buildCrew(userId: number, pets: { { Species: string, Mutation: string, Size: string } })
	clearCrew(userId)
	if #pets == 0 then
		return
	end
	local crew = {}
	for index, descriptor in pets do
		local model = AnimalModels.create(descriptor.Species, descriptor.Mutation)
		local sizeDef = GameConfig.SizeByName[descriptor.Size or "Normal"]
		local scale = (sizeDef and sizeDef.Scale or 1) * EQUIP.FollowScale
		model:ScaleTo(scale)
		model.Parent = workspace
		table.insert(crew, {
			Model = model,
			Pivot = CFrame.new(0, -100, 0), -- snaps to place on first frame
			BuildPivot = model:GetPivot(),
			Seed = index * 1.7,
		})
	end
	crews[userId] = crew
end

local function onHeartbeat(dt: number)
	local clock = os.clock()
	for userId, crew in crews do
		local player = Players:GetPlayerByUserId(userId)
		local character = player and player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then
			continue -- owner has no character right now; pets wait invisible below
		end
		for index, pet in crew do
			local angle = math.rad(ARC_ANGLES[math.min(index, #ARC_ANGLES)])
			-- Hover spot: behind the character, relative to where they face
			local offset = root.CFrame * CFrame.new(math.sin(angle) * EQUIP.FollowRadius, 0, -math.cos(angle) * EQUIP.FollowRadius)
			local bob = math.sin(clock * 3 + pet.Seed) * EQUIP.BobAmount
			-- Face the same way the owner faces (models are built facing -Z)
			local look = root.CFrame.LookVector
			local target = CFrame.new(offset.Position + Vector3.new(0, EQUIP.FollowHeight - 2 + bob, 0))
				* CFrame.Angles(0, math.atan2(-look.X, -look.Z), 0)

			-- Smooth chase; snap if teleported far away
			local alpha = math.min(dt * EQUIP.LerpSpeed, 1)
			if (pet.Pivot.Position - target.Position).Magnitude > 60 then
				pet.Pivot = target
			else
				pet.Pivot = pet.Pivot:Lerp(target, alpha)
			end
			pet.Model:PivotTo(pet.Pivot * pet.BuildPivot)
		end
	end
end

function PetFollowController.init()
	Remotes.EquipBroadcast.OnClientEvent:Connect(function(payload)
		buildCrew(payload.UserId, payload.Pets or {})
	end)
	Players.PlayerRemoving:Connect(function(player)
		clearCrew(player.UserId)
	end)
	RunService.Heartbeat:Connect(onHeartbeat)
end

return PetFollowController
