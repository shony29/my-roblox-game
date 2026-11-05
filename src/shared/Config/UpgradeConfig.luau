--!strict
--[[
	UpgradeConfig: gun upgrade levels won from the Daily Squishy.

	Each gun goes from level 1 (red) up to level 6 (purple). Higher levels
	are rarer Daily Squishy prizes. Upgrades are COSMETIC: they change the
	gun's colour (and add a glow from level 4), never its damage, so matches
	stay fair.
]]

export type Tier = { Level: number, Name: string, Color: Color3, Rarity: string }

local rgb = Color3.fromRGB

local UpgradeConfig = {}

UpgradeConfig.MAX_LEVEL = 6
UpgradeConfig.GLOW_FROM_LEVEL = 4

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
