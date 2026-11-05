--!strict
-- SpawnConfig: how players are placed when a round starts or they respawn.
-- (Round rules such as round length now live in Config/ModeConfig.)

local SpawnConfig = table.freeze({
	-- How long you are protected after spawning, in seconds.
	SPAWN_PROTECTION = 2,

	-- How many of the "safest" spawn points to pick from at random,
	-- so spawns stay away from enemies but are not totally predictable.
	SAFE_SPAWN_CHOICES = 3,

	-- Random nudge (studs) so teammates sharing a spawn pad don't stack.
	SPAWN_SPREAD = 2.5,

	-- Seconds to wait for every player's character to load before a round.
	LOAD_TIMEOUT = 8,
})

return SpawnConfig
