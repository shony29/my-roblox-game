--!strict
--[[
	WeaponConfig: every weapon number lives here.

	Want the rifle to shoot faster or the sniper to reload slower? Change the
	numbers below and press Play. The server and the client both read this
	file, so they always agree.

	Quick guide to the fields:
	  Damage              damage per bullet (per pellet for the shotgun)
	  HeadshotMultiplier  damage is multiplied by this on a head hit
	  FireRate            shots per second
	  Automatic           true = hold the mouse button to keep firing
	  Pellets             bullets per trigger pull (shotgun > 1)
	  Spread              how far bullets can wobble from the crosshair, in degrees
	  MaxRange            how far a bullet can travel, in studs
	  FalloffStart        damage starts dropping after this many studs
	  FalloffMinMultiplier  share of damage left at MaxRange (0.4 = 40%)
	  MagazineSize        bullets before you must reload
	  ReserveAmmo         spare bullets for reloading (refilled on respawn)
	  ReloadTime          seconds a reload takes
	  RecoilKick          degrees the view kicks up per shot
]]

export type WeaponStats = {
	Id: string,
	DisplayName: string,
	Damage: number,
	HeadshotMultiplier: number,
	FireRate: number,
	Automatic: boolean,
	Pellets: number,
	Spread: number,
	MaxRange: number,
	FalloffStart: number,
	FalloffMinMultiplier: number,
	MagazineSize: number,
	ReserveAmmo: number, -- spare bullets carried (refilled on respawn)
	ReloadTime: number,
	RecoilKick: number, -- degrees the view kicks up per shot (recovers by itself)

	-- Looks and sound
	TracerColor: Color3,
	TracerWidth: number,
	GunColor: Color3,
	GunLength: number,
	-- Leave "" for no shot sound, or paste a sound id like "rbxassetid://123456".
	FireSoundId: string,
}

local Weapons: { [string]: WeaponStats } = {
	-- Fast automatic rifle: steady, reliable, good at any range.
	Rifle = {
		Id = "Rifle",
		DisplayName = "Auto Rifle",
		Damage = 18,
		HeadshotMultiplier = 1.5,
		FireRate = 10,
		Automatic = true,
		Pellets = 1,
		Spread = 1.2,
		MaxRange = 300,
		FalloffStart = 120,
		FalloffMinMultiplier = 0.7,
		MagazineSize = 30,
		ReserveAmmo = 90,
		ReloadTime = 1.8,
		RecoilKick = 0.55,

		TracerColor = Color3.fromRGB(255, 230, 120),
		TracerWidth = 0.08,
		GunColor = Color3.fromRGB(80, 170, 255),
		GunLength = 2.2,
		FireSoundId = "",
	},

	-- Punchy shotgun: a cloud of pellets, brutal up close, weak far away.
	Shotgun = {
		Id = "Shotgun",
		DisplayName = "Pump Shotgun",
		Damage = 13,
		HeadshotMultiplier = 1.25,
		FireRate = 1.2,
		Automatic = false,
		Pellets = 8,
		Spread = 7,
		MaxRange = 90,
		FalloffStart = 20,
		FalloffMinMultiplier = 0.3,
		MagazineSize = 6,
		ReserveAmmo = 24,
		ReloadTime = 2.2,
		RecoilKick = 2.8,

		TracerColor = Color3.fromRGB(255, 170, 80),
		TracerWidth = 0.06,
		GunColor = Color3.fromRGB(255, 120, 90),
		GunLength = 1.8,
		FireSoundId = "",
	},

	-- One-shot sniper: slow and precise. A body hit removes all 100 health.
	Sniper = {
		Id = "Sniper",
		DisplayName = "Sniper",
		Damage = 100,
		HeadshotMultiplier = 1,
		FireRate = 0.8,
		Automatic = false,
		Pellets = 1,
		Spread = 0,
		MaxRange = 1000,
		FalloffStart = 1000,
		FalloffMinMultiplier = 1,
		MagazineSize = 5,
		ReserveAmmo = 15,
		ReloadTime = 2.6,
		RecoilKick = 3.5,

		TracerColor = Color3.fromRGB(140, 255, 255),
		TracerWidth = 0.14,
		GunColor = Color3.fromRGB(140, 230, 120),
		GunLength = 3.2,
		FireSoundId = "",
	},
}

local WeaponConfig = {
	Weapons = Weapons,

	-- Which weapon sits on keys 1, 2 and 3. The first one is equipped on spawn.
	Order = { "Rifle", "Shotgun", "Sniper" } :: { string },

	-- Seconds after swapping before you can shoot. Small = snappy swaps.
	SwapTime = 0.15,

	-- Played on the shooter's screen when the server confirms a hit.
	HitSoundId = "rbxasset://sounds/electronicpingshort.wav",

	-- Anti-cheat tuning (server only). See WeaponService for details.
	-- How far (studs) the shot's start point may be from the shooter's head.
	-- 10 leaves room for lag while dashing (85 studs/s * 0.1 s = 8.5 studs).
	MaxOriginOffset = 10,
	-- Allow shots slightly faster than FireRate, because internet lag can
	-- bunch messages together. 0.75 means "at least 75% of the normal gap".
	FireRateTolerance = 0.75,
}

function WeaponConfig.get(weaponId: string): WeaponStats?
	return Weapons[weaponId]
end

return WeaponConfig
