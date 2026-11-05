--!strict
--[[
	HitGroups: decides what a bullet can hit.

	Players look like blobs, but underneath there is still a normal (invisible)
	Roblox body that does the walking. Without this file, bullets would hit
	that invisible body, including an invisible head floating above the blob,
	and pass straight through the blob you can actually see.

	So we use two collision groups:
	  * HiddenBody: the invisible Roblox body parts. They still touch the floor
	    and walls normally, but weapon raycasts ignore them.
	  * WeaponRay: the group every weapon raycast uses.
	The visible blob body (CanQuery = true) is what bullets hit instead.
]]

local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")

local HitGroups = {}

HitGroups.HIDDEN_BODY = "HiddenBody"
HitGroups.WEAPON_RAY = "WeaponRay"

-- Hits on the top part of a blob count as headshots. 0.2 means "the part of
-- the blob more than 20% of its height above its middle".
HitGroups.BLOB_HEADSHOT_FRACTION = 0.2

local ready = false

-- Server only. Safe to call many times, from any script.
function HitGroups.setup()
	if ready then
		return
	end
	assert(RunService:IsServer(), "HitGroups.setup() must be called on the server")
	for _, name in { HitGroups.HIDDEN_BODY, HitGroups.WEAPON_RAY } do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end
	PhysicsService:CollisionGroupSetCollidable(HitGroups.WEAPON_RAY, HitGroups.HIDDEN_BODY, false)
	ready = true
end

-- Makes a RaycastParams that ignores `ignore` and the hidden body parts.
function HitGroups.weaponRayParams(ignore: { Instance }): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	-- On a client the groups arrive from the server a moment after joining,
	-- so only use the group once it exists (using a missing one errors).
	if PhysicsService:IsCollisionGroupRegistered(HitGroups.WEAPON_RAY) then
		params.CollisionGroup = HitGroups.WEAPON_RAY
	end
	return params
end

return HitGroups
