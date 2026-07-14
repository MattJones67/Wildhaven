--[[
	Remotes — creates (on the server) or finds (on the client) every
	RemoteEvent/RemoteFunction the game uses.

	The remotes live as children of THIS ModuleScript (a separate folder
	would collide with this module's own name in ReplicatedStorage — that
	bug cost us an afternoon in slice 1).

	SECURITY NOTE: remotes are just phone lines. The SERVER decides what
	actually happens when a request arrives.
]]

local RunService = game:GetService("RunService")

-- name -> class. Add new remotes here and both sides pick them up.
local DEFINITIONS = {
	-- client -> server requests (server validates everything)
	GetState = "RemoteFunction", -- full state snapshot once, on join
	StartHatch = "RemoteFunction", -- "put one of my <egg type> into a hatch slot"
	BuyPotion = "RemoteFunction", -- patch 5: "buy potion <key> for silver"
	UsePotion = "RemoteFunction", -- patch 5: "drink potion <key>" (timed buff)
	RedeemCode = "RemoteFunction", -- patch 5: "redeem code <text>"
	BuyTraderItem = "RemoteFunction", -- patch 5: "buy trader stock slot <index>"
	BuyUpgrade = "RemoteFunction", -- "buy the next level of <upgrade key>"
	ToggleEquip = "RemoteFunction", -- "equip/unequip pet <id>"
	Rebirth = "RemoteFunction", -- "I want to rebirth"
	ToggleAutoHatch = "RemoteFunction", -- "turn auto-hatch on/off"
	-- patch 4: sanctuary building (every one server-validated)
	GetSanctuary = "RemoteFunction", -- full sanctuary snapshot (join / rebuild)
	PlaceObject = "RemoteFunction", -- "place <key> at (x,z) rotated r"
	MoveObject = "RemoteFunction", -- "move object <uid> to (x,z,r)"
	DeleteObject = "RemoteFunction", -- "delete object <uid>"
	PlacePet = "RemoteFunction", -- "put pet <id> into habitat <uid>"
	UnplacePet = "RemoteFunction", -- "take pet <id> out of my sanctuary"
	RelocatePlot = "RemoteFunction", -- "move my whole plot to <biome>"
	RollClass = "RemoteFunction", -- "roll (or re-roll) my class"
	-- patch 4: guide NPC quests
	AcceptQuest = "RemoteFunction", -- "I accept quest <id>"
	TurnInQuest = "RemoteFunction", -- "I finished quest <id>, pay up"
	GetQuests = "RemoteFunction", -- active-quest tracker snapshot, on join

	-- server -> client pushes (client just renders these)
	StateUpdate = "RemoteEvent", -- coins / income / luck every tick
	CollectionUpdate = "RemoteEvent", -- full pet collection when it changes
	EggInventoryUpdate = "RemoteEvent", -- carried eggs + capacity when they change
	UpgradesUpdate = "RemoteEvent", -- upgrade levels when they change
	HatchComplete = "RemoteEvent", -- a hatch finished: play the reveal
	Notify = "RemoteEvent", -- small toast messages ("+1 Forest Egg")
	MythicAnnounce = "RemoteEvent", -- server-wide: a Mythic Egg spawned!
	EquipUpdate = "RemoteEvent", -- YOUR equipped pet ids + slot count
	EquipBroadcast = "RemoteEvent", -- EVERYONE's equipped pets (for follow visuals)
	IndexUpdate = "RemoteEvent", -- discovered-pets set changed (dex fills in)
	GoalUpdate = "RemoteEvent", -- current goal text/progress changed
	RebirthCelebrate = "RemoteEvent", -- big rebirth celebration trigger
	WelcomeBack = "RemoteEvent", -- offline earnings popup on join
	DailyReward = "RemoteEvent", -- daily login reward popup
	SanctuaryUpdate = "RemoteEvent", -- your sanctuary state changed (re-render build UI)
	QuestDialog = "RemoteEvent", -- a guide NPC starts talking (open dialog UI)
	QuestUpdate = "RemoteEvent", -- active quests / progress changed (HUD tracker)
	PotionsUpdate = "RemoteEvent", -- patch 5: potion inventory changed
	TraderDialog = "RemoteEvent", -- patch 5: trader shop opens (stock + timer)
}

local Remotes = {}

if RunService:IsServer() then
	-- Server: create each remote as a child of this ModuleScript.
	-- Children of a ModuleScript in ReplicatedStorage replicate to clients.
	for name, className in DEFINITIONS do
		local remote = Instance.new(className)
		remote.Name = name
		remote.Parent = script
		Remotes[name] = remote
	end
else
	-- Client: wait for the server-made remotes to replicate.
	for name in DEFINITIONS do
		Remotes[name] = script:WaitForChild(name)
	end
end

return Remotes
