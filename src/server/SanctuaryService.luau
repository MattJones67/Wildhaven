--[[
	SanctuaryService — the free-build sanctuary, fully server-authoritative.

	Each player owns a PLOT (claimed from the biome's PlotPositions when
	they join, Lumber-Tycoon style) and a saved build: a list of objects
	{Uid, Key, X, Z, R} in plot-local coordinates, plus pets placed into
	habitat objects. The whole build re-renders from save data on join.

	SECURITY — every remote validates:
	  * rate limit (build-action spam)
	  * catalog key exists / object Uid exists / types are sane
	  * position inside plot bounds, snapped to the grid
	  * object count under the (upgradeable) cap — the PERFORMANCE cap
	  * pet ownership, not equipped, habitat capacity, placed-pet cap
	  * relocation only into unlocked biomes with a free plot

	Income: placed pets earn IN ADDITION to equipped pets (PlayerStats sums
	both, with the matched-habitat and theme bonuses).

	TODO(later patch): visiting other players' sanctuaries — the render
	already lives in workspace.Sanctuaries[playerName], so a visit system
	only needs teleport + permissions, no data changes.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimalModels = require(ReplicatedStorage.AnimalModels)
local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Remotes)
local SanctuaryBuilder = require(ReplicatedStorage.SanctuaryBuilder)

local BiomeGenerator = require(script.Parent.BiomeGenerator)
local BiomeService = require(script.Parent.BiomeService)
local DataService = require(script.Parent.DataService)
local IncomeService = require(script.Parent.IncomeService)
local PlayerStats = require(script.Parent.PlayerStats)

local SANCTUARY = GameConfig.Sanctuary

local SanctuaryService = {}

type Plot = { Biome: string, Index: number, Origin: CFrame, Folder: Model }

local claims: { [string]: { [number]: Player? } } = {} -- claims[biome][plotIndex]
local plots: { [Player]: Plot } = {}
local lastActionAt: { [Player]: number } = {}

-- ------------------------------------------------------------
-- Small helpers
-- ------------------------------------------------------------

local function rateLimited(player: Player): boolean
	local now = os.clock()
	local last = lastActionAt[player]
	if last and now - last < SANCTUARY.MoveRateLimit then
		return true
	end
	lastActionAt[player] = now
	return false
end

local function sanctuaryOf(player: Player)
	local data = DataService.get(player)
	if not data then
		return nil
	end
	-- Older saves predate some fields; patch them in-place
	local sanct = data.Sanctuary
	sanct.Objects = sanct.Objects or {}
	sanct.PlacedPets = sanct.PlacedPets or {}
	sanct.NextUid = sanct.NextUid or 1
	return sanct
end

local function findObject(sanct, uid: number): (any, number?)
	for index, object in sanct.Objects do
		if object.Uid == uid then
			return object, index
		end
	end
	return nil, nil
end

local function snap(value: number): number
	local grid = SANCTUARY.GridSnap
	if grid <= 0 then
		return value
	end
	return math.round(value / grid) * grid
end

local function validPosition(x: any, z: any, r: any): boolean
	if typeof(x) ~= "number" or typeof(z) ~= "number" or typeof(r) ~= "number" then
		return false
	end
	if x ~= x or z ~= z or r ~= r then -- NaN guard
		return false
	end
	local half = SANCTUARY.PlotHalfSize
	return math.abs(x) <= half and math.abs(z) <= half
end

-- ------------------------------------------------------------
-- Rendering (server-built so everyone sees everyone's sanctuary)
-- ------------------------------------------------------------

local sanctuariesFolder: Folder? = nil

local function objectWorldCFrame(plot: Plot, object): CFrame
	return plot.Origin * CFrame.new(object.X, 0, object.Z) * CFrame.Angles(0, math.rad(object.R), 0)
end

local function renderObject(plot: Plot, object)
	local model = SanctuaryBuilder.create(object.Key)
	if not model then
		return
	end
	model.Name = "Obj_" .. object.Uid
	local buildPivot = model:GetPivot()
	model:PivotTo(objectWorldCFrame(plot, object) * buildPivot)
	model.Parent = plot.Folder
end

local function renderPet(player: Player, plot: Plot, sanct, placed)
	local data = DataService.get(player)
	if not data then
		return
	end
	local entry
	for _, candidate in data.Collection do
		if candidate.Id == placed.PetId then
			entry = candidate
			break
		end
	end
	local objectModel = plot.Folder:FindFirstChild("Obj_" .. placed.ObjectUid)
	if not entry or not objectModel then
		return
	end
	-- Park the pet on the first free PetSpot in the pen
	local usedSpots = {}
	for _, other in sanct.PlacedPets do
		if other.ObjectUid == placed.ObjectUid and other.PetId ~= placed.PetId and other.Spot then
			usedSpots[other.Spot] = true
		end
	end
	local spotIndex = 1
	for i = 1, SANCTUARY.HabitatCapacity do
		if not usedSpots[i] then
			spotIndex = i
			break
		end
	end
	placed.Spot = spotIndex

	local spotPart
	for _, descendant in objectModel:GetDescendants() do
		if descendant.Name == "PetSpot" and descendant:GetAttribute("SpotIndex") == spotIndex then
			spotPart = descendant
			break
		end
	end

	local petModel = AnimalModels.create(entry.Species, entry.Mutation)
	local sizeDef = GameConfig.SizeByName[entry.Size or "Normal"]
	petModel:ScaleTo(0.7 * (sizeDef and sizeDef.Scale or 1))
	petModel.Name = "Pet_" .. placed.PetId
	local buildPivot = petModel:GetPivot()
	local target
	if spotPart then
		target = (spotPart :: BasePart).CFrame * CFrame.new(0, -0.6, 0)
	else
		local object = findObject(sanct, placed.ObjectUid)
		if not object then
			petModel:Destroy()
			return
		end
		target = objectWorldCFrame(plot, object)
	end
	petModel:PivotTo(CFrame.new(target.Position) * CFrame.Angles(0, math.rad(180), 0) * buildPivot)
	petModel.Parent = plot.Folder
end

local function renderAll(player: Player)
	local plot = plots[player]
	local sanct = sanctuaryOf(player)
	if not plot or not sanct then
		return
	end
	plot.Folder:ClearAllChildren()

	-- Owner sign at the plot's front edge
	local sign = Instance.new("Part")
	sign.Anchored = true
	sign.Size = Vector3.new(0.4, 2.6, 0.4)
	sign.Color = Color3.fromRGB(110, 78, 52)
	sign.Material = Enum.Material.Wood
	sign.CFrame = plot.Origin * CFrame.new(0, 1.3, SANCTUARY.PlotHalfSize + 1)
	sign.Parent = plot.Folder
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 170, 0, 36)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
	billboard.MaxDistance = 140
	billboard.Adornee = sign
	billboard.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = "🏡 " .. player.DisplayName .. "'s Sanctuary"
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Parent = billboard
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(20, 20, 25)
	stroke.Thickness = 2
	stroke.Parent = label

	for _, object in sanct.Objects do
		renderObject(plot, object)
	end
	for _, placed in sanct.PlacedPets do
		renderPet(player, plot, sanct, placed)
	end
end

-- ------------------------------------------------------------
-- Plot claiming
-- ------------------------------------------------------------

local function claimPlot(player: Player, biomeName: string): boolean
	local plotCFrames = BiomeGenerator.getSanctuaryPlots(biomeName)
	claims[biomeName] = claims[biomeName] or {}
	for index, origin in plotCFrames do
		if claims[biomeName][index] == nil then
			claims[biomeName][index] = player

			local folder = Instance.new("Model")
			folder.Name = player.Name
			folder:SetAttribute("OwnerId", player.UserId)
			folder.Parent = sanctuariesFolder

			plots[player] = { Biome = biomeName, Index = index, Origin = origin, Folder = folder }
			return true
		end
	end
	return false
end

local function releasePlot(player: Player)
	local plot = plots[player]
	if plot then
		if claims[plot.Biome] then
			claims[plot.Biome][plot.Index] = nil
		end
		plot.Folder:Destroy()
		plots[player] = nil
	end
end

-- ------------------------------------------------------------
-- Payload / push
-- ------------------------------------------------------------

function SanctuaryService.payload(player: Player)
	local plot = plots[player]
	local sanct = sanctuaryOf(player)
	if not plot or not sanct then
		return nil
	end
	return {
		Biome = plot.Biome,
		Origin = plot.Origin,
		HalfSize = SANCTUARY.PlotHalfSize,
		Objects = sanct.Objects,
		PlacedPets = sanct.PlacedPets,
		ObjectCap = PlayerStats.getSanctuaryObjectCap(player),
		PetCap = PlayerStats.getSanctuaryPetCap(player),
		PerkText = GameConfig.BiomeByName[plot.Biome].PerkText,
	}
end

local function push(player: Player)
	Remotes.SanctuaryUpdate:FireClient(player, SanctuaryService.payload(player))
	IncomeService.pushState(player) -- placements change income
end

-- Is this pet currently placed? (EquipService asks before equipping)
function SanctuaryService.isPetPlaced(player: Player, petId: number): boolean
	local sanct = sanctuaryOf(player)
	if not sanct then
		return false
	end
	for _, placed in sanct.PlacedPets do
		if placed.PetId == petId then
			return true
		end
	end
	return false
end

-- ------------------------------------------------------------
-- Remote handlers
-- ------------------------------------------------------------

local function onPlaceObject(player: Player, key: any, x: any, z: any, r: any)
	if rateLimited(player) then
		return { Success = false, Error = "Too fast!" }
	end
	local sanct = sanctuaryOf(player)
	local plot = plots[player]
	if not sanct or not plot then
		return { Success = false, Error = "No plot yet!" }
	end
	-- SECURITY: catalog key + sane, in-bounds coordinates
	if typeof(key) ~= "string" or not GameConfig.SanctuaryObjectByKey[key] then
		return { Success = false, Error = "Unknown object" }
	end
	if not validPosition(x, z, r) then
		return { Success = false, Error = "Out of bounds!" }
	end
	-- SECURITY: the performance cap
	if #sanct.Objects >= PlayerStats.getSanctuaryObjectCap(player) then
		return { Success = false, Error = "Object cap reached — upgrade Sanctuary Deed!" }
	end

	local object = { Uid = sanct.NextUid, Key = key, X = snap(x), Z = snap(z), R = math.round(r / 45) * 45 % 360 }
	sanct.NextUid += 1
	table.insert(sanct.Objects, object)
	renderObject(plot, object)
	push(player)
	return { Success = true, Uid = object.Uid }
end

local function onMoveObject(player: Player, uid: any, x: any, z: any, r: any)
	if rateLimited(player) then
		return { Success = false, Error = "Too fast!" }
	end
	local sanct = sanctuaryOf(player)
	local plot = plots[player]
	if not sanct or not plot then
		return { Success = false, Error = "No plot yet!" }
	end
	local object = typeof(uid) == "number" and findObject(sanct, uid) or nil
	if not object then
		return { Success = false, Error = "No such object" }
	end
	if not validPosition(x, z, r) then
		return { Success = false, Error = "Out of bounds!" }
	end
	object.X, object.Z, object.R = snap(x), snap(z), math.round(r / 45) * 45 % 360
	local model = plot.Folder:FindFirstChild("Obj_" .. object.Uid)
	if model then
		model:Destroy()
	end
	renderObject(plot, object)
	-- Pets standing in this pen follow it
	for _, placed in sanct.PlacedPets do
		if placed.ObjectUid == object.Uid then
			local petModel = plot.Folder:FindFirstChild("Pet_" .. placed.PetId)
			if petModel then
				petModel:Destroy()
			end
			renderPet(player, plot, sanct, placed)
		end
	end
	push(player)
	return { Success = true }
end

local function onDeleteObject(player: Player, uid: any)
	if rateLimited(player) then
		return { Success = false, Error = "Too fast!" }
	end
	local sanct = sanctuaryOf(player)
	local plot = plots[player]
	if not sanct or not plot then
		return { Success = false, Error = "No plot yet!" }
	end
	if typeof(uid) ~= "number" then
		return { Success = false, Error = "No such object" }
	end
	local object, index = findObject(sanct, uid)
	if not object or not index then
		return { Success = false, Error = "No such object" }
	end
	-- Evict any pets living in it (they return to the collection unharmed)
	for i = #sanct.PlacedPets, 1, -1 do
		if sanct.PlacedPets[i].ObjectUid == object.Uid then
			local petModel = plot.Folder:FindFirstChild("Pet_" .. sanct.PlacedPets[i].PetId)
			if petModel then
				petModel:Destroy()
			end
			table.remove(sanct.PlacedPets, i)
		end
	end
	table.remove(sanct.Objects, index)
	local model = plot.Folder:FindFirstChild("Obj_" .. object.Uid)
	if model then
		model:Destroy()
	end
	push(player)
	return { Success = true }
end

local function onPlacePet(player: Player, petId: any, objectUid: any)
	if rateLimited(player) then
		return { Success = false, Error = "Too fast!" }
	end
	local data = DataService.get(player)
	local sanct = sanctuaryOf(player)
	local plot = plots[player]
	if not data or not sanct or not plot then
		return { Success = false, Error = "Still loading..." }
	end
	-- SECURITY: pet must exist and be YOURS
	local entry
	for _, candidate in data.Collection do
		if candidate.Id == petId then
			entry = candidate
			break
		end
	end
	if not entry then
		return { Success = false, Error = "You don't own that pet" }
	end
	-- SECURITY: not equipped (a pet can't follow you AND live at home)
	for _, equippedId in data.Equipped do
		if equippedId == petId then
			return { Success = false, Error = "Unequip it first!" }
		end
	end
	if SanctuaryService.isPetPlaced(player, petId) then
		return { Success = false, Error = "Already placed!" }
	end
	-- SECURITY: target must be YOUR habitat with room
	local object = typeof(objectUid) == "number" and findObject(sanct, objectUid) or nil
	local objectDef = object and GameConfig.SanctuaryObjectByKey[object.Key]
	if not object or not objectDef or objectDef.Category ~= "Habitat" then
		return { Success = false, Error = "That's not a habitat" }
	end
	local inThisPen = 0
	local totalPlaced = #sanct.PlacedPets
	for _, placed in sanct.PlacedPets do
		if placed.ObjectUid == object.Uid then
			inThisPen += 1
		end
	end
	if inThisPen >= SANCTUARY.HabitatCapacity then
		return { Success = false, Error = "That pen is full!" }
	end
	if totalPlaced >= PlayerStats.getSanctuaryPetCap(player) then
		return { Success = false, Error = "Placed-pet cap reached — upgrade Habitat Care!" }
	end

	local placed = { PetId = petId, ObjectUid = object.Uid }
	table.insert(sanct.PlacedPets, placed)
	renderPet(player, plot, sanct, placed)
	push(player)

	-- The habitat-bonus chime moment
	local petBiome = GameConfig.AnimalByName[entry.Species] and GameConfig.AnimalByName[entry.Species].Biome
	if objectDef.Biome == petBiome then
		Remotes.Notify:FireClient(player, {
			Text = ("✨ Matched habitat! %s earns x%.2f"):format(entry.Species, SANCTUARY.MatchedHabitatBonus),
			Kind = "Goal",
		})
	end
	return { Success = true }
end

local function onUnplacePet(player: Player, petId: any)
	if rateLimited(player) then
		return { Success = false, Error = "Too fast!" }
	end
	local sanct = sanctuaryOf(player)
	local plot = plots[player]
	if not sanct or not plot then
		return { Success = false, Error = "Still loading..." }
	end
	for index, placed in sanct.PlacedPets do
		if placed.PetId == petId then
			table.remove(sanct.PlacedPets, index)
			local petModel = plot.Folder:FindFirstChild("Pet_" .. petId)
			if petModel then
				petModel:Destroy()
			end
			push(player)
			return { Success = true }
		end
	end
	return { Success = false, Error = "Not placed" }
end

local function onRelocatePlot(player: Player, biomeName: any)
	if rateLimited(player) then
		return { Success = false, Error = "Too fast!" }
	end
	local sanct = sanctuaryOf(player)
	if not sanct then
		return { Success = false, Error = "Still loading..." }
	end
	if typeof(biomeName) ~= "string" or not GameConfig.BiomeByName[biomeName] then
		return { Success = false, Error = "Unknown biome" }
	end
	if plots[player] and plots[player].Biome == biomeName then
		return { Success = false, Error = "Already there!" }
	end
	-- SECURITY: only into biomes you've unlocked
	local unlocked, gateText = BiomeService.isUnlocked(player, biomeName)
	if not unlocked then
		return { Success = false, Error = gateText or "Locked!" }
	end

	releasePlot(player)
	sanct.Biome = biomeName
	if not claimPlot(player, biomeName) then
		-- That biome is full: fall back and say so honestly
		sanct.Biome = "Forest"
		claimPlot(player, "Forest")
		renderAll(player)
		push(player)
		return { Success = false, Error = biomeName .. " has no free plots on this server!" }
	end
	renderAll(player)
	push(player)
	Remotes.Notify:FireClient(player, {
		Text = "🏡 Sanctuary moved! " .. GameConfig.BiomeByName[biomeName].PerkText,
		Kind = "Travel",
	})
	return { Success = true }
end

-- ------------------------------------------------------------
-- Lifecycle
-- ------------------------------------------------------------

local function onPlayerAdded(player: Player)
	local data = DataService.waitForData(player, 15)
	if not data or player.Parent == nil then
		return
	end
	local sanct = sanctuaryOf(player)
	local wantedBiome = sanct.Biome or "Forest"
	-- Their saved biome may be full (or somehow locked after a wipe): degrade gracefully
	if not claimPlot(player, wantedBiome) then
		sanct.Biome = "Forest"
		claimPlot(player, "Forest")
	end
	renderAll(player)
	push(player)
end

function SanctuaryService.init()
	sanctuariesFolder = Instance.new("Folder")
	sanctuariesFolder.Name = "Sanctuaries"
	sanctuariesFolder.Parent = workspace

	Remotes.GetSanctuary.OnServerInvoke = function(player)
		return SanctuaryService.payload(player)
	end
	Remotes.PlaceObject.OnServerInvoke = onPlaceObject
	Remotes.MoveObject.OnServerInvoke = onMoveObject
	Remotes.DeleteObject.OnServerInvoke = onDeleteObject
	Remotes.PlacePet.OnServerInvoke = onPlacePet
	Remotes.UnplacePet.OnServerInvoke = onUnplacePet
	Remotes.RelocatePlot.OnServerInvoke = onRelocatePlot

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		releasePlot(player)
		lastActionAt[player] = nil
	end)
end

return SanctuaryService
