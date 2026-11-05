--!strict
--[[
	ModeConfig: the rules for each game mode, in one place.
	The match system (Phase 5) reads these, so a mode is just data.
]]

export type ModeId = "Duel" | "TeamDuel" | "TeamCombat"

export type Mode = {
	Id: ModeId,
	DisplayName: string,
	TeamSize: number, -- players per team
	TeamCount: number,
	RoundsToWin: number, -- first team to win this many rounds wins the match
	RoundTime: number, -- seconds before a round ends with no winner
	CountdownTime: number, -- seconds of "3, 2, 1" before each round
	RoundEndTime: number, -- seconds to show who won the round
	RespawnInRound: boolean, -- false = eliminated players wait for the next round
}

local Modes: { [ModeId]: Mode } = {
	Duel = {
		Id = "Duel",
		DisplayName = "1v1 Duel",
		TeamSize = 1,
		TeamCount = 2,
		RoundsToWin = 5,
		RoundTime = 90,
		CountdownTime = 3,
		RoundEndTime = 3,
		RespawnInRound = false,
	},
	TeamDuel = {
		Id = "TeamDuel",
		DisplayName = "2v2 Team Duel",
		TeamSize = 2,
		TeamCount = 2,
		RoundsToWin = 5,
		RoundTime = 120,
		CountdownTime = 3,
		RoundEndTime = 3,
		RespawnInRound = false,
	},
	TeamCombat = {
		Id = "TeamCombat",
		DisplayName = "4v4 Team Combat",
		TeamSize = 4,
		TeamCount = 2,
		RoundsToWin = 4,
		RoundTime = 150,
		CountdownTime = 3,
		RoundEndTime = 4,
		RespawnInRound = false,
	},
}

local ModeConfig = {
	Modes = Modes,
	Order = { "Duel", "TeamDuel", "TeamCombat" } :: { ModeId },
	Default = "Duel" :: ModeId,
}

-- Checks a value sent by a client is a real mode Id.
function ModeConfig.get(value: unknown): Mode?
	if typeof(value) ~= "string" then
		return nil
	end
	return Modes[value :: ModeId]
end

return ModeConfig
