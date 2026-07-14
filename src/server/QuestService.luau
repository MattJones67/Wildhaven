--[[
	QuestService — guide NPCs and their biome quests.

	Each biome guide offers two things (all defined in GameConfig.Quests):
	  * the next quest in that biome's ONE-TIME CHAIN (in order)
	  * a repeatable DAILY (24h server-stamped cooldown after turn-in)

	Progress is counted by the SERVER as things actually happen:
	  * EggSpawnService calls onEggCollected(player, eggType)
	  * HatchService calls onHatched(player, species, rarityOrder)
	so a hacked client cannot claim "I collected 3 Sand Eggs" — the server
	watched them do it (or didn't).

	Data (persisted in data.Quests):
	  Progress[questId] = n     -- accepted & counting
	  Completed[questId] = true -- chain quests finished forever
	  DailyDoneAt[biome] = t    -- last daily turn-in (os.time)

	Rewards: Coins / LuckBoost / ClassToken / Pet (granted straight into
	the collection with a proper Id + dex discovery).

	TODO(later patch): secret-area discovery quests — add a third quest
	Type ("Discover") here plus trigger zones in BiomeGenerator; the
	accept/turn-in/tracker plumbing below already handles any type.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Remotes)

local BiomeGenerator = require(script.Parent.BiomeGenerator)
local DataService = require(script.Parent.DataService)
local EggSpawnService = require(script.Parent.EggSpawnService)
local HatchService = require(script.Parent.HatchService)
local Rewards = require(script.Parent.Rewards)

local QUESTS = GameConfig.Quests

local QuestService = {}

-- Flat lookups built from the config once
local QUEST_BY_ID: { [string]: any } = {}
local CHAIN_INFO: { [string]: { Biome: string, Index: number } } = {}
local DAILY_BIOME: { [string]: string } = {}

for biomeName, chain in QUESTS.Chains do
	for index, quest in chain do
		QUEST_BY_ID[quest.Id] = quest
		CHAIN_INFO[quest.Id] = { Biome = biomeName, Index = index }
	end
end
for biomeName, quest in QUESTS.Dailies do
	QUEST_BY_ID[quest.Id] = quest
	DAILY_BIOME[quest.Id] = biomeName
end

local lastTalkAt: { [Player]: number } = {}

-- ------------------------------------------------------------
-- Data helpers
-- ------------------------------------------------------------

local function questsOf(player: Player)
	local data = DataService.get(player)
	if not data then
		return nil
	end
	data.Quests = data.Quests or {}
	data.Quests.Progress = data.Quests.Progress or {}
	data.Quests.Completed = data.Quests.Completed or {}
	data.Quests.DailyDoneAt = data.Quests.DailyDoneAt or {}
	return data.Quests
end

-- The next uncompleted quest in a biome's chain (nil = chain finished)
local function currentChainQuest(quests, biomeName)
	for _, quest in QUESTS.Chains[biomeName] or {} do
		if not quests.Completed[quest.Id] then
			return quest
		end
	end
	return nil
end

-- "available" | "active" | "ready" | "cooldown"
local function questStatus(quests, quest): string
	local progress = quests.Progress[quest.Id]
	if progress ~= nil then
		return progress >= quest.Count and "ready" or "active"
	end
	local dailyBiome = DAILY_BIOME[quest.Id]
	if dailyBiome then
		local doneAt = quests.DailyDoneAt[dailyBiome] or 0
		if os.time() - doneAt < QUESTS.DailyCooldownSeconds then
			return "cooldown"
		end
	end
	return "available"
end

-- Patch 5: reward text + granting both live in the shared Rewards module
local function rewardText(reward): string
	return Rewards.text(reward)
end

-- ------------------------------------------------------------
-- Payloads
-- ------------------------------------------------------------

local function questEntry(quests, quest)
	return {
		Id = quest.Id,
		Text = quest.Text,
		Count = quest.Count,
		Progress = quests.Progress[quest.Id] or 0,
		Status = questStatus(quests, quest),
		RewardText = rewardText(quest.Reward),
	}
end

local function dialogPayload(player: Player, biomeName: string)
	local quests = questsOf(player)
	if not quests then
		return nil
	end
	local biome = GameConfig.BiomeByName[biomeName]
	local guide = GameConfig.Guides[biomeName]
	local entries = {}
	local chainQuest = currentChainQuest(quests, biomeName)
	if chainQuest then
		table.insert(entries, questEntry(quests, chainQuest))
	end
	local daily = QUESTS.Dailies[biomeName]
	if daily then
		table.insert(entries, questEntry(quests, daily))
	end
	return {
		Biome = biomeName,
		Emoji = biome.Emoji,
		GuideName = guide.Name,
		Greeting = guide.Greeting,
		ChainDone = chainQuest == nil,
		Quests = entries,
	}
end

-- Everything the player has ACCEPTED, for the HUD tracker
local function trackerPayload(player: Player)
	local quests = questsOf(player)
	if not quests then
		return { Active = {} }
	end
	local active = {}
	for questId in quests.Progress do
		local quest = QUEST_BY_ID[questId]
		if quest then
			local info = CHAIN_INFO[questId]
			local biomeName = info and info.Biome or DAILY_BIOME[questId]
			local biome = biomeName and GameConfig.BiomeByName[biomeName]
			table.insert(active, {
				Id = questId,
				Text = (biome and biome.Emoji .. " " or "") .. quest.Text,
				Progress = quests.Progress[questId],
				Count = quest.Count,
			})
		end
	end
	table.sort(active, function(a, b)
		return a.Id < b.Id
	end)
	return { Active = active }
end

local function pushTracker(player: Player)
	Remotes.QuestUpdate:FireClient(player, trackerPayload(player))
end

-- ------------------------------------------------------------
-- Rewards
-- ------------------------------------------------------------

-- Patch 5: quests hand their (possibly multi-part) reward bundles to the
-- shared Rewards module — same behavior as codes, blocks, and the trader.
local function grantReward(player: Player, reward)
	Rewards.grant(player, reward)
end

-- ------------------------------------------------------------
-- Remote handlers
-- ------------------------------------------------------------

local function onAcceptQuest(player: Player, questId: any)
	local quests = questsOf(player)
	local quest = typeof(questId) == "string" and QUEST_BY_ID[questId] or nil
	if not quests or not quest then
		return { Success = false, Error = "Unknown quest" }
	end
	-- SECURITY: must genuinely be offerable right now
	local status = questStatus(quests, quest)
	if status ~= "available" then
		return { Success = false, Error = "Can't accept that right now" }
	end
	local info = CHAIN_INFO[questId]
	if info then
		local current = currentChainQuest(quests, info.Biome)
		if not current or current.Id ~= questId then
			return { Success = false, Error = "Finish the earlier quests first!" }
		end
	end

	quests.Progress[questId] = 0
	pushTracker(player)
	local biomeName = info and info.Biome or DAILY_BIOME[questId]
	return { Success = true, Dialog = dialogPayload(player, biomeName) }
end

local function onTurnInQuest(player: Player, questId: any)
	local quests = questsOf(player)
	local quest = typeof(questId) == "string" and QUEST_BY_ID[questId] or nil
	if not quests or not quest then
		return { Success = false, Error = "Unknown quest" }
	end
	-- SECURITY: the server counted the progress itself
	if questStatus(quests, quest) ~= "ready" then
		return { Success = false, Error = "Not finished yet!" }
	end

	quests.Progress[questId] = nil
	local info = CHAIN_INFO[questId]
	if info then
		quests.Completed[questId] = true
	else
		quests.DailyDoneAt[DAILY_BIOME[questId]] = os.time()
	end

	grantReward(player, quest.Reward)
	pushTracker(player)
	Remotes.Notify:FireClient(player, {
		Text = "✅ Quest complete! +" .. rewardText(quest.Reward),
		Kind = "Goal",
	})
	local biomeName = info and info.Biome or DAILY_BIOME[questId]
	return { Success = true, Dialog = dialogPayload(player, biomeName) }
end

-- ------------------------------------------------------------
-- Progress hooks (called by the services that WATCHED it happen)
-- ------------------------------------------------------------

local function bumpMatching(player: Player, matcher: (any) -> boolean)
	local quests = questsOf(player)
	if not quests then
		return
	end
	local changed = false
	for questId, progress in quests.Progress do
		local quest = QUEST_BY_ID[questId]
		if quest and progress < quest.Count and matcher(quest) then
			quests.Progress[questId] = progress + 1
			changed = true
			if quests.Progress[questId] >= quest.Count then
				Remotes.Notify:FireClient(player, { Text = "🎯 Quest ready — return to the guide!", Kind = "Goal" })
			else
				Remotes.Notify:FireClient(player, {
					Text = ("%s  %d/%d"):format(quest.Text, quests.Progress[questId], quest.Count),
					Kind = "Quest",
				})
			end
		end
	end
	if changed then
		pushTracker(player)
	end
end

function QuestService.onEggCollected(player: Player, eggType: string)
	bumpMatching(player, function(quest)
		return quest.Type == "CollectEgg" and quest.Param == eggType
	end)
end

function QuestService.onHatched(player: Player, species: string, rarityOrder: number)
	local animal = GameConfig.AnimalByName[species]
	local petBiome = animal and animal.Biome
	bumpMatching(player, function(quest)
		if quest.Type ~= "HatchPet" then
			return false
		end
		if quest.Param ~= "Any" and quest.Param ~= petBiome then
			return false
		end
		return rarityOrder >= (quest.MinRarity or 1)
	end)
end

-- ------------------------------------------------------------
-- Lifecycle
-- ------------------------------------------------------------

function QuestService.init()
	-- Feed on the hooks the other services exposed in checkpoint 1
	EggSpawnService.setCollectedCallback(QuestService.onEggCollected)
	HatchService.setHatchedCallback(QuestService.onHatched)

	-- Wire every guide NPC's Talk prompt
	for _, biome in GameConfig.Biomes do
		local prompt = BiomeGenerator.getGuidePrompt(biome.Name)
		if prompt then
			prompt.Triggered:Connect(function(player)
				-- Rate limit chatty tapping
				local now = os.clock()
				local last = lastTalkAt[player]
				if last and now - last < 0.8 then
					return
				end
				lastTalkAt[player] = now
				local payload = dialogPayload(player, biome.Name)
				if payload then
					Remotes.QuestDialog:FireClient(player, payload)
				end
			end)
		end
	end

	Remotes.AcceptQuest.OnServerInvoke = onAcceptQuest
	Remotes.TurnInQuest.OnServerInvoke = onTurnInQuest
	Remotes.GetQuests.OnServerInvoke = function(player)
		DataService.waitForData(player, 10)
		return trackerPayload(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		lastTalkAt[player] = nil
	end)
end

return QuestService
