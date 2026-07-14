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
-- PATCH 5: TWO CURRENCIES.
-- SILVER = the everyday grind currency: earned from pets, spent on
--          functional upgrades and shop potions. (Old "coins" migrate here.)
-- GOLD   = rare & premium: earned ONLY from codes, quests (small amounts),
--          and Lucky Blocks. Spent on class re-rolls, base cosmetics, and
--          the Wandering Trader.
-- TODO(monetisation): buying Gold with Robux plugs into DataService.grantGold
-- via a MarketplaceService ProcessReceipt in a future patch. NOT now.
GameConfig.Economy = {
	StartingSilver = 50, -- silver a brand-new player begins with
	StartingGold = 0, -- gold is earned, never given
}

-- ============================================================
-- POTIONS (patch 5 — replaces the old x2 Luck Boost button).
-- Consumables that grant TIMED buffs. Kind = which stat they buff:
--   Luck  -> multiplies effective luck (rare/mutation/size odds)
--   Hatch -> multiplies hatch TIME (0.75 = 25% faster)
-- SilverCost = shop price (nil = not sold in the shop; trader/blocks only).
-- Stacking rule: ONE active buff per Kind — activating a second of the
-- same kind while one runs is rejected (simple and readable).
-- ============================================================
GameConfig.Potions = {
	{ Key = "MinorLuck", Title = "Minor Luck Potion", Emoji = "🍀", Kind = "Luck", Mult = 1.5, DurationSeconds = 240, SilverCost = 400, Color = Color3.fromRGB(110, 220, 120) },
	{ Key = "MajorLuck", Title = "Major Luck Potion", Emoji = "🍀", Kind = "Luck", Mult = 2.25, DurationSeconds = 360, SilverCost = nil, Color = Color3.fromRGB(60, 255, 140) },
	{ Key = "MinorHatch", Title = "Minor Hatch Potion", Emoji = "⚡", Kind = "Hatch", Mult = 0.75, DurationSeconds = 240, SilverCost = 400, Color = Color3.fromRGB(255, 200, 90) },
	{ Key = "MajorHatch", Title = "Major Hatch Potion", Emoji = "⚡", Kind = "Hatch", Mult = 0.5, DurationSeconds = 360, SilverCost = nil, Color = Color3.fromRGB(255, 160, 60) },
}

GameConfig.PotionByKey = {}
for _, potion in GameConfig.Potions do
	GameConfig.PotionByKey[potion.Key] = potion
end

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
-- Biome = home biome: drives egg pools, the sanctuary matched-habitat
-- bonus, and quest requirements.
GameConfig.Animals = {
	-- FOREST (the original 12)
	{ Name = "Squirrel", Rarity = "Common", IncomePerSecond = 2, Biome = "Forest" },
	{ Name = "Bunny", Rarity = "Common", IncomePerSecond = 3, Biome = "Forest" },
	{ Name = "Raccoon", Rarity = "Uncommon", IncomePerSecond = 8, Biome = "Forest" },
	{ Name = "Hedgehog", Rarity = "Uncommon", IncomePerSecond = 10, Biome = "Forest" },
	{ Name = "Fox", Rarity = "Rare", IncomePerSecond = 25, Biome = "Forest" },
	{ Name = "Boar", Rarity = "Rare", IncomePerSecond = 35, Biome = "Forest" },
	{ Name = "Wolf", Rarity = "Epic", IncomePerSecond = 90, Biome = "Forest" },
	{ Name = "Fawn", Rarity = "Epic", IncomePerSecond = 120, Biome = "Forest" },
	{ Name = "Bear", Rarity = "Legendary", IncomePerSecond = 280, Biome = "Forest" },
	{ Name = "Owl", Rarity = "Legendary", IncomePerSecond = 360, Biome = "Forest" },
	{ Name = "Golden Stag", Rarity = "Mythic", IncomePerSecond = 1000, Biome = "Forest" },
	{ Name = "Spirit Lynx", Rarity = "Mythic", IncomePerSecond = 1500, Biome = "Forest" },
	-- DESERT (patch 4) — slightly richer than Forest, it's an unlock
	{ Name = "Meerkat", Rarity = "Common", IncomePerSecond = 2.5, Biome = "Desert" },
	{ Name = "Fennec Fox", Rarity = "Uncommon", IncomePerSecond = 9, Biome = "Desert" },
	{ Name = "Scorpion", Rarity = "Rare", IncomePerSecond = 28, Biome = "Desert" },
	{ Name = "Camel", Rarity = "Epic", IncomePerSecond = 100, Biome = "Desert" },
	{ Name = "Sand Serpent", Rarity = "Legendary", IncomePerSecond = 300, Biome = "Desert" },
	{ Name = "Golden Scarab", Rarity = "Mythic", IncomePerSecond = 1200, Biome = "Desert" },
	-- TUNDRA
	{ Name = "Arctic Hare", Rarity = "Common", IncomePerSecond = 3, Biome = "Tundra" },
	{ Name = "Penguin", Rarity = "Uncommon", IncomePerSecond = 11, Biome = "Tundra" },
	{ Name = "Snow Fox", Rarity = "Rare", IncomePerSecond = 30, Biome = "Tundra" },
	{ Name = "Polar Bear", Rarity = "Epic", IncomePerSecond = 110, Biome = "Tundra" },
	{ Name = "Frost Wolf", Rarity = "Legendary", IncomePerSecond = 330, Biome = "Tundra" },
	{ Name = "Ancient Mammoth", Rarity = "Mythic", IncomePerSecond = 1300, Biome = "Tundra" },
	-- VOLCANIC
	{ Name = "Ember Lizard", Rarity = "Common", IncomePerSecond = 3.5, Biome = "Volcanic" },
	{ Name = "Magma Crab", Rarity = "Uncommon", IncomePerSecond = 12, Biome = "Volcanic" },
	{ Name = "Ash Hound", Rarity = "Rare", IncomePerSecond = 34, Biome = "Volcanic" },
	{ Name = "Lava Golem", Rarity = "Epic", IncomePerSecond = 125, Biome = "Volcanic" },
	{ Name = "Phoenix Chick", Rarity = "Legendary", IncomePerSecond = 380, Biome = "Volcanic" },
	{ Name = "Inferno Drake", Rarity = "Mythic", IncomePerSecond = 1500, Biome = "Volcanic" },
	-- SKY ISLES
	{ Name = "Cloud Bunny", Rarity = "Common", IncomePerSecond = 4, Biome = "Sky" },
	{ Name = "Sky Sparrow", Rarity = "Uncommon", IncomePerSecond = 14, Biome = "Sky" },
	{ Name = "Griffin Cub", Rarity = "Rare", IncomePerSecond = 38, Biome = "Sky" },
	{ Name = "Pegasus Foal", Rarity = "Epic", IncomePerSecond = 140, Biome = "Sky" },
	{ Name = "Storm Eagle", Rarity = "Legendary", IncomePerSecond = 420, Biome = "Sky" },
	{ Name = "Celestial Roc", Rarity = "Mythic", IncomePerSecond = 1800, Biome = "Sky" },
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
	-- PATCH 4: one signature egg per new biome, full rarity ladder inside.
	-- (SpawnWeight only competes within the SAME biome's egg list.)
	{
		Name = "Sand Egg",
		SpawnWeight = 100,
		Color = Color3.fromRGB(235, 205, 140),
		GlowIntensity = 1.5,
		HatchSeconds = 35,
		Announce = false,
		Pool = {
			{ Pet = "Meerkat", Weight = 40 },
			{ Pet = "Fennec Fox", Weight = 28 },
			{ Pet = "Scorpion", Weight = 16 },
			{ Pet = "Camel", Weight = 10 },
			{ Pet = "Sand Serpent", Weight = 4.5 },
			{ Pet = "Golden Scarab", Weight = 1.5 },
		},
	},
	{
		Name = "Frost Egg",
		SpawnWeight = 100,
		Color = Color3.fromRGB(175, 220, 245),
		GlowIntensity = 1.5,
		HatchSeconds = 45,
		Announce = false,
		Pool = {
			{ Pet = "Arctic Hare", Weight = 40 },
			{ Pet = "Penguin", Weight = 28 },
			{ Pet = "Snow Fox", Weight = 16 },
			{ Pet = "Polar Bear", Weight = 10 },
			{ Pet = "Frost Wolf", Weight = 4.5 },
			{ Pet = "Ancient Mammoth", Weight = 1.5 },
		},
	},
	{
		Name = "Ember Egg",
		SpawnWeight = 100,
		Color = Color3.fromRGB(240, 120, 70),
		GlowIntensity = 2,
		HatchSeconds = 60,
		Announce = false,
		Pool = {
			{ Pet = "Ember Lizard", Weight = 40 },
			{ Pet = "Magma Crab", Weight = 28 },
			{ Pet = "Ash Hound", Weight = 16 },
			{ Pet = "Lava Golem", Weight = 10 },
			{ Pet = "Phoenix Chick", Weight = 4.5 },
			{ Pet = "Inferno Drake", Weight = 1.5 },
		},
	},
	{
		Name = "Sky Egg",
		SpawnWeight = 100,
		Color = Color3.fromRGB(200, 225, 255),
		GlowIntensity = 2.2,
		HatchSeconds = 75,
		Announce = false,
		Pool = {
			{ Pet = "Cloud Bunny", Weight = 40 },
			{ Pet = "Sky Sparrow", Weight = 28 },
			{ Pet = "Griffin Cub", Weight = 16 },
			{ Pet = "Pegasus Foal", Weight = 10 },
			{ Pet = "Storm Eagle", Weight = 4.5 },
			{ Pet = "Celestial Roc", Weight = 1.5 },
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
	-- (Per-biome egg caps live on each entry in GameConfig.Biomes.)
	SpawnIntervalSeconds = 5, -- how often the server tries to fill empty slots
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
		Key = "SanctuarySize",
		Title = "Sanctuary Deed",
		Kind = "Functional",
		Describe = "%s build objects",
		Values = { 20, 30, 45, 60 }, -- max placed sanctuary objects (performance cap)
		Prices = { 0, 1000, 10000, 50000 },
	},
	{
		Key = "SanctuaryPets",
		Title = "Habitat Care",
		Kind = "Functional",
		Describe = "%s placed pets",
		Values = { 4, 6, 8, 12 }, -- pets placeable into sanctuary habitats
		Prices = { 0, 2000, 15000, 80000 },
	},
	-- PATCH 5: Aesthetic (Kind = "Aesthetic") upgrades now cost GOLD —
	-- cosmetics are the flex economy; functional upgrades stay Silver.
	{
		Key = "BaseTier",
		Title = "Home",
		Kind = "Aesthetic",
		Describe = "%s",
		Values = { "Starter Cabin", "Cozy Cabin", "Grand Treehouse Annex" },
		Prices = { 0, 12, 35 }, -- GOLD
	},
	{
		Key = "Lanterns",
		Title = "Lantern Set",
		Kind = "Aesthetic",
		Describe = "Glowing lanterns at your base",
		Values = { false, true }, -- simple owned/not-owned unlock
		Prices = { 0, 3 }, -- GOLD
	},
	{
		Key = "Banner",
		Title = "House Banner",
		Kind = "Aesthetic",
		Describe = "A proud banner on your cabin",
		Values = { false, true },
		Prices = { 0, 5 }, -- GOLD
	},
	{
		Key = "FancyFirepit",
		Title = "Fancy Firepit",
		Kind = "Aesthetic",
		Describe = "A cozy firepit by your door",
		Values = { false, true },
		Prices = { 0, 8 }, -- GOLD
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
		{ Type = "Silver", Amount = 100, Label = "100 🪙" },
		{ Type = "Silver", Amount = 250, Label = "250 🪙" },
		{ Type = "Potion", Key = "MinorLuck", Label = "🍀 Minor Luck Potion" },
		{ Type = "Silver", Amount = 750, Label = "750 🪙" },
		{ Type = "Egg", EggType = "Mossy Egg", Label = "A Mossy Egg 🥚" },
		{ Type = "Silver", Amount = 2000, Label = "2,000 🪙" },
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

-- ============================================================
-- BIOMES (patch 4). Each is its own island. The PLOT PERK applies to a
-- player GLOBALLY while their sanctuary sits in that biome — choosing
-- where to live is a strategic decision (luck vs income vs hatch speed).
--
-- Gate: what unlocks travel. Checked live against saved stats, so no
-- extra save field is needed: { Rebirths = n } and/or { TotalEarned = n }.
-- Perk multipliers: Income/Luck multiply; HatchSpeed multiplies hatch
-- TIME (0.9 = 10% faster).
-- ============================================================
-- PATCH 4 REWORK: the land biomes are one CONNECTED continent — you can
-- walk Forest -> Desert/Tundra/Volcanic (Sky Isles stay floating; travel
-- crystal only). Radius = terrain footprint; regions overlap and blend.
-- WallRadius = the translucent gate wall ring around locked biomes.
-- PlotPositions = ABSOLUTE sanctuary plot spots (Lumber-Tycoon style,
-- scattered so a full server has room); Y is the plot's ground height —
-- TerrainForge flattens the land under each one. Nudge freely.
GameConfig.Biomes = {
	{
		Name = "Forest",
		Center = Vector3.new(0, 0, 0),
		Radius = 260,
		Color = Color3.fromRGB(95, 170, 90),
		Emoji = "🌲",
		Gate = {}, -- always open
		GateText = "Open to everyone",
		Perk = { HatchSpeed = 0.9 },
		PerkText = "Plot perk: 10% faster hatches",
		Eggs = { "Forest Egg", "Mossy Egg", "Ancient Egg", "Mythic Egg" },
		MaxWorldEggs = 12,
		PlotPositions = {
			Vector3.new(175, 0, 55), Vector3.new(175, 0, -55),
			Vector3.new(-175, 0, 55), Vector3.new(-175, 0, -55),
			Vector3.new(55, 0, 175), Vector3.new(-55, 0, 175),
		},
	},
	{
		Name = "Desert",
		Center = Vector3.new(480, 0, 0),
		Radius = 260,
		WallRadius = 250,
		Color = Color3.fromRGB(230, 195, 120),
		Emoji = "🏜️",
		Gate = { TotalEarned = 10000 },
		GateText = "Earn 10,000 lifetime 🪙",
		Perk = { Income = 1.2 },
		PerkText = "Plot perk: +20% income",
		Eggs = { "Sand Egg" },
		MaxWorldEggs = 8,
		PlotPositions = {
			Vector3.new(640, 4, 0), Vector3.new(480, 4, 160),
			Vector3.new(480, 4, -160), Vector3.new(590, 4, 115),
			Vector3.new(590, 4, -115), Vector3.new(370, 4, 130),
		},
	},
	{
		Name = "Tundra",
		Center = Vector3.new(-480, 0, 0),
		Radius = 260,
		WallRadius = 250,
		Color = Color3.fromRGB(190, 225, 240),
		Emoji = "❄️",
		Gate = { Rebirths = 1 },
		GateText = "Reach Rebirth 1",
		Perk = { Luck = 1.2 },
		PerkText = "Plot perk: +20% luck",
		Eggs = { "Frost Egg" },
		MaxWorldEggs = 8,
		PlotPositions = {
			Vector3.new(-640, 10, 0), Vector3.new(-480, 10, 160),
			Vector3.new(-480, 10, -160), Vector3.new(-590, 10, 115),
			Vector3.new(-590, 10, -115), Vector3.new(-370, 10, 130),
		},
	},
	{
		Name = "Volcanic",
		Center = Vector3.new(0, 0, 480),
		Radius = 240,
		WallRadius = 235,
		Color = Color3.fromRGB(215, 95, 60),
		Emoji = "🌋",
		Gate = { Rebirths = 2 },
		GateText = "Reach Rebirth 2",
		Perk = { Income = 1.6 },
		PerkText = "Plot perk: +60% income",
		Eggs = { "Ember Egg" },
		MaxWorldEggs = 8,
		PlotPositions = {
			Vector3.new(150, 6, 480), Vector3.new(-150, 6, 480),
			Vector3.new(115, 6, 615), Vector3.new(-115, 6, 615),
		},
	},
	{
		Name = "Sky",
		Center = Vector3.new(0, 150, -650), -- floating; NOT part of the continent
		Radius = 60,
		Color = Color3.fromRGB(180, 205, 255),
		Emoji = "☁️",
		Gate = { Rebirths = 3 },
		GateText = "Reach Rebirth 3",
		-- (The pitch says "faster XP" but there is no XP system yet, so the
		-- celestial perk is luck+income until leveling exists.)
		Perk = { Luck = 1.15, Income = 1.15 },
		PerkText = "Plot perk: +15% luck AND +15% income",
		Eggs = { "Sky Egg" },
		MaxWorldEggs = 6,
		PlotPositions = {
			Vector3.new(20, 150, -668), Vector3.new(-20, 150, -632),
		},
	},
}

GameConfig.BiomeByName = {}
for _, biome in GameConfig.Biomes do
	GameConfig.BiomeByName[biome.Name] = biome
end

-- ============================================================
-- FREE-BUILD SANCTUARY (patch 4). The player's own decorated plot in a
-- chosen biome. Placed pets earn income ON TOP of equipped pets.
-- ============================================================
GameConfig.Sanctuary = {
	PlotHalfSize = 26, -- placements valid within ±this many studs of plot center
	-- (Plot LOCATIONS live on each biome's PlotPositions list above.)
	GridSnap = 2, -- placement snaps to this grid (0 = free placement)
	HabitatCapacity = 2, -- pets one enclosure can hold
	MatchedHabitatBonus = 1.25, -- pet income x this when habitat biome matches pet
	ThemeBonus = { MinSameBiomeObjects = 4, Mult = 1.1 }, -- cohesive-theme reward
	MoveRateLimit = 0.2, -- min seconds between build actions (anti-spam)
}

-- The placement palette. Habitats have a Biome (drives the matched bonus);
-- terrain/decor with a Biome count toward the theme bonus for that biome.
GameConfig.SanctuaryObjects = {
	-- Terrain
	{ Key = "GrassTile", Title = "Grass Patch", Category = "Terrain", Biome = "Forest" },
	{ Key = "SandTile", Title = "Sand Patch", Category = "Terrain", Biome = "Desert" },
	{ Key = "SnowTile", Title = "Snow Patch", Category = "Terrain", Biome = "Tundra" },
	{ Key = "PathTile", Title = "Stone Path", Category = "Terrain" },
	{ Key = "WaterTile", Title = "Pond Tile", Category = "Terrain" },
	{ Key = "Hill", Title = "Small Hill", Category = "Terrain" },
	-- Habitats (one per biome)
	{ Key = "ForestPen", Title = "Forest Pen", Category = "Habitat", Biome = "Forest" },
	{ Key = "DesertPen", Title = "Desert Pen", Category = "Habitat", Biome = "Desert" },
	{ Key = "TundraPen", Title = "Tundra Pen", Category = "Habitat", Biome = "Tundra" },
	{ Key = "VolcanicPen", Title = "Volcanic Pen", Category = "Habitat", Biome = "Volcanic" },
	{ Key = "SkyPen", Title = "Sky Pen", Category = "Habitat", Biome = "Sky" },
	-- Decor
	{ Key = "TreeProp", Title = "Tree", Category = "Decor", Biome = "Forest" },
	{ Key = "CactusProp", Title = "Cactus", Category = "Decor", Biome = "Desert" },
	{ Key = "IceSpike", Title = "Ice Spike", Category = "Decor", Biome = "Tundra" },
	{ Key = "EmberRock", Title = "Ember Rock", Category = "Decor", Biome = "Volcanic" },
	{ Key = "CloudPuff", Title = "Cloud Puff", Category = "Decor", Biome = "Sky" },
	{ Key = "RockProp", Title = "Boulder", Category = "Decor" },
	{ Key = "Fence", Title = "Fence", Category = "Decor" },
	{ Key = "Bench", Title = "Bench", Category = "Decor" },
	{ Key = "LanternProp", Title = "Lantern", Category = "Decor" },
	{ Key = "SignProp", Title = "Sign", Category = "Decor" },
	{ Key = "Arch", Title = "Arch", Category = "Decor" },
	-- PATCH 5: trader-exclusive decor — must be UNLOCKED (bought with gold
	-- from the Wandering Trader) before it appears placeable.
	{ Key = "GoldenStatue", Title = "Golden Stag Statue", Category = "Decor", Exclusive = true },
	{ Key = "StarLantern", Title = "Star Lantern", Category = "Decor", Exclusive = true },
}

GameConfig.SanctuaryObjectByKey = {}
for _, object in GameConfig.SanctuaryObjects do
	GameConfig.SanctuaryObjectByKey[object.Key] = object
end

-- ============================================================
-- CLASSES (patch 4). Rolled rarity-weighted; perks are marginal
-- multipliers (meaningful, not game-breaking). MutationChance multiplies
-- mutation odds on top of luck.
-- First roll is FREE, one free roll every 24h, extra re-rolls cost coins.
-- TODO(monetisation): paid Robux re-roll hooks into ClassService later.
-- ============================================================
GameConfig.Classes = {
	List = {
		{ Name = "Forager", Weight = 26, Tier = "Common", Color = Color3.fromRGB(180, 210, 150), Perks = { Income = 1.05 }, Blurb = "+5% income" },
		{ Name = "Swift", Weight = 26, Tier = "Common", Color = Color3.fromRGB(160, 200, 230), Perks = { HatchSpeed = 0.95 }, Blurb = "5% faster hatches" },
		{ Name = "Lucky", Weight = 24, Tier = "Common", Color = Color3.fromRGB(150, 220, 160), Perks = { Luck = 1.05 }, Blurb = "+5% luck" },
		{ Name = "Merchant", Weight = 8, Tier = "Rare", Color = Color3.fromRGB(255, 205, 100), Perks = { Income = 1.12 }, Blurb = "+12% income" },
		{ Name = "Tempest", Weight = 7, Tier = "Rare", Color = Color3.fromRGB(140, 170, 255), Perks = { HatchSpeed = 0.9, Income = 1.05 }, Blurb = "10% faster hatches, +5% income" },
		{ Name = "Fortune", Weight = 7, Tier = "Rare", Color = Color3.fromRGB(120, 230, 190), Perks = { Luck = 1.12 }, Blurb = "+12% luck" },
		{ Name = "Angel", Weight = 1, Tier = "Chase", Color = Color3.fromRGB(255, 250, 200), Perks = { Luck = 1.25, HatchSpeed = 0.85 }, Blurb = "+25% luck, 15% faster hatches ✨" },
		{ Name = "Demon", Weight = 1, Tier = "Chase", Color = Color3.fromRGB(255, 90, 90), Perks = { Income = 1.25, MutationChance = 1.1 }, Blurb = "+25% income, +10% mutation odds 🔥" },
	},
	RerollCostGold = 8, -- GOLD for an extra roll beyond the free daily (patch 5)
	FreeRollCooldownSeconds = 24 * 3600,
}

GameConfig.ClassByName = {}
for _, class in GameConfig.Classes.List do
	GameConfig.ClassByName[class.Name] = class
end

-- ============================================================
-- GUIDE NPC QUESTS (patch 4). One-time CHAIN per biome (in order) plus a
-- repeatable DAILY per biome. Types:
--   CollectEgg  — pick up Count eggs of type Param (progress counted live)
--   HatchPet    — hatch Count pets from biome Param at rarity >= MinRarity
-- Rewards can COMBINE fields (patch 5): Silver / Gold (small amounts — a
-- primary premium source!) / Potion (key) / ClassToken / Pet (name).
-- TODO(later patch): "Discover the hidden ruins" secret-area quests hook
-- in here as a third type once secret areas exist.
-- ============================================================
GameConfig.Quests = {
	Chains = {
		Forest = {
			{ Id = "forest1", Text = "Collect 3 Forest Eggs", Type = "CollectEgg", Param = "Forest Egg", Count = 3, Reward = { Silver = 200 } },
			{ Id = "forest2", Text = "Hatch an Uncommon or better", Type = "HatchPet", Param = "Any", MinRarity = 2, Count = 1, Reward = { Potion = "MinorLuck" } },
			{ Id = "forest3", Text = "Collect 2 Mossy Eggs", Type = "CollectEgg", Param = "Mossy Egg", Count = 2, Reward = { Silver = 500, Gold = 1 } },
		},
		Desert = {
			{ Id = "desert1", Text = "Collect 3 Sand Eggs", Type = "CollectEgg", Param = "Sand Egg", Count = 3, Reward = { Silver = 400 } },
			{ Id = "desert2", Text = "Hatch a Desert Rare or better", Type = "HatchPet", Param = "Desert", MinRarity = 3, Count = 1, Reward = { ClassToken = 1 } },
			{ Id = "desert3", Text = "Collect 5 Sand Eggs", Type = "CollectEgg", Param = "Sand Egg", Count = 5, Reward = { Pet = "Fennec Fox", Gold = 2 } },
		},
		Tundra = {
			{ Id = "tundra1", Text = "Collect 3 Frost Eggs", Type = "CollectEgg", Param = "Frost Egg", Count = 3, Reward = { Silver = 800 } },
			{ Id = "tundra2", Text = "Hatch a Tundra Rare or better", Type = "HatchPet", Param = "Tundra", MinRarity = 3, Count = 1, Reward = { Potion = "MinorLuck" } },
			{ Id = "tundra3", Text = "Collect 5 Frost Eggs", Type = "CollectEgg", Param = "Frost Egg", Count = 5, Reward = { Silver = 2000, Gold = 2 } },
		},
		Volcanic = {
			{ Id = "volcanic1", Text = "Collect 3 Ember Eggs", Type = "CollectEgg", Param = "Ember Egg", Count = 3, Reward = { Silver = 1500 } },
			{ Id = "volcanic2", Text = "Hatch a Volcanic Epic or better", Type = "HatchPet", Param = "Volcanic", MinRarity = 4, Count = 1, Reward = { ClassToken = 1 } },
			{ Id = "volcanic3", Text = "Collect 5 Ember Eggs", Type = "CollectEgg", Param = "Ember Egg", Count = 5, Reward = { Silver = 5000, Gold = 3 } },
		},
		Sky = {
			{ Id = "sky1", Text = "Collect 3 Sky Eggs", Type = "CollectEgg", Param = "Sky Egg", Count = 3, Reward = { Silver = 3000 } },
			{ Id = "sky2", Text = "Hatch a Sky Epic or better", Type = "HatchPet", Param = "Sky", MinRarity = 4, Count = 1, Reward = { Potion = "MinorLuck" } },
			{ Id = "sky3", Text = "Collect 5 Sky Eggs", Type = "CollectEgg", Param = "Sky Egg", Count = 5, Reward = { Pet = "Griffin Cub", Gold = 3 } },
		},
	},
	-- Repeatable dailies (per biome, 24h cooldown after turn-in)
	Dailies = {
		Forest = { Id = "dailyForest", Text = "Daily: Collect 2 Forest Eggs", Type = "CollectEgg", Param = "Forest Egg", Count = 2, Reward = { Silver = 300 } },
		Desert = { Id = "dailyDesert", Text = "Daily: Collect 2 Sand Eggs", Type = "CollectEgg", Param = "Sand Egg", Count = 2, Reward = { Silver =600 } },
		Tundra = { Id = "dailyTundra", Text = "Daily: Collect 2 Frost Eggs", Type = "CollectEgg", Param = "Frost Egg", Count = 2, Reward = { Silver = 1200 } },
		Volcanic = { Id = "dailyVolcanic", Text = "Daily: Collect 2 Ember Eggs", Type = "CollectEgg", Param = "Ember Egg", Count = 2, Reward = { Silver = 2400 } },
		Sky = { Id = "dailySky", Text = "Daily: Collect 2 Sky Eggs", Type = "CollectEgg", Param = "Sky Egg", Count = 2, Reward = { Silver = 4000 } },
	},
	DailyCooldownSeconds = 24 * 3600,
}

-- NPC guides: one per biome, positioned by the biome generators.
GameConfig.Guides = {
	Forest = { Name = "Willow", Greeting = "Welcome to the forest, friend! The eggs practically fall from the trees here." },
	Desert = { Name = "Dune", Greeting = "Ah, a traveler! The sands hide treasures... and the occasional scorpion." },
	Tundra = { Name = "Aurora", Greeting = "Bundle up! The rarest pets love the cold, you know." },
	Volcanic = { Name = "Cinder", Greeting = "Careful where you step! The heat here breeds LEGENDS." },
	Sky = { Name = "Zephyr", Greeting = "You made it up here! The clouds are full of wonders." },
}

-- ============================================================
-- CODES (patch 5) — one-time-per-player redemptions; a primary GOLD
-- source and a marketing lever (drop new codes with updates/socials).
-- Rewards use the same multi-field shape as quests.
-- Remove a code from this table to expire it everywhere at once.
-- ============================================================
GameConfig.Codes = {
	WILDHAVEN = { Gold = 5 },
	LAUNCHDAY = { Silver = 2500 },
	LUCKYME = { Potion = "MinorLuck", Count = 2 },
	GOLDRUSH = { Gold = 3, Silver = 500 },
}

-- ============================================================
-- LUCKY BLOCKS (patch 5) — random world drops everyone can race to.
-- ============================================================
GameConfig.LuckyBlocks = {
	SpawnIntervalSeconds = 180, -- how often the server ROLLS for a spawn
	SpawnChance = 0.55, -- chance each roll actually drops a block
	DespawnSeconds = 120, -- unopened blocks vanish after this
	GoldenChance = 0.12, -- chance a drop is the GOLDEN variant
	FallHeight = 90, -- how high above the ground the block appears
	FallSeconds = 2.2, -- the suspenseful descent
	OpenMaxDistance = 12, -- SECURITY: server-checked claim distance
	-- Weighted reward tables (same multi-field rewards as quests)
	Rewards = {
		{ Weight = 30, Reward = { Silver = 1500 }, Label = "1,500 🪙" },
		{ Weight = 25, Reward = { Potion = "MinorLuck" }, Label = "🍀 Minor Luck Potion" },
		{ Weight = 20, Reward = { Potion = "MinorHatch" }, Label = "⚡ Minor Hatch Potion" },
		{ Weight = 15, Reward = { Gold = 2 }, Label = "2 🌕 Gold!" },
		{ Weight = 10, Reward = { Egg = "Ancient Egg" }, Label = "An Ancient Egg! 🥚✨" },
	},
	GoldenRewards = {
		{ Weight = 30, Reward = { Gold = 5 }, Label = "5 🌕 Gold!" },
		{ Weight = 25, Reward = { Potion = "MajorLuck" }, Label = "🍀 MAJOR Luck Potion!" },
		{ Weight = 20, Reward = { Potion = "MajorHatch" }, Label = "⚡ MAJOR Hatch Potion!" },
		{ Weight = 15, Reward = { Egg = "Mythic Egg" }, Label = "A MYTHIC EGG?! 🥚🌈" },
		{ Weight = 10, Reward = { Gold = 10, Silver = 2500 }, Label = "The jackpot! 10 🌕 + 2,500 🪙" },
	},
}

-- ============================================================
-- WANDERING TRADER (patch 5) — a roaming GOLD vendor with limited,
-- rotating stock and a departure timer for urgency.
-- ============================================================
GameConfig.Trader = {
	SpawnIntervalSeconds = 420, -- how often he TRIES to appear somewhere
	SpawnChance = 0.65,
	DwellSeconds = 180, -- how long he stays per visit
	StockPerVisit = 3, -- how many different items he carries each visit
	BuyMaxDistance = 14, -- SECURITY: must actually be at his stall
	Name = "Barnaby",
	Lines = {
		"Psst — rare goods, fair prices. Well... prices.",
		"Everything here fell off the back of a sky-wagon. Probably.",
		"Gold only, friend. Silver jingles too loud on the road.",
		"Buy quick! The road calls and she is IMPATIENT.",
	},
	-- The stock pool; each visit draws StockPerVisit of these at random.
	-- Qty = how many can be sold PER VISIT (first come first served).
	Stock = {
		{ Key = "MajorLuckPotion", Title = "Major Luck Potion", Gold = 5, Qty = 2, Reward = { Potion = "MajorLuck" } },
		{ Key = "MajorHatchPotion", Title = "Major Hatch Potion", Gold = 5, Qty = 2, Reward = { Potion = "MajorHatch" } },
		{ Key = "AncientEgg", Title = "Ancient Egg", Gold = 8, Qty = 2, Reward = { Egg = "Ancient Egg" } },
		{ Key = "MythicEgg", Title = "Mythic Egg", Gold = 22, Qty = 1, Reward = { Egg = "Mythic Egg" } },
		{ Key = "GoldenStatue", Title = "Golden Stag Statue (decor)", Gold = 15, Qty = 1, Reward = { Decor = "GoldenStatue" } },
		{ Key = "StarLantern", Title = "Star Lantern (decor)", Gold = 10, Qty = 1, Reward = { Decor = "StarLantern" } },
	},
}

-- TODO (future patch): visiting other players' sanctuaries (social hooks).
-- TODO (patch 6): trade tokens + the trading system.

-- ============================================================
-- FOREST GENERATION
-- Everything the ForestGenerator uses. Same Seed = identical island, so
-- tweak numbers freely and regenerate to compare.
-- Landmark positions are plain constants — nudge them without touching logic.
-- ============================================================
GameConfig.Forest = {
	Seed = 1337,
	IslandRadius = 220, -- how far forest flora/scatter spreads from the village

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

	-- Tree copses (clustered, not evenly sprinkled) — denser since the
	-- continent rework made the forest much bigger
	TreeClusterCount = 16,
	TreesPerClusterMin = 5,
	TreesPerClusterMax = 12,
	TreeClusterRadius = 18,

	-- Scattered small detail
	RockCount = 34,
	BushCount = 46,
	FernCount = 52,
	MushroomCount = 34,
	FallenLogCount = 10,
	TallGrassCount = 90,
	FireflyPatchCount = 9,
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
