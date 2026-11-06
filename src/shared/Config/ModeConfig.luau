--!strict
--[[
	ModeConfig: the rules for each game mode, in one place.
	The match system (Phase 5) reads these, so a mode is just data.
]]

export type ModeId = "Duel" | "TeamDuel" | "TeamCombat" | "FreeForAll"

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
	-- Free for all only (everyone for themselves, see MatchService):
	FreeForAll: boolean?,
	MinPlayers: number?, -- the match can start with this many
	MaxPlayers: number?, -- and takes at most this many
	FillTime: number?, -- once MinPlayers are waiting, seconds others get to join
	EliminationsToWin: number?, -- first to this many eliminations wins
	RespawnDelay: number?, -- seconds before you're back after being eliminated
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
	-- Everyone for themselves: 3 to 25 players, quick respawns, one long
	-- round. First to 20 eliminations (or the most when time runs out) wins.
	FreeForAll = {
		Id = "FreeForAll",
		DisplayName = "Free For All",
		TeamSize = 25,
		TeamCount = 1,
		RoundsToWin = 1,
		RoundTime = 300,
		CountdownTime = 3,
		RoundEndTime = 3,
		RespawnInRound = true,
		FreeForAll = true,
		MinPlayers = 3,
		MaxPlayers = 25,
		FillTime = 15,
		EliminationsToWin = 20,
		RespawnDelay = 2.5,
	},
}

local ModeConfig = {
	Modes = Modes,
	Order = { "Duel", "TeamDuel", "TeamCombat", "FreeForAll" } :: { ModeId },
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
