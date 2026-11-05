--!strict
--[[
	SoundConfig: every sound the game plays, and the volume of each category.

	Only sounds that ship with Roblox itself (rbxasset://sounds/...) are used
	here. Sounds marked PLACEHOLDER are silent ("") until you upload your own
	audio (Creator Dashboard -> Audio) and paste its "rbxassetid://..." here.
	Weapon fire sounds live in Config/WeaponConfig (FireSoundId).
]]

export type Category = "Weapons" | "Movement" | "UI" | "Match"

export type SoundInfo = {
	Id: string, -- "" = silent placeholder
	Category: Category,
	Volume: number,
	Pitch: number,
}

local PING = "rbxasset://sounds/electronicpingshort.wav"

local Sounds: { [string]: SoundInfo } = {
	Elimination = { Id = PING, Category = "Weapons", Volume = 0.9, Pitch = 1.5 },
	Jump = { Id = "rbxasset://sounds/action_jump.mp3", Category = "Movement", Volume = 0.3, Pitch = 1.2 },
	Land = { Id = "rbxasset://sounds/action_jump_land.mp3", Category = "Movement", Volume = 0.4, Pitch = 0.9 },
	Dash = { Id = "rbxasset://sounds/swordlunge.wav", Category = "Movement", Volume = 0.3, Pitch = 1.4 },
	CountdownTick = { Id = PING, Category = "Match", Volume = 0.45, Pitch = 0.8 },
	Go = { Id = PING, Category = "Match", Volume = 0.7, Pitch = 1.6 },
	MatchFound = { Id = "", Category = "Match", Volume = 0.8, Pitch = 1 }, -- PLACEHOLDER
	Victory = { Id = "", Category = "Match", Volume = 0.8, Pitch = 1 }, -- PLACEHOLDER
	Defeat = { Id = "", Category = "Match", Volume = 0.8, Pitch = 1 }, -- PLACEHOLDER
}

local SoundConfig = {
	Sounds = Sounds,
	-- Default category volumes (0 to 1). Players can change these later in
	-- Settings; the client stores them as "Volume<Category>" attributes.
	Volumes = { Master = 1, Weapons = 0.8, Movement = 0.6, UI = 0.7, Match = 0.8 } :: { [string]: number },
}

return SoundConfig
