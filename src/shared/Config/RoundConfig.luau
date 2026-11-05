--!strict
-- RoundConfig: all the numbers that control a round, in one place.
-- Change a value here and both the server and the HUD pick it up.

local RoundConfig = table.freeze({
	-- Free-for-all: the first player to reach this many eliminations wins.
	ELIMINATIONS_TO_WIN = 25,

	-- How long a round lasts, in seconds (5 minutes).
	ROUND_LENGTH = 5 * 60,

	-- The break between rounds, in seconds.
	INTERMISSION_LENGTH = 10,

	-- How long you stay down after being eliminated, in seconds.
	RESPAWN_DELAY = 0.5,

	-- How long you are protected after spawning, in seconds.
	SPAWN_PROTECTION = 2,

	-- How many of the "safest" spawn points to pick from at random,
	-- so spawns stay away from enemies but are not totally predictable.
	SAFE_SPAWN_CHOICES = 3,

	-- Rounds only start once this many players are in the server.
	-- 1 makes solo testing in Studio easy; raise it to 2 for live games.
	MIN_PLAYERS = 1,
})

return RoundConfig
