--[[
	GameConfig — the single source of truth for EVERY tunable number in Wildhaven.

	Game logic never hard-codes a price, weight, or chance. If you want to
	rebalance the economy or reshape the island, change values HERE and only here.

	Slice 2 additions: egg types + per-egg pet pools, the SIZE modifier axis,
	forest generation parameters, world egg spawning, and base upgrades.
]]

local GameConfig = {}

-- ============================================================
-- ECONOMY
-- ============================================================
GameConfig.Economy = {
	StartingCoins = 50, -- coins a brand-new player begins with
	-- World eggs are FREE to collect; coins now fund base upgrades.
}

GameConfig.LuckBoost = {
	Cost = 100, -- coins to buy one Luck Boost
	Multiplier = 2, -- effective luck while the boost is active (1 = normal)
	DurationSeconds = 120, -- how long the boost lasts
	-- Luck improves: rarer pets from egg pools, mutation odds, AND size odds.
}

GameConfig.Income = {
	TickSeconds = 1, -- how often the server pays out passive income
}

-- ============================================================
-- ANTI-SPAM (server-side rate limits; client mirrors these)
-- ============================================================
GameConfig.RateLimits = {
	CollectCooldownSeconds = 0.4, -- min seconds between egg pickups per player
	StartHatchCooldownSeconds = 0.5, -- min seconds between hatch-slot deposits
	BuyCooldownSeconds = 0.5, -- min seconds between shop/upgrade purchases
}

-- ============================================================
-- RARITIES (unchanged from slice 1)
-- LuckPower: adjustedWeight = baseWeight * luck ^ LuckPower — rarer tiers
-- benefit more from luck; Common (power 0) is never boosted.
-- ============================================================
GameConfig.Rarities = {
	{ Name = "Common", Order = 1, LuckPower = 0, Color = Color3.fromRGB(235, 235, 235) },
	{ Name = "Uncommon", Order = 2, LuckPower = 0.25, Color = Color3.fromRGB(88, 205, 100) },
	{ Name = "Rare", Order = 3, LuckPower = 0.5, Color = Color3.fromRGB(70, 130, 255) },
	{ Name = "Epic", Order = 4, LuckPower = 0.75, Color = Color3.fromRGB(170, 80, 255) },
	{ Name = "Legendary", Order = 5, LuckPower = 1, Color = Color3.fromRGB(255, 195, 40) },
	{ Name = "Mythic", Order = 6, LuckPower = 1.25, Color = Color3.fromRGB(255, 65, 65) },
}

GameConfig.RarityByName = {}
for _, rarity in GameConfig.Rarities do
	GameConfig.RarityByName[rarity.Name] = rarity
end

-- ============================================================
-- PET ROSTER (12 forest pets across the full ladder)
-- IncomePerSecond = coins/sec BEFORE mutation and size multipliers.
--
-- RETUNED for slice 3: income now comes ONLY from EQUIPPED pets (2 slots
-- at the start), so each pet earns roughly 2.5x its old rate — two
-- Commons still feel rewarding in the first minutes.
-- ============================================================
GameConfig.Animals = {
	{ Name = "Squirrel", Rarity = "Common", IncomePerSecond = 2 },
	{ Name = "Bunny", Rarity = "Common", IncomePerSecond = 3 },
	{ Name = "Raccoon", Rarity = "Uncommon", IncomePerSecond = 8 },
	{ Name = "Hedgehog", Rarity = "Uncommon", IncomePerSecond = 10 },
	{ Name = "Fox", Rarity = "Rare", IncomePerSecond = 25 },
	{ Name = "Boar", Rarity = "Rare", IncomePerSecond = 35 },
	{ Name = "Wolf", Rarity = "Epic", IncomePerSecond = 90 },
	{ Name = "Fawn", Rarity = "Epic", IncomePerSecond = 120 },
	{ Name = "Bear", Rarity = "Legendary", IncomePerSecond = 280 },
	{ Name = "Owl", Rarity = "Legendary", IncomePerSecond = 360 },
	{ Name = "Golden Stag", Rarity = "Mythic", IncomePerSecond = 1000 },
	{ Name = "Spirit Lynx", Rarity = "Mythic", IncomePerSecond = 1500 },
}

GameConfig.AnimalByName = {}
for _, animal in GameConfig.Animals do
	GameConfig.AnimalByName[animal.Name] = animal
end

-- ============================================================
-- EGG TYPES
-- SpawnWeight  = ticket count when the world picks which egg to spawn.
-- GlowIntensity = how hard the egg glows/shimmers in the world (1 = subtle).
-- HatchSeconds = base incubation time (reduced by the HatchSpeed upgrade).
-- Pool         = weighted pet pool for THIS egg (rarer eggs bias rarer pets).
--                Pool weights are luck-adjusted by each pet's rarity LuckPower.
-- ============================================================
GameConfig.Eggs = {
	{
		Name = "Forest Egg",
		SpawnWeight = 60,
		Color = Color3.fromRGB(170, 210, 130),
		GlowIntensity = 0.6,
		HatchSeconds = 15,
		Announce = false,
		Pool = {
			{ Pet = "Squirrel", Weight = 44 },
			{ Pet = "Bunny", Weight = 34 },
			{ Pet = "Raccoon", Weight = 11 },
			{ Pet = "Hedgehog", Weight = 8 },
			{ Pet = "Fox", Weight = 2.5 },
			{ Pet = "Boar", Weight = 0.5 },
		},
	},
	{
		Name = "Mossy Egg",
		SpawnWeight = 27,
		Color = Color3.fromRGB(95, 150, 85),
		GlowIntensity = 1.2,
		HatchSeconds = 40,
		Announce = false,
		Pool = {
			{ Pet = "Raccoon", Weight = 28 },
			{ Pet = "Hedgehog", Weight = 28 },
			{ Pet = "Fox", Weight = 21 },
			{ Pet = "Boar", Weight = 14 },
			{ Pet = "Wolf", Weight = 5 },
			{ Pet = "Fawn", Weight = 3.5 },
			{ Pet = "Bear", Weight = 0.5 },
		},
	},
	{
		Name = "Ancient Egg",
		SpawnWeight = 10,
		Color = Color3.fromRGB(200, 170, 110),
		GlowIntensity = 2.2,
		HatchSeconds = 90,
		Announce = false,
		Pool = {
			{ Pet = "Fox", Weight = 24 },
			{ Pet = "Boar", Weight = 20 },
			{ Pet = "Wolf", Weight = 22 },
			{ Pet = "Fawn", Weight = 18 },
			{ Pet = "Bear", Weight = 8 },
			{ Pet = "Owl", Weight = 6 },
			{ Pet = "Golden Stag", Weight = 1.5 },
			{ Pet = "Spirit Lynx", Weight = 0.5 },
		},
	},
	{
		Name = "Mythic Egg",
		SpawnWeight = 1.3, -- very rare world event
		Color = Color3.fromRGB(210, 90, 255),
		GlowIntensity = 4,
		HatchSeconds = 180,
		Announce = true, -- server-wide banner + sound when one spawns
		Pool = {
			{ Pet = "Wolf", Weight = 25 },
			{ Pet = "Fawn", Weight = 20 },
			{ Pet = "Bear", Weight = 24 },
			{ Pet = "Owl", Weight = 18 },
			{ Pet = "Golden Stag", Weight = 9 },
			{ Pet = "Spirit Lynx", Weight = 4 },
		},
	},
}

GameConfig.EggByName = {}
for _, egg in GameConfig.Eggs do
	GameConfig.EggByName[egg.Name] = egg
end

-- ============================================================
-- WORLD EGG SPAWNING
-- ============================================================
GameConfig.EggSpawning = {
	MaxWorldEggs = 12, -- concurrent eggs on the island
	SpawnIntervalSeconds = 5, -- how often the server tries to fill an empty slot
	PickupMaxDistance = 12, -- SECURITY: server rejects pickups from further away
}

GameConfig.Hatchery = {
	MaxStartDistance = 45, -- SECURITY: how close to your base you must be to deposit an egg
}

-- ============================================================
-- MUTATIONS (unchanged; rolled independently of pet AND size)
-- Listed rarest-first; effectiveChance = Chance * luck.
-- ============================================================
GameConfig.Mutations = {
	{ Name = "Rainbow", Multiplier = 8, Chance = 0.004, SpectacleOrder = 6 },
	{ Name = "Golden", Multiplier = 3, Chance = 0.025, SpectacleOrder = 4 },
	{ Name = "Shiny", Multiplier = 1.5, Chance = 0.08, SpectacleOrder = 3 },
}

GameConfig.MutationByName = {}
for _, mutation in GameConfig.Mutations do
	GameConfig.MutationByName[mutation.Name] = mutation
end

-- ============================================================
-- SIZES (new axis — stacks independently of mutations, so a pet can be
-- a "Giant Rainbow Fox"). Rolled rarest-first like mutations; luck helps.
-- Scale visibly resizes the model; Multiplier applies to income.
-- ============================================================
GameConfig.Sizes = {
	{ Name = "Giant", Scale = 2, Multiplier = 5, Chance = 0.015, SpectacleOrder = 5 },
	{ Name = "Big", Scale = 1.4, Multiplier = 2, Chance = 0.10, SpectacleOrder = 3 },
	-- "Normal" (scale 1, x1) is the remainder — no table entry needed.
}

GameConfig.SizeByName = {}
for _, size in GameConfig.Sizes do
	GameConfig.SizeByName[size.Name] = size
end

-- ============================================================
-- BASE UPGRADES
-- Each upgrade is an array of levels: Values[i] is the effect at level i,
-- Prices[i] is what it costs to REACH level i (level 1 is free/default).
-- Functional upgrades change numbers; Aesthetic ones visibly change your base.
-- ============================================================
GameConfig.BaseUpgrades = {
	{
		Key = "HatchSpeed",
		Title = "Warm Nest",
		Kind = "Functional",
		Describe = "Hatch time x%s", -- shown in UI with the value
		Values = { 1, 0.8, 0.65, 0.5, 0.35 }, -- multiplier on egg HatchSeconds
		Prices = { 0, 250, 1000, 5000, 25000 },
	},
	{
		Key = "HatchSlots",
		Title = "Hatch Slots",
		Kind = "Functional",
		Describe = "%s eggs hatch at once",
		Values = { 2, 3, 4, 5, 6 }, -- number of parallel hatchery slots
		Prices = { 0, 400, 2000, 10000, 50000 },
	},
	{
		Key = "EggCapacity",
		Title = "Egg Satchel",
		Kind = "Functional",
		Describe = "Carry %s eggs",
		Values = { 3, 5, 7, 10, 15 }, -- egg inventory capacity
		Prices = { 0, 150, 600, 3000, 15000 },
	},
	{
		Key = "IncomeBoost",
		Title = "Pet Care",
		Kind = "Functional",
		Describe = "Income x%s",
		Values = { 1, 1.25, 1.5, 2, 3 }, -- multiplier on ALL pet income
		Prices = { 0, 500, 2500, 12000, 60000 },
	},
	{
		Key = "WalkSpeed",
		Title = "Trail Boots",
		Kind = "Functional",
		Describe = "Speed %s",
		Values = { 16, 18, 21, 24, 28 }, -- Humanoid.WalkSpeed
		Prices = { 0, 200, 800, 4000, 20000 },
	},
	{
		Key = "EquipSlots",
		Title = "Pet Team",
		Kind = "Functional",
		Describe = "%s equip slots",
		Values = { 2, 3, 4, 5 }, -- equipped-pet slots (rebirth unlocks add MORE on top)
		Prices = { 0, 2500, 20000, 100000 },
	},
	{
		Key = "BaseTier",
		Title = "Home",
		Kind = "Aesthetic",
		Describe = "%s",
		Values = { "Starter Cabin", "Cozy Cabin", "Grand Treehouse Annex" },
		Prices = { 0, 1500, 20000 },
	},
	{
		Key = "Lanterns",
		Title = "Lantern Set",
		Kind = "Aesthetic",
		Describe = "Glowing lanterns at your base",
		Values = { false, true }, -- simple owned/not-owned unlock
		Prices = { 0, 300 },
	},
	{
		Key = "Banner",
		Title = "House Banner",
		Kind = "Aesthetic",
		Describe = "A proud banner on your cabin",
		Values = { false, true },
		Prices = { 0, 750 },
	},
	{
		Key = "FancyFirepit",
		Title = "Fancy Firepit",
		Kind = "Aesthetic",
		Describe = "A cozy firepit by your door",
		Values = { false, true },
		Prices = { 0, 2000 },
	},
}

GameConfig.UpgradeByKey = {}
for _, upgrade in GameConfig.BaseUpgrades do
	GameConfig.UpgradeByKey[upgrade.Key] = upgrade
end

-- ============================================================
-- EQUIPPED PET FOLLOWING (client visuals only — pure charm numbers)
-- ============================================================
GameConfig.Equip = {
	FollowRadius = 4.5, -- how far behind the character pets hover
	FollowHeight = 1.6, -- hover height off the ground
	FollowScale = 0.8, -- pets shrink a little while following (before Size scale)
	BobAmount = 0.3, -- vertical bob while idle
	LerpSpeed = 6, -- how snappily pets chase their follow spot
}

-- ============================================================
-- REBIRTH — the long-term spine. Rebirth resets coins + ALL base upgrade
-- levels, in exchange for PERMANENT stacking multipliers and unlocks.
-- Pets, eggs, discoveries, and running hatches are KEPT.
--
-- Requirement: lifetime TotalEarned >= RequirementBase * RequirementGrowth^n
-- (n = rebirths done so far): 25k, 100k, 400k, 1.6M, ...
-- ============================================================
GameConfig.Rebirth = {
	RequirementBase = 25000,
	RequirementGrowth = 4,

	-- Permanent per-rebirth gains (all stack linearly/multiplicatively):
	IncomePerRebirth = 0.5, -- +50% income each rebirth (multiplier = 1 + 0.5n)
	LuckPerRebirth = 0.25, -- +25% luck each rebirth
	HatchSpeedPerRebirth = 0.05, -- hatches 5% faster per rebirth (compounding)
	HatchSpeedFloor = 0.25, -- hatch time can never drop below 25% of base
	CapacityPerRebirth = 2, -- +2 egg satchel capacity each rebirth

	-- Tangible unlock ladder (rebirth number -> what it unlocks).
	-- "EquipSlot" adds +1 equip slot on top of the Pet Team upgrade.
	Unlocks = {
		{ Rebirth = 1, Type = "EquipSlot", Label = "+1 Equip Slot" },
		{ Rebirth = 2, Type = "AutoHatch", Label = "🤖 AUTO-HATCH unlocked!" },
		{ Rebirth = 3, Type = "EquipSlot", Label = "+1 Equip Slot" },
		{ Rebirth = 5, Type = "EquipSlot", Label = "+1 Equip Slot" },
	},
}

-- ============================================================
-- COLLECTION INDEX — discover every pet. Completing a rarity's full set
-- grants a PERMANENT bonus (computed live from the discovered list).
-- Bonus values are fractions: Income = 0.1 means +10% income forever.
-- ============================================================
GameConfig.IndexRewards = {
	{ Rarity = "Common", Bonus = { Income = 0.1 }, Label = "Common set: +10% income" },
	{ Rarity = "Uncommon", Bonus = { Luck = 0.1 }, Label = "Uncommon set: +10% luck" },
	{ Rarity = "Rare", Bonus = { Income = 0.15 }, Label = "Rare set: +15% income" },
	{ Rarity = "Epic", Bonus = { Luck = 0.15 }, Label = "Epic set: +15% luck" },
	{ Rarity = "Legendary", Bonus = { Income = 0.25 }, Label = "Legendary set: +25% income" },
	{ Rarity = "Mythic", Bonus = { Income = 0.5, Luck = 0.25 }, Label = "Mythic set: +50% income, +25% luck" },
}

-- ============================================================
-- DAILY LOGIN REWARDS — escalate through the streak, then repeat day 7.
-- Missing more than DailyGraceSeconds resets the streak to day 1.
-- ============================================================
GameConfig.Daily = {
	CooldownSeconds = 24 * 3600, -- one claim per 24h (server-timestamped)
	GraceSeconds = 48 * 3600, -- come back within 48h or the streak resets
	Rewards = {
		{ Type = "Coins", Amount = 100, Label = "100 🪙" },
		{ Type = "Coins", Amount = 250, Label = "250 🪙" },
		{ Type = "LuckBoost", Label = "Free 🍀 Luck Boost" },
		{ Type = "Coins", Amount = 750, Label = "750 🪙" },
		{ Type = "Egg", EggType = "Mossy Egg", Label = "A Mossy Egg 🥚" },
		{ Type = "Coins", Amount = 2000, Label = "2,000 🪙" },
		{ Type = "Egg", EggType = "Ancient Egg", Label = "An Ancient Egg 🥚✨" },
	},
}

-- ============================================================
-- OFFLINE INCOME — equipped pets keep earning while you're away
-- (at a reduced rate, capped) so coming back always feels good.
-- ============================================================
GameConfig.Offline = {
	MinAwaySeconds = 300, -- ignore absences under 5 minutes
	MaxSeconds = 8 * 3600, -- earn for at most 8 hours away
	RateMultiplier = 0.5, -- offline earnings run at 50% of live rate
}

-- ============================================================
-- AUTO-HATCH (unlocked at rebirth 2) — eggs from the satchel flow into
-- free hatch slots automatically, from anywhere on the island.
-- ============================================================
GameConfig.AutoHatch = {
	IntervalSeconds = 2, -- how often the server tries to auto-fill slots
}

-- ============================================================
-- GOAL LADDER — the HUD always shows your next objective. Completing one
-- grants coins and reveals the next. Stats are tracked server-side.
-- Stat keys: EggsCollected, HatchCount, EquippedCount, IncomePerSec,
--            DiscoveredCount, BestRarityOrder, UpgradesBought, Rebirths
-- ============================================================
GameConfig.Goals = {
	{ Text = "Collect an egg", Stat = "EggsCollected", Target = 1, Reward = 50 },
	{ Text = "Hatch an egg", Stat = "HatchCount", Target = 1, Reward = 100 },
	{ Text = "Equip 2 pets", Stat = "EquippedCount", Target = 2, Reward = 150 },
	{ Text = "Discover 4 pets", Stat = "DiscoveredCount", Target = 4, Reward = 250 },
	{ Text = "Reach 50 🪙/s", Stat = "IncomePerSec", Target = 50, Reward = 400 },
	{ Text = "Hatch a Rare or better", Stat = "BestRarityOrder", Target = 3, Reward = 750 },
	{ Text = "Buy a base upgrade", Stat = "UpgradesBought", Target = 1, Reward = 500 },
	{ Text = "Discover 8 pets", Stat = "DiscoveredCount", Target = 8, Reward = 1500 },
	{ Text = "Reach 500 🪙/s", Stat = "IncomePerSec", Target = 500, Reward = 2500 },
	{ Text = "Rebirth once", Stat = "Rebirths", Target = 1, Reward = 5000 },
	{ Text = "Discover all 12 pets", Stat = "DiscoveredCount", Target = 12, Reward = 10000 },
	{ Text = "Reach 5,000 🪙/s", Stat = "IncomePerSec", Target = 5000, Reward = 25000 },
}

-- ============================================================
-- WORLD EGG VISIBILITY — world eggs are big, floating, glowing beacons
-- ============================================================
GameConfig.WorldEggVisual = {
	Scale = 1.9, -- world eggs are nearly 2x the hatchery egg size
	FloatHeight = 1.6, -- they hover this far off the ground
	BeamHeight = 16, -- the vertical light column above each egg
	HaloHeight = 4.6, -- the spinning rarity ring floats this high
}

-- TODO (future slices): free-build sanctuary zones plug in here as new
-- config tables — see init.server for the service hooks.

-- ============================================================
-- FOREST GENERATION
-- Everything the ForestGenerator uses. Same Seed = identical island, so
-- tweak numbers freely and regenerate to compare.
-- Landmark positions are plain constants — nudge them without touching logic.
-- ============================================================
GameConfig.Forest = {
	Seed = 1337,
	IslandRadius = 130, -- grass island size (studs)
	BeachRadius = 145, -- sand ring just past the grass

	-- Landmarks (hand-curated positions; y is always ground = 0)
	VillageCenter = Vector3.new(0, 0, 0),
	VillageRadius = 30, -- cabins ring around the campfire
	CabinCount = 8, -- player plots per server
	TreehousePosition = Vector3.new(0, 0, -75),
	PondCenter = Vector3.new(68, 0, 48),
	PondRadius = 17,

	-- River: flows from the north shore down into the pond (XZ waypoints)
	RiverPoints = { Vector2.new(42, -140), Vector2.new(36, -85), Vector2.new(40, -30), Vector2.new(48, 10), Vector2.new(62, 40) },
	RiverWidth = 7,
	BridgePositions = { Vector3.new(47, 0, 6), Vector3.new(38, 0, -55) }, -- plank bridges over the river

	-- Dirt paths between landmarks (XZ polylines; carved into the terrain)
	Paths = {
		{ Vector2.new(0, 12), Vector2.new(0, -40), Vector2.new(0, -68) }, -- village -> treehouse
		{ Vector2.new(10, 6), Vector2.new(30, 16), Vector2.new(56, 34) }, -- village -> pond dock
		{ Vector2.new(-10, 4), Vector2.new(-38, -14), Vector2.new(-62, -30) }, -- village -> west clearing
		{ Vector2.new(12, -70), Vector2.new(38, -58), Vector2.new(56, -46) }, -- treehouse -> east clearing
	},
	PathWidth = 5,

	-- Clearings: kept free of trees; prime egg-spawn real estate
	Clearings = {
		Vector3.new(-62, 0, -30),
		Vector3.new(56, 0, -46),
		Vector3.new(-48, 0, 55),
		Vector3.new(22, 0, 85),
		Vector3.new(-85, 0, 8),
	},
	ClearingRadius = 16,

	-- Tree copses (clustered, not evenly sprinkled)
	TreeClusterCount = 9,
	TreesPerClusterMin = 5,
	TreesPerClusterMax = 11,
	TreeClusterRadius = 16,

	-- Scattered small detail
	RockCount = 22,
	BushCount = 30,
	FernCount = 36,
	MushroomCount = 24,
	FallenLogCount = 7,
	TallGrassCount = 60,
	FireflyPatchCount = 6,
}

-- ============================================================
-- HATCH REVEAL TIMINGS (the juice — tune to taste)
-- ============================================================
GameConfig.Reveal = {
	WobbleAngles = { 8, 14, 22 }, -- degrees; each wobble hits harder
	WobbleTimes = { 0.36, 0.3, 0.24 }, -- seconds per wobble; each one faster
	SuspensePause = 0.45, -- beat of stillness before the pop
	PopTime = 0.12, -- egg scale-punch duration
	SpringInTime = 0.2, -- animal squash-and-stretch overshoot
	SettleTime = 0.16, -- overshoot settling back to normal size
	NameShowSeconds = 2.4, -- how long the animal + name stay on display
	BeamMinOrder = 3, -- Rare (order 3) and up get the light beam
	BigEventMinOrder = 5, -- Legendary (5) and up: flash, shake, banner, confetti
	SlowMoBeatSeconds = 0.35, -- dramatic hold on Legendary+ reveals
	CameraShakeSeconds = 0.6,
	CameraShakeIntensity = 0.35, -- degrees of jitter at full strength
}

return GameConfig
