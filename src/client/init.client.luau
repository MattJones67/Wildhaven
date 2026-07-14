--[[
	Client bootstrap — wires input to remotes and remotes to rendering.

	The client's whole job:
	  * ASK the server for things (hatch, equip, rebirth, buy) and surface
	    errors if refused
	  * RENDER what the server says is true (coins, eggs, pets, upgrades,
	    goals, discoveries, equipped teams)
	  * PLAY the pretty effects (following pets, reveals, popups, toasts)

	No outcomes are ever decided here — a modified client can only make
	requests the server validates anyway.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimalModels = require(ReplicatedStorage.AnimalModels)
local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Remotes)

local BiomeWallController = require(script.BiomeWallController)
local BuildController = require(script.BuildController)
local EggFXController = require(script.EggFXController)
local HatchRevealController = require(script.HatchRevealController)
local PetFollowController = require(script.PetFollowController)
local ProgressUI = require(script.ProgressUI)
local Sounds = require(script.Sounds)
local UIController = require(script.UIController)

-- One loop cycles the hue of every Rainbow-mutated part (reveals + cards)
AnimalModels.startRainbowCycler()

-- ------------------------------------------------------------
-- Actions (client-side debounce; the server enforces its own limits)
-- ------------------------------------------------------------

-- Generic guarded invoke: one in flight at a time per action
local function makeAction(invoke: (...any) -> any, onSuccess: (any) -> ())
	local busy = false
	return function(...)
		if busy then
			return
		end
		busy = true
		local args = { ... }
		local ok, result = pcall(function()
			return invoke(table.unpack(args))
		end)
		if ok and result and result.Success then
			onSuccess(result)
		else
			UIController.showError((ok and result and result.Error) or "Something went wrong!")
			Sounds.errorBuzz()
		end
		task.wait(0.35)
		busy = false
	end
end

local requestStartHatch = makeAction(function(eggType)
	return Remotes.StartHatch:InvokeServer(eggType)
end, function()
	Sounds.buttonPress()
	UIController.showToast("Egg is hatching!")
end)

local requestLuckBoost = makeAction(function()
	return Remotes.BuyLuckBoost:InvokeServer()
end, function(result)
	UIController.setState({ Coins = result.Coins, LuckSecondsLeft = result.SecondsLeft })
	Sounds.raritySting(3)
end)

local requestUpgrade = makeAction(function(key)
	return Remotes.BuyUpgrade:InvokeServer(key)
end, function(result)
	UIController.setState({ Coins = result.Coins })
	Sounds.raritySting(3)
	UIController.showToast("Upgrade purchased!")
end)

local requestToggleEquip = makeAction(function(petId)
	return Remotes.ToggleEquip:InvokeServer(petId)
end, function(result)
	Sounds.equipPop()
	UIController.showToast(result.Equipped and "Pet equipped! ⭐" or "Pet unequipped")
end)

local requestRebirth = makeAction(function()
	return Remotes.Rebirth:InvokeServer()
end, function()
	-- The celebration arrives via RebirthCelebrate; nothing to do here
end)

local requestToggleAutoHatch = makeAction(function()
	return Remotes.ToggleAutoHatch:InvokeServer()
end, function(result)
	UIController.setAutoHatch(true, result.Enabled)
	UIController.showToast(result.Enabled and "🤖 Auto-Hatch ON" or "Auto-Hatch off")
end)

-- ------------------------------------------------------------
-- Boot
-- ------------------------------------------------------------

UIController.init({
	onStartHatch = requestStartHatch,
	onBuyLuck = requestLuckBoost,
	onBuyUpgrade = requestUpgrade,
	onToggleEquip = requestToggleEquip,
	onToggleAutoHatch = requestToggleAutoHatch,
})
ProgressUI.init({
	onRebirth = requestRebirth,
})
HatchRevealController.init()
EggFXController.init()
PetFollowController.init()
BiomeWallController.init()
BuildController.init()

-- Live updates pushed by the server
Remotes.StateUpdate.OnClientEvent:Connect(function(state)
	UIController.setState(state)
	ProgressUI.setState(state)
	BiomeWallController.setState(state) -- gate walls react to progression
end)
Remotes.CollectionUpdate.OnClientEvent:Connect(function(collection)
	UIController.setCollection(collection)
	BuildController.setCollection(collection)
end)
Remotes.SanctuaryUpdate.OnClientEvent:Connect(function(payload)
	BuildController.setSanctuary(payload)
end)
Remotes.EggInventoryUpdate.OnClientEvent:Connect(function(payload)
	UIController.setEggInventory(payload.Inventory, payload.Capacity)
end)
Remotes.UpgradesUpdate.OnClientEvent:Connect(function(payload)
	UIController.setUpgrades(payload)
end)
Remotes.EquipUpdate.OnClientEvent:Connect(function(payload)
	UIController.setEquipped(payload)
	BuildController.setEquipped(payload)
end)
Remotes.IndexUpdate.OnClientEvent:Connect(function(payload)
	ProgressUI.setDiscovered(payload.Discovered)
end)
Remotes.GoalUpdate.OnClientEvent:Connect(function(payload)
	ProgressUI.setGoal(payload)
end)
Remotes.Notify.OnClientEvent:Connect(function(payload)
	UIController.showToast(payload.Text, payload.Kind)
	if payload.Kind == "Pickup" then
		Sounds.eggPickup()
	elseif payload.Kind == "Error" then
		Sounds.errorBuzz()
	elseif payload.Kind == "Goal" then
		Sounds.raritySting(2)
	elseif payload.Kind == "Discovery" then
		Sounds.hatchReady()
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
Remotes.RebirthCelebrate.OnClientEvent:Connect(function(payload)
	ProgressUI.celebrateRebirth(payload)
end)
Remotes.WelcomeBack.OnClientEvent:Connect(function(payload)
	local minutes = math.floor(payload.AwaySeconds / 60)
	local timeText = minutes >= 120 and (math.floor(minutes / 60) .. " hours") or (minutes .. " minutes")
	ProgressUI.popup("💤 Welcome back!", ("Your pets earned %s 🪙 while you were away (%s)!"):format(tostring(payload.Coins), timeText))
end)
Remotes.DailyReward.OnClientEvent:Connect(function(payload)
	ProgressUI.popup("🎁 Daily Reward — Day " .. payload.Day, "You got: " .. payload.Label)
end)

-- Initial snapshot (covers everything that happened before we connected)
local initialState = Remotes.GetState:InvokeServer()
if initialState then
	UIController.setState(initialState)
	UIController.setCollection(initialState.Collection)
	BuildController.setCollection(initialState.Collection)
	BuildController.setEquipped({ Equipped = initialState.Equipped })
	BiomeWallController.setState(initialState)
	UIController.setEggInventory(initialState.EggInventory, initialState.EggCapacity)
	UIController.setUpgrades({ Upgrades = initialState.Upgrades, EggCapacity = initialState.EggCapacity, EquipSlots = initialState.EquipSlots })
	UIController.setEquipped({ Equipped = initialState.Equipped, Slots = initialState.EquipSlots })
	UIController.setAutoHatch(initialState.AutoHatchUnlocked, initialState.AutoHatchEnabled)
	ProgressUI.setState(initialState)
	ProgressUI.setDiscovered(initialState.Discovered)
	ProgressUI.setGoal(initialState.Goal)
end

-- Sanctuary snapshot (separate remote; SanctuaryService owns it)
local initialSanctuary = Remotes.GetSanctuary:InvokeServer()
if initialSanctuary then
	BuildController.setSanctuary(initialSanctuary)
end

print("[Wildhaven] Client ready 🐿️")
