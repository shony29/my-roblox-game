--!strict
--[[
	WeaponRemotes: the weapon system's remotes, by short name.
	They live in the central list in Shared/Net/Net.luau; this file just
	groups them so weapon code can write `remotes.Fire`.

	  Fire       client -> server  (weaponId, origin, direction)
	  Equip      client -> server  (weaponId)
	  Reload     client -> server  ()
	  State      server -> client  (weaponId, ammo, reloading)
	  HitConfirm server -> client  (damage, killed, headshot)
	  ShotFx     server -> others  (shooter, weaponId, origin, endPoints)
]]

local Net = require(script.Parent:WaitForChild("Net"))

export type Remotes = {
	Fire: RemoteEvent,
	Equip: RemoteEvent,
	Reload: RemoteEvent,
	State: RemoteEvent,
	HitConfirm: RemoteEvent,
	ShotFx: RemoteEvent,
}

local cached: Remotes? = nil

local WeaponRemotes = {}

function WeaponRemotes.get(): Remotes
	if cached then
		return cached
	end
	local remotes: Remotes = {
		Fire = Net.event("WeaponFire"),
		Equip = Net.event("WeaponEquip"),
		Reload = Net.event("WeaponReload"),
		State = Net.event("WeaponState"),
		HitConfirm = Net.event("WeaponHitConfirm"),
		ShotFx = Net.event("WeaponShotFx"),
	}
	cached = remotes
	return remotes
end

return WeaponRemotes
