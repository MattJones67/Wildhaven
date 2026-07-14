--[[
	BaseUpgradeService — owns each player's base: claiming a village plot,
	the upgrade levels (functional AND aesthetic), and rebuilding the cabin
	whenever its look changes.

	All plots are built "Unclaimed" at server start so the village looks
	complete. When a player joins they claim the first free plot and their
	cabin rebuilds with THEIR saved tier/decor. Buying an aesthetic upgrade
	rebuilds it again on the spot — upgrades are visible, which is the fun.

	SECURITY: BuyUpgrade validates the key exists, a next level exists, and
	the SERVER-side balance can afford it. Rate-limited like every purchase.

	Other services read effects through the getters here (capacity, slots,
	hatch speed, income multiplier) so the config stays the single source.

	TODO (future slices): the free-build sanctuary replaces fixed plots, and
	RebirthService will reset upgrade levels — both plug in via this service.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Remotes)

local BaseBuilder = require(script.Parent.BaseBuilder)
local DataService = require(script.Parent.DataService)
local EquipService = require(script.Parent.EquipService)
local ForestGenerator = require(script.Parent.ForestGenerator)
local GoalService = require(script.Parent.GoalService)
local PlayerStats = require(script.Parent.PlayerStats)

local BaseUpgradeService = {}

type Claim = {
	PlotIndex: number,
	Model: Model?,
	PadPositions: { Vector3 },
}

local claims: { [Player]: Claim } = {}
local plotOwner: { [number]: Player } = {}
local unclaimedModels: { [number]: Model } = {}
local lastBuyAt: { [Player]: number } = {}
local basesFolder: Model

-- HatchService registers here so incubating eggs can follow their pads
-- when a cabin is rebuilt (avoids a circular require between the services).
local baseRebuiltCallback: ((Player) -> ())? = nil
function BaseUpgradeService.setBaseRebuiltCallback(callback: (Player) -> ())
	baseRebuiltCallback = callback
end

-- ------------------------------------------------------------
-- Upgrade getters (the rest of the game reads effects through these)
-- ------------------------------------------------------------

local function upgradeValue(player: Player, key: string): any
	local upgrade = GameConfig.UpgradeByKey[key]
	local data = DataService.get(player)
	local level = (data and data.Upgrades[key]) or 1
	return upgrade.Values[math.clamp(level, 1, #upgrade.Values)]
end

-- NOTE (slice 3): derived stats that stack with rebirth/index bonuses
-- (egg capacity, hatch speed, income, luck, equip slots) live in
-- PlayerStats now. Only plain per-key reads remain here.
function BaseUpgradeService.getHatchSlots(player: Player): number
	return upgradeValue(player, "HatchSlots")
end

function BaseUpgradeService.getPlotCFrame(player: Player): CFrame?
	local claim = claims[player]
	return claim and ForestGenerator.getCabinPlots()[claim.PlotIndex] or nil
end

function BaseUpgradeService.getPadPositions(player: Player): { Vector3 }
	local claim = claims[player]
	return claim and claim.PadPositions or {}
end

-- ------------------------------------------------------------
-- Building / rebuilding cabins
-- ------------------------------------------------------------

local function lookFor(player: Player?): BaseBuilder.BaseLook
	local data = player and DataService.get(player)
	if not data then
		return { Tier = 1, Slots = 2, Lanterns = false, Banner = false, FancyFirepit = false }
	end
	return {
		Tier = data.Upgrades.BaseTier or 1, -- tier IS the level (1..3)
		Slots = BaseUpgradeService.getHatchSlots(player :: Player),
		Lanterns = upgradeValue(player :: Player, "Lanterns") == true,
		Banner = upgradeValue(player :: Player, "Banner") == true,
		FancyFirepit = upgradeValue(player :: Player, "FancyFirepit") == true,
	}
end

local function rebuildPlot(plotIndex: number)
	local plotCFrame = ForestGenerator.getCabinPlots()[plotIndex]
	local owner = plotOwner[plotIndex]

	-- Tear down whatever stands there
	if unclaimedModels[plotIndex] then
		unclaimedModels[plotIndex]:Destroy()
		unclaimedModels[plotIndex] = nil
	end
	if owner and claims[owner] and claims[owner].Model then
		claims[owner].Model:Destroy()
	end

	local model, pads = BaseBuilder.build(basesFolder, plotCFrame, lookFor(owner), owner and owner.DisplayName or nil, plotIndex)
	if owner and claims[owner] then
		claims[owner].Model = model
		claims[owner].PadPositions = pads
		if baseRebuiltCallback then
			baseRebuiltCallback(owner) -- let HatchService re-seat incubating eggs
		end
	else
		unclaimedModels[plotIndex] = model
	end
end

function BaseUpgradeService.pushUpgrades(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	Remotes.UpgradesUpdate:FireClient(player, {
		Upgrades = data.Upgrades,
		EggCapacity = PlayerStats.getEggCapacity(player),
		HatchSlots = BaseUpgradeService.getHatchSlots(player),
		EquipSlots = PlayerStats.getEquipSlots(player),
	})
end

-- Rebuild everything that depends on upgrade levels (used after rebirth
-- resets them): cabin visuals, walk speed, and the client's upgrade UI.
function BaseUpgradeService.refresh(player: Player)
	local claim = claims[player]
	if claim then
		rebuildPlot(claim.PlotIndex)
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = upgradeValue(player, "WalkSpeed")
	end
	BaseUpgradeService.pushUpgrades(player)
end

-- ------------------------------------------------------------
-- The purchase remote
-- ------------------------------------------------------------

local function applyWalkSpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = upgradeValue(player, "WalkSpeed")
	end
end

local function onBuyUpgrade(player: Player, key: any)
	-- SECURITY CHECK 1: rate limit
	local now = os.clock()
	local last = lastBuyAt[player]
	if last and now - last < GameConfig.RateLimits.BuyCooldownSeconds then
		return { Success = false, Error = "Too fast!" }
	end
	lastBuyAt[player] = now

	-- SECURITY CHECK 2: well-formed request for a real upgrade
	if typeof(key) ~= "string" or not GameConfig.UpgradeByKey[key] then
		return { Success = false, Error = "Unknown upgrade" }
	end
	local upgrade = GameConfig.UpgradeByKey[key]

	local data = DataService.get(player)
	if not data then
		return { Success = false, Error = "Still loading..." }
	end

	local currentLevel = data.Upgrades[key] or 1
	local nextLevel = currentLevel + 1
	if nextLevel > #upgrade.Values then
		return { Success = false, Error = "Already maxed!" }
	end

	-- SECURITY CHECK 3: server-side affordability — patch 5 currency split:
	-- FUNCTIONAL upgrades cost SILVER (the grind), AESTHETIC cost GOLD (the flex)
	local cost = upgrade.Prices[nextLevel]
	if upgrade.Kind == "Aesthetic" then
		if data.Gold < cost then
			return { Success = false, Error = "Not enough gold! (Codes, quests & lucky blocks)" }
		end
		data.Gold -= cost
	else
		if data.Silver < cost then
			return { Success = false, Error = "Not enough silver!" }
		end
		data.Silver -= cost
	end
	data.Upgrades[key] = nextLevel

	-- Apply visible/functional side effects immediately
	if key == "WalkSpeed" then
		applyWalkSpeed(player)
	elseif key == "BaseTier" or key == "Lanterns" or key == "Banner" or key == "FancyFirepit" or key == "HatchSlots" then
		local claim = claims[player]
		if claim then
			rebuildPlot(claim.PlotIndex)
		end
	elseif key == "EquipSlots" then
		EquipService.pushEquipped(player) -- the equip UI shows the new slot count
	end
	-- (EggCapacity and IncomeBoost need no world change — PlayerStats sees
	-- the new level instantly; the next income tick reflects it.)

	GoalService.bump(player, "UpgradesBought")
	BaseUpgradeService.pushUpgrades(player)
	return { Success = true, Silver = math.floor(data.Silver), Gold = data.Gold }
end

-- ------------------------------------------------------------
-- Lifecycle: claim on join, release on leave
-- ------------------------------------------------------------

local function onPlayerAdded(player: Player)
	local data = DataService.waitForData(player, 15)
	if not data or player.Parent == nil then
		return
	end

	-- Claim the first free plot. If the village is somehow full (more
	-- players than cabins), the player just has no base this session —
	-- they can still explore and collect. TODO: dynamic overflow plots.
	local plots = ForestGenerator.getCabinPlots()
	for index = 1, #plots do
		if not plotOwner[index] then
			plotOwner[index] = player
			claims[player] = { PlotIndex = index, Model = nil, PadPositions = {} }
			rebuildPlot(index)
			break
		end
	end
	if not claims[player] then
		Remotes.Notify:FireClient(player, { Text = "Village is full — no free cabin!", Kind = "Error" })
	end

	BaseUpgradeService.pushUpgrades(player)
	player.CharacterAdded:Connect(function()
		task.wait(0.1) -- let the Humanoid finish spawning
		applyWalkSpeed(player)
	end)
	applyWalkSpeed(player)
end

function BaseUpgradeService.init()
	basesFolder = Instance.new("Model")
	basesFolder.Name = "Bases"
	basesFolder.Parent = workspace

	-- Build every plot as "Unclaimed" so the village starts complete
	for index = 1, #ForestGenerator.getCabinPlots() do
		rebuildPlot(index)
	end

	Remotes.BuyUpgrade.OnServerInvoke = onBuyUpgrade

	Players.PlayerAdded:Connect(function(player)
		task.spawn(onPlayerAdded, player)
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastBuyAt[player] = nil
		local claim = claims[player]
		if claim then
			claims[player] = nil
			plotOwner[claim.PlotIndex] = nil
			rebuildPlot(claim.PlotIndex) -- back to "Unclaimed"
		end
	end)
end

return BaseUpgradeService
