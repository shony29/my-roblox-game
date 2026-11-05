--!strict
--[[
	PlayerDataSchema
	================
	Describes what we save for every player, and how to clean up
	old or damaged saves so they always match the current shape.

	If you ever add a new field:
	  1. Add it to the PlayerData type and to Schema.default().
	  2. Bump Schema.VERSION.
	  3. Handle the old version inside Schema.reconcile().
]]

export type PlayerData = {
	schemaVersion: number,
	eliminations: number, -- lifetime eliminations
	wins: number, -- lifetime round wins
	coins: number, -- spendable coins
}

local Schema = {}

Schema.VERSION = 1

-- How many coins a player earns for each elimination.
Schema.COINS_PER_ELIMINATION = 5

-- Safety cap so a bug can never write an absurd number into a save.
Schema.MAX_STAT_VALUE = 1_000_000_000

function Schema.default(): PlayerData
	return {
		schemaVersion = Schema.VERSION,
		eliminations = 0,
		wins = 0,
		coins = 0,
	}
end

-- Turns any value into a whole, non-negative, capped number.
local function cleanNumber(value: unknown): number
	if typeof(value) ~= "number" then
		return 0
	end
	-- NaN check (NaN is the only value not equal to itself) and infinity check
	if value ~= value or value == math.huge or value == -math.huge then
		return 0
	end
	return math.clamp(math.floor(value), 0, Schema.MAX_STAT_VALUE)
end

--[[
	Takes whatever came out of the DataStore (could be nil, an old
	version, or something broken) and returns a clean PlayerData.
]]
function Schema.reconcile(raw: unknown): PlayerData
	local data = Schema.default()
	if typeof(raw) ~= "table" then
		return data
	end
	local source = raw :: { [string]: unknown }

	-- Future migrations go here, for example:
	-- if (source.schemaVersion or 0) < 2 then ... end

	data.eliminations = cleanNumber(source.eliminations)
	data.wins = cleanNumber(source.wins)
	data.coins = cleanNumber(source.coins)
	data.schemaVersion = Schema.VERSION
	return data
end

function Schema.copy(data: PlayerData): PlayerData
	return {
		schemaVersion = data.schemaVersion,
		eliminations = data.eliminations,
		wins = data.wins,
		coins = data.coins,
	}
end

return Schema
