--[[
	Rewards — ONE place that grants any reward bundle, used by quests,
	codes, lucky blocks, the wandering trader, and daily logins. A reward
	is a table that can COMBINE fields:

	  { Silver = 500, Gold = 2 }
	  { Potion = "MinorLuck", Count = 2 }
	  { Egg = "Ancient Egg" }
	  { Pet = "Fennec Fox" }
	  { ClassToken = 1 }
	  { Decor = "GoldenStatue" }   -- unlocks trader-exclusive decor

	Granting pushes the right client updates (state / collection / dex /
	egg inventory / potions) so every caller gets consistent behavior.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local IndexUtil = require(ReplicatedStorage.IndexUtil)
local Remotes = require(ReplicatedStorage.Remotes)

local DataService = require(script.Parent.DataService)
local IncomeService = require(script.Parent.IncomeService)
local PlayerStats = require(script.Parent.PlayerStats)

local Rewards = {}

-- Human-readable summary ("500 🪙 + 2 🌕") for toasts and quest cards
function Rewards.text(reward): string
	local parts = {}
	if reward.Silver then
		table.insert(parts, reward.Silver .. " 🪙")
	end
	if reward.Gold then
		table.insert(parts, reward.Gold .. " 🌕")
	end
	if reward.Potion then
		local potion = GameConfig.PotionByKey[reward.Potion]
		local count = reward.Count or 1
		table.insert(parts, (count > 1 and count .. "x " or "") .. (potion and potion.Emoji .. " " .. potion.Title or reward.Potion))
	end
	if reward.Egg then
		table.insert(parts, "🥚 " .. reward.Egg)
	end
	if reward.Pet then
		table.insert(parts, "🐾 " .. reward.Pet)
	end
	if reward.ClassToken then
		table.insert(parts, "🎟 Class Token")
	end
	if reward.Decor then
		local def = GameConfig.SanctuaryObjectByKey[reward.Decor]
		table.insert(parts, "🏡 " .. (def and def.Title or reward.Decor))
	end
	return table.concat(parts, " + ")
end

function Rewards.grant(player: Player, reward)
	local data = DataService.get(player)
	if not data then
		return
	end

	if reward.Silver then
		DataService.grantSilver(player, reward.Silver)
	end
	if reward.Gold then
		DataService.grantGold(player, reward.Gold)
		-- Gold is rare: every gain gets its own shimmer moment
		Remotes.Notify:FireClient(player, { Text = "+" .. reward.Gold .. " 🌕 GOLD!", Kind = "Gold" })
	end
	if reward.Potion then
		data.Potions = data.Potions or {}
		data.Potions[reward.Potion] = (data.Potions[reward.Potion] or 0) + (reward.Count or 1)
		Remotes.PotionsUpdate:FireClient(player, { Potions = data.Potions })
	end
	if reward.Egg then
		-- Straight into the satchel. Rewards may overflow capacity — the cap
		-- only gates world PICKUPS, never gifts.
		table.insert(data.EggInventory, reward.Egg)
		Remotes.EggInventoryUpdate:FireClient(player, {
			Inventory = data.EggInventory,
			Capacity = PlayerStats.getEggCapacity(player),
		})
	end
	if reward.Pet then
		local entry = { Id = data.NextPetId, Species = reward.Pet, Mutation = "None", Size = "Normal" }
		data.NextPetId += 1
		table.insert(data.Collection, entry)
		Remotes.CollectionUpdate:FireClient(player, data.Collection)
		if not data.Discovered[reward.Pet] then
			data.Discovered[reward.Pet] = true
			Remotes.IndexUpdate:FireClient(player, { Discovered = data.Discovered })
			Remotes.Notify:FireClient(player, { Text = "📖 NEW PET: " .. reward.Pet .. "!", Kind = "Discovery" })
			local rarity = GameConfig.AnimalByName[reward.Pet].Rarity
			if IndexUtil.isSetComplete(data.Discovered, rarity) then
				for _, indexReward in GameConfig.IndexRewards do
					if indexReward.Rarity == rarity then
						Remotes.Notify:FireClient(player, { Text = "🏆 SET COMPLETE! " .. indexReward.Label, Kind = "Discovery" })
					end
				end
			end
		end
	end
	if reward.ClassToken then
		data.ClassTokens = (data.ClassTokens or 0) + reward.ClassToken
	end
	if reward.Decor then
		data.UnlockedDecor = data.UnlockedDecor or {}
		data.UnlockedDecor[reward.Decor] = true
	end

	IncomeService.pushState(player)
end

return Rewards
