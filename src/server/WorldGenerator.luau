--[[
	WorldGenerator — the region-based orchestrator for the whole island
	(the ForestGenerator refactor the world-expansion patch asked for).

	Regions are defined as data in GameConfig.Biomes (Center / Radius /
	GateRadius / PlotPositions — all hand-tunable constants); build order:

	  1. TerrainForge.build()    — the continent heightmap: every region's
	                               ground, border-mountain ridges + passes,
	                               volcano, coasts (chunked, yields)
	  2. ForestGenerator.build() — the Forest region: village hub, river,
	                               paths, flora (region builders own their
	                               own decoration)
	  3. BiomeGenerator.build()  — the other regions' decoration, sanctuary
	                               pads, pass gates, travel hubs, guides,
	                               and the PERSISTENT LOD silhouettes

	Later region checkpoints (2A-2E) extend the per-region builders —
	caves, temples, secret areas — WITHOUT touching this orchestration.

	Services keep using BiomeGenerator for world lookups (egg points,
	arrivals, plots, prompts); this module just owns the build sequence.
]]

local BiomeGenerator = require(script.Parent.BiomeGenerator)
local ForestGenerator = require(script.Parent.ForestGenerator)
local TerrainForge = require(script.Parent.TerrainForge)

local WorldGenerator = {}

function WorldGenerator.build()
	local startedAt = os.clock()
	TerrainForge.build()
	print(("[Wildhaven] Terrain forged in %.1fs"):format(os.clock() - startedAt))
	ForestGenerator.build()
	BiomeGenerator.build()
	print(("[Wildhaven] World built in %.1fs total"):format(os.clock() - startedAt))
end

return WorldGenerator
