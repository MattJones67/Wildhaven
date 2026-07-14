--[[
	Server bootstrap — the only server Script; everything else is a
	ModuleScript it starts up in a deliberate order:

	  1. Remotes            (shared module creates the RemoteEvents/Functions)
	  2. DataService        (players can start loading data immediately)
	  3. ForestGenerator    (the island exists before anyone finishes spawning)
	  4. BaseUpgradeService (village cabins built; plots claimable)
	  5. Gameplay services  (income, equip, goals, hatchery, eggs, shop)
	  6. RebirthService + ReturnsService (meta progression + welcome-back)

	TODO (later passes): SanctuaryService (free-build zones) plugs in here.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requiring Remotes on the server CREATES the remotes in ReplicatedStorage.
require(ReplicatedStorage.Remotes)

local DataService = require(script.DataService)
local TerrainForge = require(script.TerrainForge)
local ForestGenerator = require(script.ForestGenerator)
local BiomeGenerator = require(script.BiomeGenerator)
local BiomeService = require(script.BiomeService)
local BaseUpgradeService = require(script.BaseUpgradeService)
local GoalService = require(script.GoalService)
local IncomeService = require(script.IncomeService)
local EquipService = require(script.EquipService)
local HatchService = require(script.HatchService)
local EggSpawnService = require(script.EggSpawnService)
local ShopService = require(script.ShopService)
local ClassService = require(script.ClassService)
local SanctuaryService = require(script.SanctuaryService)
local QuestService = require(script.QuestService)
local RebirthService = require(script.RebirthService)
local ReturnsService = require(script.ReturnsService)

DataService.init()
TerrainForge.build() -- the whole connected continent's ground
ForestGenerator.build() -- carves river/pond/paths + plants the forest
BiomeGenerator.build() -- biome decor, landmarks, walls, hubs, guides
BiomeService.init()
BaseUpgradeService.init()
GoalService.init()
IncomeService.init()
EquipService.init()
HatchService.init()
EggSpawnService.init()
ShopService.init()
ClassService.init()
SanctuaryService.init()
QuestService.init()
RebirthService.init()
ReturnsService.init()

print("[Wildhaven] Server ready 🌲")
