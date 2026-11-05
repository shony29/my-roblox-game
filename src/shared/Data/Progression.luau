--!strict
--[[
	Progression: experience (XP) and levels. Pure maths, used by the server
	(to award XP) and the client (to show your level).

	  * Every match: 50 XP, plus 15 per elimination, plus 100 for a win.
	  * Level n -> n+1 needs 250 + 50 x (n - 1) XP, so each level takes a
	    little longer than the last.
	Only the total XP is saved; the level is worked out from it.
]]

local Progression = {}

Progression.XP_PER_MATCH = 50
Progression.XP_PER_ELIMINATION = 15
Progression.XP_PER_WIN = 100
Progression.MAX_LEVEL = 999

function Progression.xpForLevel(level: number): number
	return 250 + 50 * (level - 1)
end

-- Returns (level, XP earned inside this level, XP needed for the next level).
function Progression.levelFromXp(totalXp: number): (number, number, number)
	local level = 1
	local remaining = math.max(0, math.floor(totalXp))
	while level < Progression.MAX_LEVEL and remaining >= Progression.xpForLevel(level) do
		remaining -= Progression.xpForLevel(level)
		level += 1
	end
	return level, remaining, Progression.xpForLevel(level)
end

function Progression.matchXp(eliminations: number, won: boolean): number
	return Progression.XP_PER_MATCH
		+ eliminations * Progression.XP_PER_ELIMINATION
		+ (if won then Progression.XP_PER_WIN else 0)
end

return Progression
