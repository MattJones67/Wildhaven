--[[
	Server bootstrap — the only server Script; everything else is a
	ModuleScript it starts up in a deliberate order:

	  1. Remotes            (shared module creates the RemoteEvents/Functions)
	  2. DataService        (players can start loading data immediately)
	  3. ForestGenerator    (the island exists before anyone finishes spawning)
	  4. BaseUpgradeService (village cabins built; plots claimable)
	  5. IncomeService, HatchService, EggSpawnService, ShopService (gameplay live)

	TODO (later passes): SanctuaryService (free-build zones) and
	RebirthService get required and init()-ed here, same pattern.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Requiring Remotes on the server CREATES the remotes in ReplicatedStorage.
require(ReplicatedStorage.Remotes)

local DataService = require(script.DataService)
local ForestGenerator = require(script.ForestGenerator)
local BaseUpgradeService = require(script.BaseUpgradeService)
local IncomeService = require(script.IncomeService)
local HatchService = require(script.HatchService)
local EggSpawnService = require(script.EggSpawnService)
local ShopService = require(script.ShopService)

DataService.init()
ForestGenerator.build()
BaseUpgradeService.init()
IncomeService.init()
HatchService.init()
EggSpawnService.init()
ShopService.init()

print("[Wildhaven] Server ready 🌲")
