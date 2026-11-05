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

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ShopConfig"))

-- Which shop item the player is wearing in each slot.
export type EquippedItems = {
	Color: string,
	Hat: string,
	Skin: string,
	Topping: string, -- kill effect
}

export type PlayerData = {
	schemaVersion: number,
	eliminations: number, -- lifetime eliminations
	wins: number, -- lifetime round wins
	coins: number, -- spendable coins
	xp: number, -- total experience (the level is worked out from this, see Data/Progression)
	lastDailyAt: number, -- os.time() of the last Daily Squishy claim (0 = never)
	receipts: { string }, -- Robux purchases already granted (so one is never granted twice)
	gunLevels: { [string]: number }, -- weapon Id -> upgrade level 0-6 (cosmetic colour)
	ownedItems: { string }, -- shop item Ids the player bought (free items are always owned)
	equippedItems: EquippedItems, -- shop items the player is wearing
}

local Schema = {}

Schema.VERSION = 6 -- 2: shop items. 3: xp. 4: lastDailyAt. 5: toppings and Robux receipts. 6: gun levels

-- How many coins a player earns for each elimination.
Schema.COINS_PER_ELIMINATION = 5

-- Safety cap so a bug can never write an absurd number into a save.
Schema.MAX_STAT_VALUE = 1_000_000_000

-- Safety limits for the shop lists in a save.
Schema.MAX_OWNED_ITEMS = 500
Schema.MAX_ITEM_ID_LENGTH = 64

function Schema.default(): PlayerData
	return {
		schemaVersion = Schema.VERSION,
		eliminations = 0,
		wins = 0,
		coins = 0,
		xp = 0,
		lastDailyAt = 0,
		receipts = {},
		gunLevels = {},
		ownedItems = {},
		equippedItems = {
			Color = ShopConfig.Defaults.Color,
			Hat = ShopConfig.Defaults.Hat,
			Skin = ShopConfig.Defaults.Skin,
			Topping = ShopConfig.Defaults.Topping,
		},
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

-- Keeps only sensible item Ids: strings, not too long, no repeats.
-- Unknown Ids are kept, so an item that is removed and added back later
-- is still owned.
local function cleanOwnedItems(value: unknown): { string }
	local result: { string } = {}
	if typeof(value) ~= "table" then
		return result
	end
	local seen: { [string]: boolean } = {}
	for _, id in value :: { unknown } do
		if #result >= Schema.MAX_OWNED_ITEMS then
			break
		end
		if typeof(id) == "string" and #id > 0 and #id <= Schema.MAX_ITEM_ID_LENGTH and not seen[id] then
			seen[id] = true
			table.insert(result, id)
		end
	end
	return result
end

-- An equipped item must exist, be in the right category, and be owned
-- (or free). Anything else goes back to the default item.
local function cleanEquipped(value: unknown, category: ShopConfig.Category, owned: { string }): string
	if typeof(value) == "string" then
		local item = ShopConfig.getItem(value)
		if item and item.Category == category and (item.Price <= 0 or table.find(owned, value) ~= nil) then
			return value
		end
	end
	return ShopConfig.defaultFor(category)
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
	data.xp = cleanNumber(source.xp) -- version 1-2 saves have no xp, so they start at 0
	data.lastDailyAt = cleanNumber(source.lastDailyAt) -- older saves: never claimed
	-- Version 1 saves have no shop fields; they get the free defaults.
	data.ownedItems = cleanOwnedItems(source.ownedItems)
	local equipped: { [string]: unknown } = if typeof(source.equippedItems) == "table"
		then source.equippedItems :: { [string]: unknown }
		else {}
	data.equippedItems = {
		Color = cleanEquipped(equipped.Color, "Color", data.ownedItems),
		Hat = cleanEquipped(equipped.Hat, "Hat", data.ownedItems),
		Skin = cleanEquipped(equipped.Skin, "Skin", data.ownedItems),
		Topping = cleanEquipped(equipped.Topping, "Topping", data.ownedItems), -- older saves: the default
	}
	-- Receipts: keep the newest 100 purchase ids (plenty to catch a retried purchase).
	local receipts: { string } = {}
	if typeof(source.receipts) == "table" then
		for _, id in source.receipts :: { unknown } do
			if typeof(id) == "string" and #id <= 100 then
				table.insert(receipts, id)
			end
		end
	end
	while #receipts > 100 do
		table.remove(receipts, 1)
	end
	data.receipts = receipts
	-- Gun upgrade levels: short weapon Ids with whole levels 0-6 (older saves: none).
	local gunLevels: { [string]: number } = {}
	if typeof(source.gunLevels) == "table" then
		for weaponId, level in source.gunLevels :: { [unknown]: unknown } do
			if typeof(weaponId) == "string" and #weaponId <= 24 and typeof(level) == "number" and level == level then
				gunLevels[weaponId] = math.clamp(math.floor(level), 0, 6)
			end
		end
	end
	data.gunLevels = gunLevels
	data.schemaVersion = Schema.VERSION
	return data
end

function Schema.copy(data: PlayerData): PlayerData
	return {
		schemaVersion = data.schemaVersion,
		eliminations = data.eliminations,
		wins = data.wins,
		coins = data.coins,
		xp = data.xp,
		lastDailyAt = data.lastDailyAt,
		receipts = table.clone(data.receipts),
		gunLevels = table.clone(data.gunLevels),
		-- New tables, so a save snapshot never changes while it is being written.
		ownedItems = table.clone(data.ownedItems),
		equippedItems = {
			Color = data.equippedItems.Color,
			Hat = data.equippedItems.Hat,
			Skin = data.equippedItems.Skin,
			Topping = data.equippedItems.Topping,
		},
	}
end

return Schema
