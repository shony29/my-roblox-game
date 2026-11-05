--!strict
--[[
	CameraConfig: first-person camera feel.

	Gameplay-critical aim (where you point) is never smoothed. These values
	only control cosmetic effects layered on top (bob, landing dip, recoil
	kick), which always return to zero.
]]

local CameraConfig = table.freeze({
	FieldOfView = 70, -- normal field of view (players can change it in Settings later)
	SprintFovBoost = 6, -- extra field of view while sprinting
	DashFovBoost = 12, -- extra field of view during a dash
	FovLerpSpeed = 12, -- how quickly the field of view eases between values

	MouseSensitivity = 1, -- multiplier on Roblox's own sensitivity setting
	ControllerSensitivity = 1,

	-- Head bob (cosmetic, studs). Kept small so it never hurts aiming.
	WalkBobAmount = 0.05,
	SprintBobAmount = 0.09,
	BobSpeed = 9, -- bob cycles per second at sprint speed

	-- Landing dip (cosmetic): how far the view dips per stud/s of fall speed.
	LandingDipPerSpeed = 0.006,
	MaxLandingDip = 0.35,
	LandingRecoverySpeed = 10,

	-- Recoil kick recovery: how fast the view returns after a shot.
	RecoilRecoverySpeed = 14,
})

return CameraConfig
