--!strict
--[[
	MatchState: the names the server and clients agree on for a match.

	The server is the only one who changes these. It writes them as
	attributes on ReplicatedStorage.MatchState (and on each Player), and
	attributes copy to every client automatically, even late joiners.

	Match flow (server/Services/MatchService runs it):
	  Lobby -> Queued -> MatchFound -> (MapVoting -> Loading) -> Countdown
	        -> InMatch -> RoundEnd -> (next round: Countdown ...) -> MatchResults
	        -> Returning -> Lobby
	MapVoting and Loading arrive in Phase 7.
]]

export type State =
	"Lobby"
	| "Queued"
	| "MatchFound"
	| "MapVoting"
	| "Loading"
	| "Countdown"
	| "InMatch"
	| "RoundEnd"
	| "MatchResults"
	| "Returning"

export type TeamId = "A" | "B"

local STATES: { [string]: State } = {
	Lobby = "Lobby",
	Queued = "Queued",
	MatchFound = "MatchFound",
	MapVoting = "MapVoting",
	Loading = "Loading",
	Countdown = "Countdown",
	InMatch = "InMatch",
	RoundEnd = "RoundEnd",
	MatchResults = "MatchResults",
	Returning = "Returning",
}

local MatchState = {}

MatchState.FOLDER_NAME = "MatchState"

-- Attributes on ReplicatedStorage.MatchState
MatchState.Attr = table.freeze({
	State = "State", -- State
	Mode = "Mode", -- ModeConfig mode Id
	Round = "Round", -- number
	RoundsToWin = "RoundsToWin", -- number
	ScoreA = "ScoreA", -- rounds won by team A
	ScoreB = "ScoreB",
	PhaseEndsAt = "PhaseEndsAt", -- workspace:GetServerTimeNow() when this state ends (0 = no timer)
	RoundWinner = "RoundWinner", -- "A", "B" or "" (draw)
	MatchWinner = "MatchWinner", -- "A", "B" or ""
	MapId = "MapId", -- the map being played (or just picked)
	VoteOptions = "VoteOptions", -- comma-separated map Ids during MapVoting
	RematchVotes = "RematchVotes", -- players who pressed REMATCH
	RematchNeeded = "RematchNeeded", -- players needed for a rematch
	-- Also "Queue<ModeId>" = how many players are waiting for that mode, e.g. QueueDuel,
	-- and "Votes<MapId>" = votes for that map during MapVoting, e.g. VotesJellyArena.
})

-- Attributes on each Player
MatchState.PlayerAttr = table.freeze({
	Team = "Team", -- "A", "B", or nil when not in a match
	Status = "MatchStatus", -- "Menu" (before Play), "Lobby", "Queued" or "InMatch"
	QueueMode = "QueueMode", -- mode Id while queued
	QueuedAt = "QueuedAt", -- workspace:GetServerTimeNow() when they joined the queue
	Eliminations = "MatchEliminations",
	Deaths = "MatchDeaths",
	Damage = "MatchDamage",
})

-- On a character while it has spawn protection.
MatchState.PROTECTED_ATTR = "SpawnProtected"

MatchState.Teams = table.freeze({
	A = table.freeze({ Name = "Blue", Color = Color3.fromRGB(90, 170, 255) }),
	B = table.freeze({ Name = "Red", Color = Color3.fromRGB(255, 85, 85) }),
})

-- Reads a state value safely (anything unexpected counts as "Lobby").
function MatchState.toState(value: unknown): State
	if typeof(value) == "string" and STATES[value] then
		return STATES[value]
	end
	return "Lobby"
end

function MatchState.toTeam(value: unknown): TeamId?
	if value == "A" then
		return "A"
	elseif value == "B" then
		return "B"
	end
	return nil
end

export type TeamInfo = { Name: string, Color: Color3 }

-- Name and colour of a team (typed, so --!strict is happy).
function MatchState.teamInfo(team: TeamId): TeamInfo
	return if team == "A" then MatchState.Teams.A else MatchState.Teams.B
end

function MatchState.otherTeam(team: TeamId): TeamId
	return if team == "A" then "B" else "A"
end

return MatchState
