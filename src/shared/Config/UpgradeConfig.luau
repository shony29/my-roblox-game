--!strict
--[[
	UpgradeConfig: gun upgrade levels.

	Each gun goes from level 1 (red) up to level 6 (purple). Get them by
	buying them in the shop (Guns tab: the UPGRADE button on a gun you own)
	or as Daily Squishy prizes (higher levels are rarer). Upgrades are
	COSMETIC: they change the gun's colour (and add a glow from level 4),
	never its damage, so matches stay fair.

	Upgrade prices: the first upgrade costs more than the gun itself
	(FIRST_UPGRADE x its price; the free guns count as FREE_GUN_VALUE), and
	every level after that costs GROWTH times the one before.
]]

export type Tier = { Level: number, Name: string, Color: Color3, Rarity: string }

local rgb = Color3.fromRGB

local UpgradeConfig = {}

UpgradeConfig.MAX_LEVEL = 6
UpgradeConfig.GLOW_FROM_LEVEL = 4

UpgradeConfig.FIRST_UPGRADE = 1.5 -- the first upgrade costs 1.5x the gun's price
UpgradeConfig.GROWTH = 1.6 -- each level costs 1.6x the level before
UpgradeConfig.FREE_GUN_VALUE = 100 -- what the free guns count as for upgrade prices

UpgradeConfig.Tiers = {
	{ Level = 1, Name = "Red", Color = rgb(235, 60, 60), Rarity = "Common" },
	{ Level = 2, Name = "Orange", Color = rgb(255, 140, 40), Rarity = "Common" },
	{ Level = 3, Name = "Yellow", Color = rgb(255, 220, 50), Rarity = "Uncommon" },
	{ Level = 4, Name = "Green", Color = rgb(80, 210, 90), Rarity = "Rare" },
	{ Level = 5, Name = "Blue", Color = rgb(70, 140, 255), Rarity = "Epic" },
	{ Level = 6, Name = "Purple", Color = rgb(170, 80, 255), Rarity = "Legendary" },
} :: { Tier }

function UpgradeConfig.tier(level: number): Tier?
	return UpgradeConfig.Tiers[level]
end

-- The coin price of upgrading a gun (shop price `gunPrice`) to `nextLevel`.
-- Rounded to a tidy number; always more than the level before.
function UpgradeConfig.cost(gunPrice: number, nextLevel: number): number
	local base = math.max(gunPrice, UpgradeConfig.FREE_GUN_VALUE) * UpgradeConfig.FIRST_UPGRADE
	local raw = base * UpgradeConfig.GROWTH ^ (math.max(nextLevel, 1) - 1)
	local step = if raw < 1000 then 10 elseif raw < 10000 then 50 else 500
	return math.floor(raw / step + 0.5) * step
end

-- Gun levels travel to clients as a short text, e.g. "Rifle=2,SMG=1".
function UpgradeConfig.format(levels: { [string]: number }): string
	local parts: { string } = {}
	for weaponId, level in levels do
		table.insert(parts, `{weaponId}={level}`)
	end
	table.sort(parts)
	return table.concat(parts, ",")
end

function UpgradeConfig.parse(text: unknown): { [string]: number }
	local levels: { [string]: number } = {}
	if typeof(text) ~= "string" then
		return levels
	end
	for _, pair in string.split(text, ",") do
		local weaponId, level = string.match(pair, "^(%w+)=(%d+)$")
		if weaponId and level then
			levels[weaponId] = math.clamp(tonumber(level) or 0, 0, UpgradeConfig.MAX_LEVEL)
		end
	end
	return levels
end

return UpgradeConfig
