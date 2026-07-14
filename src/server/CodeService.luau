--[[
	CodeService — one-time redemption codes (patch 5), a primary GOLD
	source and a marketing lever: drop a new code with every update.

	Codes live in GameConfig.Codes (CODE -> reward bundle). Removing a code
	from that table expires it for everyone instantly.

	SECURITY: the server normalizes and validates the code, checks the
	player hasn't redeemed it before (data.RedeemedCodes), and grants
	through the shared Rewards module. Rate-limited against guess-spam.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.GameConfig)
local Remotes = require(ReplicatedStorage.Remotes)

local DataService = require(script.Parent.DataService)
local Rewards = require(script.Parent.Rewards)

local CodeService = {}

local lastRedeemAt: { [Player]: number } = {}

local function onRedeemCode(player: Player, rawCode: any)
	-- SECURITY: rate limit (stops brute-force guessing)
	local now = os.clock()
	local last = lastRedeemAt[player]
	if last and now - last < 1.5 then
		return { Success = false, Error = "Too fast!" }
	end
	lastRedeemAt[player] = now

	if typeof(rawCode) ~= "string" then
		return { Success = false, Error = "Type a code first!" }
	end
	-- Normalize: trim whitespace, uppercase — "  wildhaven " works
	local code = rawCode:gsub("%s+", ""):upper()
	if #code == 0 or #code > 30 then
		return { Success = false, Error = "Type a code first!" }
	end

	local data = DataService.get(player)
	if not data then
		return { Success = false, Error = "Still loading..." }
	end

	local reward = GameConfig.Codes[code]
	if not reward then
		return { Success = false, Error = "Invalid or expired code" }
	end
	-- SECURITY: strictly one redemption per player, saved forever
	if data.RedeemedCodes[code] then
		return { Success = false, Error = "Already redeemed!" }
	end

	data.RedeemedCodes[code] = true
	Rewards.grant(player, reward)

	return { Success = true, Text = Rewards.text(reward) }
end

function CodeService.init()
	Remotes.RedeemCode.OnServerInvoke = onRedeemCode
	Players.PlayerRemoving:Connect(function(player)
		lastRedeemAt[player] = nil
	end)
end

return CodeService
