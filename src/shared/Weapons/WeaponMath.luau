--!strict
--[[
	WeaponMath: small math helpers shared by the server and the client.
	No game state here, just "numbers in, numbers out".
]]

local WeaponConfig = require(script.Parent.WeaponConfig)

type WeaponStats = WeaponConfig.WeaponStats

local WeaponMath = {}

-- True when every part of the vector is a normal number (not NaN or infinite).
-- Cheaters can send strange numbers, so the server checks this first.
function WeaponMath.isFiniteVector(v: Vector3): boolean
	for _, n in { v.X, v.Y, v.Z } do
		if n ~= n or n == math.huge or n == -math.huge then
			return false
		end
	end
	return true
end

-- Turns a straight aim direction into a slightly random one inside a cone.
-- spreadDegrees = 0 means perfectly accurate.
function WeaponMath.applySpread(direction: Vector3, spreadDegrees: number, rng: Random): Vector3
	local unit = direction.Unit
	if spreadDegrees <= 0 then
		return unit
	end
	local aim = CFrame.lookAt(Vector3.zero, unit)
	-- sqrt spreads the bullets evenly across the cone instead of bunching in the middle.
	local tilt = math.rad(spreadDegrees) * math.sqrt(rng:NextNumber())
	local roll = rng:NextNumber() * math.pi * 2
	return (aim * CFrame.Angles(0, 0, roll) * CFrame.Angles(tilt, 0, 0)).LookVector
end

-- Damage for one bullet that travelled `distance` studs.
function WeaponMath.damageAtDistance(stats: WeaponStats, distance: number): number
	if distance <= stats.FalloffStart or stats.MaxRange <= stats.FalloffStart then
		return stats.Damage
	end
	local t = math.clamp((distance - stats.FalloffStart) / (stats.MaxRange - stats.FalloffStart), 0, 1)
	local multiplier = 1 + (stats.FalloffMinMultiplier - 1) * t
	return stats.Damage * multiplier
end

return WeaponMath
