--!strict
--[[
	MovementConfig
	==============
	Every tuning number for movement and the blob characters lives here.
	Change a value, press Play in Studio, and feel the difference.

	Both the client (what the player feels) and the server (what it allows)
	read from this one file, so they always agree.
]]

local MovementConfig = {
	-- WALKING ------------------------------------------------------------
	-- Roblox characters speed up and stop instantly (no sliding around),
	-- which is the most responsive feel for a competitive shooter.
	WalkSpeed = 20, -- studs per second (normal Roblox is 16)

	-- SPRINT (hold Shift) --------------------------------------------------
	SprintSpeed = 26, -- studs per second while sprinting
	SprintKeys = { Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3 },
	SprintForwardDot = 0.3, -- you must be moving mostly forward to sprint
	SprintShootLockout = 0.35, -- seconds after firing before sprint starts again
	JumpPower = 55, -- upward speed of the first jump (normal Roblox is 50)

	-- DOUBLE JUMP --------------------------------------------------------
	MaxAirJumps = 1, -- extra jumps allowed while in the air
	DoubleJumpPower = 52, -- upward speed of an air jump
	DoubleJumpDelay = 0.12, -- seconds after leaving the ground before an air jump works
	JumpRetapTime = 0.1, -- jump must be released for this long to count as a new press

	-- DASH (Shift) -------------------------------------------------------
	DashKeys = { Enum.KeyCode.Q, Enum.KeyCode.ButtonX }, -- Shift is sprint
	DashSpeed = 85, -- studs per second during the dash
	DashDuration = 0.18, -- seconds the dash lasts (85 * 0.18 is about 15 studs)
	DashCooldown = 1.5, -- seconds before you can dash again

	-- SLIDE (crouch while running) ---------------------------------------
	SlideKeys = { Enum.KeyCode.LeftControl, Enum.KeyCode.C, Enum.KeyCode.ButtonB },
	SlideStartSpeed = 55, -- studs per second at the start of a slide
	SlideEndSpeed = 14, -- studs per second when the slide finishes
	SlideDuration = 0.7, -- seconds a slide lasts
	SlideCooldown = 0.8, -- seconds before you can slide again
	SlideMinSpeed = 18, -- you must be moving at least this fast to slide
	SlideCameraDrop = 1.5, -- how far the camera lowers while sliding

	-- (Camera feel such as field of view now lives in Config/CameraConfig.)

	-- BLOB LOOKS ---------------------------------------------------------
	-- The shape itself is built in server/Components/BlobCharacter.luau.
	BlobBodySize = Vector3.new(4.3, 3.6, 4.1), -- rough blob size (used by the shop preview)
	BlobColorSaturation = 0.5, -- 0 = grey, 1 = very vivid (0.5 = soft candy colours)
	BlobColorBrightness = 0.95, -- 0 = black, 1 = very bright
	BlobHitboxSize = Vector3.new(4.6, 3.8, 4.4), -- the invisible box bullets hit (same for everyone)

	-- SERVER CHECKS (fairness) -------------------------------------------
	-- These keep cheaters from moving faster or higher than the rules allow,
	-- while being forgiving enough that laggy players are not punished.
	CheckInterval = 0.1, -- seconds between server position checks
	SpeedTolerance = 1.35, -- allow 35% over the expected speed (lag wiggle room)
	DistanceSlack = 2.5, -- extra studs allowed per check
	HeightTolerance = 1.25, -- allow 25% over the expected jump height
	HeightSlack = 3, -- extra studs of height allowed
	StrikesBeforeCorrection = 3, -- suspicious checks in a row before snapping back
	ActionGraceTime = 0.35, -- extra seconds a dash/slide speed allowance lasts (lag)
	CooldownLeniency = 0.15, -- seconds a cooldown may be "early" because of lag
	SpawnGraceTime = 1, -- seconds of no checks right after spawning
	MaxRequestsPerSecond = 15, -- ignore players who spam the server faster than this
}

return table.freeze(MovementConfig)
