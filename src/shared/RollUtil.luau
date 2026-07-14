--[[
	RollUtil — pure math for every random roll: which pet comes out of an
	egg's pool, the independent mutation roll, the independent SIZE roll,
	and income totals.

	"Pure" means: no game state, no side effects. Pass luck in, get a result
	out. The optional Random object makes results reproducible for testing.

	Only the SERVER acts on these results — the client may use this module
	for display math only (e.g. showing odds), never outcomes.
]]

local GameConfig = require(script.Parent.GameConfig)

local RollUtil = {}

export type CollectionEntry = { Species: string, Mutation: string, Size: string? }

-- Luck-adjusted weight for one pool entry: rarer pets benefit more from luck.
-- Formula (documented in GameConfig): weight * luck ^ rarity.LuckPower
local function adjustedPoolWeight(entry: { Pet: string, Weight: number }, luck: number): number
	local animal = GameConfig.AnimalByName[entry.Pet]
	local rarity = GameConfig.RarityByName[animal.Rarity]
	return entry.Weight * luck ^ rarity.LuckPower
end

-- Weighted raffle over ONE egg type's pet pool. Every pet gets tickets
-- equal to its (luck-adjusted) weight; we draw one ticket.
function RollUtil.rollPetFromEgg(eggName: string, luck: number, rng: Random?): string
	local egg = GameConfig.EggByName[eggName]
	assert(egg, "Unknown egg type: " .. tostring(eggName))
	local random = rng or Random.new()

	local totalWeight = 0
	for _, entry in egg.Pool do
		totalWeight += adjustedPoolWeight(entry, luck)
	end

	local ticket = random:NextNumber() * totalWeight
	local runningTotal = 0
	for _, entry in egg.Pool do
		runningTotal += adjustedPoolWeight(entry, luck)
		if ticket <= runningTotal then
			return entry.Pet
		end
	end
	return egg.Pool[#egg.Pool].Pet -- float rounding edge case: rarest wins
end

-- Which egg type should spawn next, from a specific list (each biome has
-- its own egg list — see GameConfig.Biomes)? Luck does NOT apply here:
-- world spawns are the same for everyone; luck helps what's INSIDE.
function RollUtil.rollEggTypeFrom(eggNames: { string }, rng: Random?): string
	local random = rng or Random.new()
	local totalWeight = 0
	for _, name in eggNames do
		totalWeight += GameConfig.EggByName[name].SpawnWeight
	end
	local ticket = random:NextNumber() * totalWeight
	local runningTotal = 0
	for _, name in eggNames do
		runningTotal += GameConfig.EggByName[name].SpawnWeight
		if ticket <= runningTotal then
			return name
		end
	end
	return eggNames[#eggNames]
end

-- Independent mutation roll, rarest-first. Returns "None" for no mutation.
-- Luck scales each chance linearly: effectiveChance = Chance * luck.
function RollUtil.rollMutation(luck: number, rng: Random?): string
	local random = rng or Random.new()
	local roll = random:NextNumber()
	local cumulative = 0
	for _, mutation in GameConfig.Mutations do
		cumulative += math.min(mutation.Chance * luck, 1)
		if roll < cumulative then
			return mutation.Name
		end
	end
	return "None"
end

-- Independent SIZE roll, same shape as mutations. Returns "Normal" usually.
function RollUtil.rollSize(luck: number, rng: Random?): string
	local random = rng or Random.new()
	local roll = random:NextNumber()
	local cumulative = 0
	for _, size in GameConfig.Sizes do
		cumulative += math.min(size.Chance * luck, 1)
		if roll < cumulative then
			return size.Name
		end
	end
	return "Normal"
end

-- Income for one collection entry: base * mutation * size.
-- Entries saved before slice 2 have no Size field — treated as "Normal".
function RollUtil.incomeForEntry(entry: CollectionEntry): number
	local animal = GameConfig.AnimalByName[entry.Species]
	if not animal then
		return 0 -- unknown species in saved data; ignore rather than error
	end
	local total = animal.IncomePerSecond
	local mutation = GameConfig.MutationByName[entry.Mutation]
	if mutation then
		total *= mutation.Multiplier
	end
	local size = GameConfig.SizeByName[entry.Size or "Normal"]
	if size then
		total *= size.Multiplier
	end
	return total
end

-- Raw coins/sec for a whole collection (BEFORE the IncomeBoost upgrade —
-- IncomeService applies that on top).
function RollUtil.incomePerSecond(collection: { CollectionEntry }): number
	local total = 0
	for _, entry in collection do
		total += RollUtil.incomeForEntry(entry)
	end
	return total
end

return RollUtil
