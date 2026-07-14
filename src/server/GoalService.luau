--[[
	GoalService — the HUD goal ladder ("always know what's next").

	Goals live in GameConfig.Goals and complete strictly in order. Progress
	comes from two kinds of stats:
	  * counters bumped by other services (EggsCollected, HatchCount, ...)
	    stored in data.Stats
	  * live values computed on demand (IncomePerSec, EquippedCount,
	    DiscoveredCount, Rebirths)

	Completing a goal grants silver (through DataService.grantSilver so it
	counts toward rebirth), toasts the player, and advances the ladder.
	A slow loop re-checks live stats so "reach 500/s" completes on its own.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local IndexUtil = require(ReplicatedStorage.IndexUtil)
local Remotes = require(ReplicatedStorage.Remotes)

local DataService = require(script.Parent.DataService)
local PlayerStats = require(script.Parent.PlayerStats)

local GoalService = {}

local function statValue(player: Player, data, stat: string): number
	if stat == "IncomePerSec" then
		return PlayerStats.getIncomePerSecond(player)
	elseif stat == "EquippedCount" then
		return #(data.Equipped or {})
	elseif stat == "DiscoveredCount" then
		return IndexUtil.discoveredCount(data.Discovered or {})
	elseif stat == "Rebirths" then
		return data.Rebirths or 0
	end
	return (data.Stats and data.Stats[stat]) or 0
end

-- What the client's goal strip should show right now
function GoalService.payload(player: Player)
	local data = DataService.get(player)
	if not data then
		return nil
	end
	local goal = GameConfig.Goals[data.GoalIndex]
	if not goal then
		return { Done = true, Index = data.GoalIndex, Total = #GameConfig.Goals }
	end
	return {
		Index = data.GoalIndex,
		Total = #GameConfig.Goals,
		Text = goal.Text,
		Progress = math.min(statValue(player, data, goal.Stat), goal.Target),
		Target = goal.Target,
		Reward = goal.Reward,
	}
end

function GoalService.push(player: Player)
	local payload = GoalService.payload(player)
	if payload then
		Remotes.GoalUpdate:FireClient(player, payload)
	end
end

-- Complete every goal the player currently satisfies (they can chain)
function GoalService.check(player: Player)
	local data = DataService.get(player)
	if not data then
		return
	end
	local advanced = false
	while true do
		local goal = GameConfig.Goals[data.GoalIndex]
		if not goal or statValue(player, data, goal.Stat) < goal.Target then
			break
		end
		DataService.grantSilver(player, goal.Reward)
		data.GoalIndex += 1
		advanced = true
		Remotes.Notify:FireClient(player, {
			Text = ("🎯 %s  +%d 🪙"):format(goal.Text, goal.Reward),
			Kind = "Goal",
		})
	end
	if advanced then
		GoalService.push(player)
	end
end

-- Counter bump from another service ("one more egg collected")
function GoalService.bump(player: Player, stat: string, amount: number?)
	local data = DataService.get(player)
	if not data then
		return
	end
	data.Stats[stat] = (data.Stats[stat] or 0) + (amount or 1)
	GoalService.check(player)
	GoalService.push(player) -- progress moved even if the goal didn't finish
end

-- High-water-mark stat ("best rarity ever hatched")
function GoalService.raiseTo(player: Player, stat: string, value: number)
	local data = DataService.get(player)
	if not data then
		return
	end
	if value > (data.Stats[stat] or 0) then
		data.Stats[stat] = value
		GoalService.check(player)
		GoalService.push(player)
	end
end

function GoalService.init()
	-- Live stats (income/sec, equips) change without a counter bump —
	-- sweep everyone every few seconds so those goals complete on their own.
	task.spawn(function()
		while true do
			task.wait(3)
			for player in DataService.getAllLoaded() do
				GoalService.check(player)
			end
		end
	end)
end

return GoalService
