--[[
	DataService — owns every player's saved data for the whole session.

	Responsibilities:
	  * Load data from DataStore when a player joins (with retries + pcall)
	  * Keep a fast in-memory "session cache" that gameplay services mutate
	  * Autosave periodically, save on leave, and save on server shutdown
	  * FAIL SAFE: if loading errors, the player gets default data for this
	    session but we REFUSE to save over their real data (CanSave = false)

	The rest of the game talks only to this module's getters — nothing else
	touches DataStores. That makes swapping to ProfileService later a
	one-file change: reimplement load/save here, keep the same public API.

	Data shape (per player):
	  {
	    Coins = 50,                    -- can be fractional internally; UI floors it
	    Collection = {                 -- every pet ever hatched
	      { Species = "Fox", Mutation = "None", Size = "Giant" },
	      { Species = "Bunny", Mutation = "Golden" },  -- pre-slice-2: no Size = "Normal"
	    },
	    LuckEndsAt = 0,                -- os.time() epoch when the luck boost expires
	    EggInventory = { "Forest Egg", "Mossy Egg" },  -- carried eggs (capacity-limited)
	    Hatches = {                    -- in-progress hatchery slots (survive rejoins)
	      { Slot = 1, EggType = "Forest Egg", EndsAt = 1786000000 },
	    },
	    Upgrades = { HatchSpeed = 1, HatchSlots = 1, ... }, -- level per upgrade key
	  }

	MIGRATION: loads from before slice 2 are reconciled — any missing field
	gets its default, existing fields (coins, collection) pass through
	untouched, so no save is ever broken by an update.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)

local STORE_NAME = "WildhavenPlayerData_v1" -- bump the suffix to wipe/migrate data
local AUTOSAVE_SECONDS = 60
local LOAD_RETRIES = 3

export type CollectionEntry = { Species: string, Mutation: string, Size: string?, Id: number? }
export type Hatch = { Slot: number, EggType: string, EndsAt: number }
export type PlayerData = {
	Coins: number,
	Collection: { CollectionEntry },
	LuckEndsAt: number,
	EggInventory: { string },
	Hatches: { Hatch },
	Upgrades: { [string]: number },
	-- slice 3:
	NextPetId: number, -- id counter so equips can reference exact pets
	Equipped: { number }, -- pet Ids currently equipped (income comes from these)
	Rebirths: number,
	TotalEarned: number, -- lifetime coins earned (rebirth requirement)
	Discovered: { [string]: boolean }, -- species seen at least once (the dex)
	LastDailyClaimAt: number, -- os.time() of last daily reward
	DailyStreak: number,
	AutoHatch: boolean, -- player's auto-hatch toggle (works once unlocked)
	GoalIndex: number, -- which goal in GameConfig.Goals is active (1-based)
	Stats: { [string]: number }, -- goal counters (EggsCollected, HatchCount, ...)
	LastSeenAt: number, -- stamped on every save; drives offline income
}

type Session = {
	Data: PlayerData,
	CanSave: boolean, -- false if load failed; protects real data from being overwritten
}

local DataService = {}

local store: DataStore? = nil
local sessions: { [Player]: Session } = {}

local function defaultUpgrades(): { [string]: number }
	local upgrades = {}
	for _, upgrade in GameConfig.BaseUpgrades do
		upgrades[upgrade.Key] = 1 -- every upgrade starts at level 1 (the free default)
	end
	return upgrades
end

local function defaultData(): PlayerData
	return {
		Coins = GameConfig.Economy.StartingCoins,
		Collection = {},
		LuckEndsAt = 0,
		EggInventory = {},
		Hatches = {},
		Upgrades = defaultUpgrades(),
		NextPetId = 1,
		Equipped = {},
		Rebirths = 0,
		TotalEarned = 0,
		Discovered = {},
		LastDailyClaimAt = 0,
		DailyStreak = 0,
		AutoHatch = false,
		GoalIndex = 1,
		Stats = {},
		LastSeenAt = 0,
		-- patch 4:
		Sanctuary = { Biome = "Forest", PlotIndex = 0, Objects = {}, PlacedPets = {} },
		Class = "", -- empty until the first class roll
		ClassTokens = 0, -- free class rolls earned from quests
		LastClassRollAt = 0, -- os.time() of last FREE roll (24h cooldown)
		Quests = { Progress = {}, Completed = {}, DailyDoneAt = {} },
	}
end

-- MIGRATION SAFETY: fill any missing field with its default so saves from
-- older versions of the game load cleanly. Existing values pass through.
local function reconcile(data: { [string]: any }): PlayerData
	local defaults = defaultData()
	for key, value in defaults :: any do
		if data[key] == nil then
			data[key] = value
		end
	end
	-- New upgrade keys added in future updates get level 1 automatically
	for key, level in defaults.Upgrades do
		if data.Upgrades[key] == nil then
			data.Upgrades[key] = level
		end
	end
	-- MIGRATION (slice 3): give every existing pet a unique Id so equips
	-- can reference exact pets, and back-fill the dex from old collections.
	for _, entry in data.Collection do
		if entry.Id == nil then
			entry.Id = data.NextPetId
			data.NextPetId += 1
		end
		data.Discovered[entry.Species] = true
	end
	return data :: PlayerData
end

local function keyFor(player: Player): string
	return "player_" .. player.UserId
end

-- ------------------------------------------------------------
-- Load / save internals (every DataStore call is wrapped in pcall)
-- ------------------------------------------------------------

local function loadData(player: Player): (PlayerData?, boolean)
	if not store then
		return nil, false -- DataStores unavailable (e.g. Studio without API access)
	end
	for attempt = 1, LOAD_RETRIES do
		local ok, result = pcall(function()
			return store:GetAsync(keyFor(player))
		end)
		if ok then
			-- nil result = brand-new player; that's a successful load
			return result :: PlayerData?, true
		end
		warn(("[DataService] load attempt %d/%d failed for %s: %s"):format(attempt, LOAD_RETRIES, player.Name, tostring(result)))
		task.wait(attempt) -- back off a little more each retry
	end
	return nil, false
end

local function saveData(player: Player, session: Session)
	if not store then
		return
	end
	if not session.CanSave then
		-- SECURITY/SAFETY: their real save failed to load. Writing now would
		-- overwrite good data with this session's defaults. Never do that.
		warn(("[DataService] skipping save for %s (load failed earlier)"):format(player.Name))
		return
	end
	session.Data.LastSeenAt = os.time() -- offline income measures from here
	local ok, err = pcall(function()
		store:SetAsync(keyFor(player), session.Data)
	end)
	if not ok then
		warn(("[DataService] save failed for %s: %s"):format(player.Name, tostring(err)))
	end
end

-- ------------------------------------------------------------
-- Public API used by the other services
-- ------------------------------------------------------------

-- The live session data, or nil if the player hasn't finished loading.
function DataService.get(player: Player): PlayerData?
	local session = sessions[player]
	return session and session.Data or nil
end

-- Yields until the player's data is loaded (or the timeout passes).
-- Used by remotes that might fire before the join flow finishes.
function DataService.waitForData(player: Player, timeoutSeconds: number): PlayerData?
	local deadline = os.clock() + timeoutSeconds
	while os.clock() < deadline do
		local data = DataService.get(player)
		if data then
			return data
		end
		if player.Parent == nil then
			return nil -- player left while we were waiting
		end
		task.wait(0.1)
	end
	return nil
end

-- Current effective luck for rolls: boosted while the timed boost is active.
function DataService.getLuckMultiplier(player: Player): number
	local data = DataService.get(player)
	if data and os.time() < data.LuckEndsAt then
		return GameConfig.LuckBoost.Multiplier
	end
	return 1
end

function DataService.getLuckSecondsLeft(player: Player): number
	local data = DataService.get(player)
	if not data then
		return 0
	end
	return math.max(0, data.LuckEndsAt - os.time())
end

-- Grant coins the RIGHT way: every gain also counts toward TotalEarned,
-- which is what gates rebirth. (Spending goes through data.Coins directly.)
function DataService.grantCoins(player: Player, amount: number)
	local data = DataService.get(player)
	if data and amount > 0 then
		data.Coins += amount
		data.TotalEarned += amount
	end
end

-- Iterate all loaded players (used by IncomeService's tick).
function DataService.getAllLoaded(): { [Player]: PlayerData }
	local result = {}
	for player, session in sessions do
		result[player] = session.Data
	end
	return result
end

-- ------------------------------------------------------------
-- Lifecycle
-- ------------------------------------------------------------

local function onPlayerAdded(player: Player)
	local saved, loadedOk = loadData(player)
	if player.Parent == nil then
		return -- left during the (possibly slow) load
	end
	sessions[player] = {
		Data = if saved then reconcile(saved) else defaultData(),
		CanSave = loadedOk,
	}
	if not loadedOk then
		warn(("[DataService] %s is playing on TEMPORARY data this session"):format(player.Name))
	end
end

local function onPlayerRemoving(player: Player)
	local session = sessions[player]
	if session then
		sessions[player] = nil
		saveData(player, session)
	end
end

function DataService.init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[DataService] DataStores unavailable — running with in-memory data only: " .. tostring(result))
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player) -- players who joined before init
	end
	Players.PlayerRemoving:Connect(onPlayerRemoving)

	-- Periodic autosave so a server crash loses at most ~1 minute of progress.
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE_SECONDS)
			for player, session in sessions do
				task.spawn(saveData, player, session)
			end
		end
	end)

	-- Last-chance save when the server shuts down.
	game:BindToClose(function()
		for player, session in sessions do
			saveData(player, session)
		end
	end)
end

return DataService
