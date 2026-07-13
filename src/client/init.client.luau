--[[
	Client bootstrap — wires input to remotes and remotes to rendering.

	The client's whole job:
	  * ASK the server for things (start a hatch, buy luck/upgrades) and
	    surface errors if refused
	  * RENDER what the server says is true (coins, eggs, pets, upgrades)
	  * PLAY the pretty effects (world egg bobbing, hatch reveals, toasts)

	No outcomes are ever decided here — a modified client can only make
	requests the server validates anyway.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimalModels = require(ReplicatedStorage.AnimalModels)
local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Remotes)

local EggFXController = require(script.EggFXController)
local HatchRevealController = require(script.HatchRevealController)
local Sounds = require(script.Sounds)
local UIController = require(script.UIController)

-- One loop cycles the hue of every Rainbow-mutated part (reveals + cards)
AnimalModels.startRainbowCycler()

-- ------------------------------------------------------------
-- Actions (client-side debounce; the server enforces its own limits)
-- ------------------------------------------------------------

local hatchBusy = false
local function requestStartHatch(eggType: string)
	if hatchBusy then
		return
	end
	hatchBusy = true
	local ok, result = pcall(function()
		return Remotes.StartHatch:InvokeServer(eggType)
	end)
	if ok and result and result.Success then
		Sounds.buttonPress()
		UIController.showToast(eggType .. " is hatching!")
	else
		UIController.showError((ok and result and result.Error) or "Something went wrong!")
		Sounds.errorBuzz()
	end
	task.wait(0.4)
	hatchBusy = false
end

local buyBusy = false
local function requestLuckBoost()
	if buyBusy then
		return
	end
	buyBusy = true
	local ok, result = pcall(function()
		return Remotes.BuyLuckBoost:InvokeServer()
	end)
	if ok and result and result.Success then
		UIController.setState({ Coins = result.Coins, LuckSecondsLeft = result.SecondsLeft })
		Sounds.raritySting(3)
	else
		UIController.showError((ok and result and result.Error) or "Something went wrong!")
		Sounds.errorBuzz()
	end
	task.wait(0.4)
	buyBusy = false
end

local upgradeBusy = false
local function requestUpgrade(key: string)
	if upgradeBusy then
		return
	end
	upgradeBusy = true
	local ok, result = pcall(function()
		return Remotes.BuyUpgrade:InvokeServer(key)
	end)
	if ok and result and result.Success then
		UIController.setState({ Coins = result.Coins })
		Sounds.raritySting(3)
		UIController.showToast("Upgrade purchased!")
	else
		UIController.showError((ok and result and result.Error) or "Something went wrong!")
		Sounds.errorBuzz()
	end
	task.wait(0.4)
	upgradeBusy = false
end

-- ------------------------------------------------------------
-- Boot
-- ------------------------------------------------------------

UIController.init({
	onStartHatch = requestStartHatch,
	onBuyLuck = requestLuckBoost,
	onBuyUpgrade = requestUpgrade,
})
HatchRevealController.init()
EggFXController.init()

-- Live updates pushed by the server
Remotes.StateUpdate.OnClientEvent:Connect(function(state)
	UIController.setState(state)
end)
Remotes.CollectionUpdate.OnClientEvent:Connect(function(collection)
	UIController.setCollection(collection)
end)
Remotes.EggInventoryUpdate.OnClientEvent:Connect(function(payload)
	UIController.setEggInventory(payload.Inventory, payload.Capacity)
end)
Remotes.UpgradesUpdate.OnClientEvent:Connect(function(payload)
	UIController.setUpgrades(payload)
end)
Remotes.Notify.OnClientEvent:Connect(function(payload)
	UIController.showToast(payload.Text, payload.Kind)
	if payload.Kind == "Pickup" then
		Sounds.eggPickup()
	elseif payload.Kind == "Error" then
		Sounds.errorBuzz()
	end
end)
Remotes.HatchComplete.OnClientEvent:Connect(function(result)
	HatchRevealController.play(result)
end)
Remotes.MythicAnnounce.OnClientEvent:Connect(function(payload)
	local egg = GameConfig.EggByName[payload.EggType]
	UIController.announce("🌟 A " .. payload.EggType .. " has appeared! 🌟", egg and egg.Color or nil)
	Sounds.mythicAnnounce()
end)

-- Initial snapshot (covers everything that happened before we connected)
local initialState = Remotes.GetState:InvokeServer()
if initialState then
	UIController.setState(initialState)
	UIController.setCollection(initialState.Collection)
	UIController.setEggInventory(initialState.EggInventory, initialState.EggCapacity)
	UIController.setUpgrades({ Upgrades = initialState.Upgrades, EggCapacity = initialState.EggCapacity })
end

print("[Wildhaven] Client ready 🐿️")
