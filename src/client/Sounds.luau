--[[
	Sounds — every audio moment in the game gets a NAMED hook here, built
	from Roblox's built-in rbxasset sounds pitched up/down to make "tones".

	These are placeholders: when you get real audio later, replace the
	implementation of each hook (or swap ASSETS ids) and nothing else in
	the codebase changes.
]]

local SoundService = game:GetService("SoundService")

-- Built-in sounds that ship with Roblox — no uploaded asset ids needed.
local ASSETS = {
	Blip = "rbxasset://sounds/electronicpingshort.wav", -- clean ping; our "tone generator"
	Snap = "rbxasset://sounds/snap.mp3", -- sharp crack
	Swoosh = "rbxasset://sounds/swoosh.wav", -- soft whoosh
}

local Sounds = {}

-- Fire-and-forget one-shot. PlaybackSpeed doubles as pitch:
-- 2.0 = one octave up, 0.5 = one octave down.
local function play(assetId: string, pitch: number, volume: number)
	local sound = Instance.new("Sound")
	sound.SoundId = assetId
	sound.PlaybackSpeed = pitch
	sound.Volume = volume
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Once(function()
		sound:Destroy()
	end)
	task.delay(5, function() -- safety net if Ended never fires
		if sound.Parent then
			sound:Destroy()
		end
	end)
end

-- UI button press feedback
function Sounds.buttonPress()
	play(ASSETS.Blip, 1.6, 0.25)
end

-- Soft blip when the coin counter gains (kept quiet — it fires often)
function Sounds.coinBlip()
	play(ASSETS.Blip, 2.3, 0.06)
end

-- Rejected action (can't afford, too fast, etc.)
function Sounds.errorBuzz()
	play(ASSETS.Blip, 0.45, 0.35)
end

-- Egg anticipation wobbles: 1, 2, 3 — each a little higher and louder
function Sounds.eggWobble(index: number)
	play(ASSETS.Swoosh, 0.85 + index * 0.18, 0.25 + index * 0.08)
end

-- The egg shell giving way
function Sounds.eggCrack()
	play(ASSETS.Snap, 1, 0.6)
end

-- The pop as the animal springs out
function Sounds.hatchPop()
	play(ASSETS.Snap, 1.35, 0.5)
	play(ASSETS.Blip, 0.9, 0.4)
end

-- Satisfying pop + chime when you pick up a world egg
function Sounds.eggPickup()
	play(ASSETS.Snap, 1.6, 0.35)
	play(ASSETS.Blip, 1.5, 0.3)
	task.delay(0.08, function()
		play(ASSETS.Blip, 2, 0.25)
	end)
end

-- A hatch slot finished incubating (played just before the reveal)
function Sounds.hatchReady()
	play(ASSETS.Blip, 1.2, 0.35)
	task.delay(0.12, function()
		play(ASSETS.Blip, 1.8, 0.35)
	end)
end

-- Server-wide "a Mythic Egg has appeared!" fanfare
function Sounds.mythicAnnounce()
	play(ASSETS.Blip, 0.6, 0.5)
	task.delay(0.15, function()
		play(ASSETS.Blip, 0.9, 0.5)
	end)
	task.delay(0.3, function()
		play(ASSETS.Blip, 1.2, 0.55)
		play(ASSETS.Blip, 0.6, 0.4)
	end)
end

-- Rising musical sting; bigger spectacle = longer, higher arpeggio.
-- Notes are semitone offsets of a major arpeggio played on the Blip.
local ARPEGGIO_STEPS = { 0, 4, 7, 12, 16, 19, 24 }
function Sounds.raritySting(spectacleOrder: number)
	local noteCount = math.clamp(spectacleOrder + 1, 2, #ARPEGGIO_STEPS)
	for i = 1, noteCount do
		task.delay((i - 1) * 0.09, function()
			local semitones = ARPEGGIO_STEPS[i]
			local pitch = 1 * 2 ^ (semitones / 12)
			play(ASSETS.Blip, pitch, 0.35)
		end)
	end
	-- Legendary+ gets a final triumphant high note held by a lower octave double
	if spectacleOrder >= 5 then
		task.delay(noteCount * 0.09 + 0.1, function()
			play(ASSETS.Blip, 2, 0.5)
			play(ASSETS.Blip, 1, 0.4)
		end)
	end
end

return Sounds
