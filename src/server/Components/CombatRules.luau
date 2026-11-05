--!strict
--[[
	CombatRules: one place that decides WHEN shooting is allowed and WHO can
	be hurt. WeaponService asks these questions; MatchService answers them by
	calling CombatRules.setRules when a match starts and ends.

	Default (no match running): nobody can fire. That keeps lobbies safe and
	stops shooting during countdowns, round ends and results screens.
]]

export type CanFire = (shooter: Player) -> boolean
-- `victim` is nil for non-player targets (e.g. practice dummies).
export type CanDamage = (attacker: Player, victim: Player?, victimModel: Model?) -> boolean
export type DamageListener = (attacker: Player, victim: Player?, amount: number) -> ()

local function never(_shooter: Player): boolean
	return false
end

local canFireRule: CanFire = never
local canDamageRule: CanDamage = function(_attacker: Player, _victim: Player?, _victimModel: Model?): boolean
	return false
end
local damageListeners: { DamageListener } = {}

local CombatRules = {}

function CombatRules.setRules(canFire: CanFire, canDamage: CanDamage)
	canFireRule = canFire
	canDamageRule = canDamage
end

-- Back to the safe default: nobody can fire or be hurt.
function CombatRules.reset()
	canFireRule = never
	canDamageRule = function(_attacker: Player, _victim: Player?, _victimModel: Model?): boolean
		return false
	end
end

function CombatRules.canFire(shooter: Player): boolean
	return canFireRule(shooter)
end

-- `victimModel` is the character that was hit (lets bots be checked by team).
function CombatRules.canDamage(attacker: Player, victim: Player?, victimModel: Model?): boolean
	return canDamageRule(attacker, victim, victimModel)
end

-- WeaponService calls this after dealing damage (for match statistics).
function CombatRules.reportDamage(attacker: Player, victim: Player?, amount: number)
	for _, listener in damageListeners do
		task.spawn(listener, attacker, victim, amount)
	end
end

function CombatRules.onDamage(listener: DamageListener)
	table.insert(damageListeners, listener)
end

return CombatRules
