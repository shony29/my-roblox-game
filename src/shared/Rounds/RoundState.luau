--!strict
-- RoundState: the shared "names" the server and clients agree on.
--
-- How information flows (the server is the only one who writes):
--   * The server makes a Folder in ReplicatedStorage called "RoundState" and
--     writes the current phase, timer and winner onto it as Attributes.
--     Attributes copy to every client automatically, even late joiners.
--   * Each player's score lives in leaderstats.Eliminations (an IntValue the
--     server owns). This also shows up on Roblox's built-in player list.
--   * A RemoteEvent called "Eliminated" tells clients "A eliminated B" for the
--     kill feed. It only goes server -> client; clients never send anything.

export type Phase = "Waiting" | "Playing" | "Intermission"

local RoundState = table.freeze({
	FOLDER_NAME = "RoundState",
	ELIMINATED_EVENT = "Eliminated",

	-- Attribute names on the RoundState folder.
	ATTR_PHASE = "Phase", -- Phase
	ATTR_ENDS_AT = "EndsAt", -- number, in workspace:GetServerTimeNow() time
	ATTR_ROUND_NUMBER = "RoundNumber", -- number
	ATTR_WINNER_TEXT = "WinnerText", -- string, "" until a round ends
	ATTR_WINNER_SCORE = "WinnerScore", -- number

	-- Name of the score IntValue inside each player's leaderstats folder.
	SCORE_STAT = "Eliminations",

	-- Attribute set to true on a character while it has spawn protection.
	-- Blaster code can check this too, as an extra safety net.
	PROTECTED_ATTR = "SpawnProtected",
})

return RoundState
