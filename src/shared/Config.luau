--!strict
--[[
	Config
	Every number that controls how the game *feels* lives here, so you can
	tweak the game without hunting through code. Both the server and the
	client read this file.

	Tip: change a value, save, and Rojo will sync it into Studio instantly.
]]

local Config = {
	Movement = {
		WalkSpeed = 28, -- Roblox default is 16, so this is nice and zippy
		JumpPower = 55, -- Roblox default is 50
		DoubleJumpPower = 60, -- upward speed given by the mid-air jump
		MaxAirJumps = 1, -- 1 = double jump, 2 = triple jump, ...
		DashSpeed = 95, -- sideways speed during a dash
		DashDuration = 0.18, -- seconds the dash push lasts
		DashCooldown = 1.1, -- seconds before you can dash again
		LaunchPadPower = 110, -- upward speed from the bouncy pads in the arena
	},

	Weapon = {
		Name = "Splat Blaster",
		Damage = 25, -- 4 hits to splat a full-health jelly
		FireInterval = 0.11, -- seconds between shots (about 9 shots per second)
		MagazineSize = 24,
		ReloadTime = 1.2,
		Range = 350, -- studs

		-- Anti-cheat: how far (in studs) the client's reported muzzle position
		-- may be from where the server thinks the player's head is. A bit of
		-- slack is needed because the server sees fast players slightly late.
		MaxOriginDistance = 10,
	},

	Player = {
		MaxHealth = 100,
		RespawnTime = 0, -- seconds. 0 = straight back into the action!
		SpawnProtection = 1.5, -- seconds of force field after spawning (ends early if you shoot)
	},

	Rewards = {
		CoinsPerKill = 10,
	},
}

return Config
