--!strict
--[[
	DailyService: the Daily Squishy. Once every 24 hours a player can burst
	the squishy in the lobby for a prize.

	The client only asks "can I have my daily?" (the tapping and the burst
	are just animation). The server checks the player's data is loaded and
	the 24 hours have passed (PlayerDataService.tryClaimDaily, which can't
	be claimed twice), then picks the prize itself:
	  * first a rarity is rolled, fresh every time (no streaks or pity):
	    40% Common, 30% Uncommon, 20% Rare, 8% Epic, 2% Legendary
	    (Config/ShopConfig.Rarities);
	  * then a random prize of that rarity: an item they don't own yet (a
	    colour, squishy, skin, topping or gun), or a gun upgrade for a gun
	    they own (red -> orange -> yellow -> green -> blue -> purple; higher
	    levels are rarer, see Config/UpgradeConfig);
	  * if they own every item of that rarity, the nearest rarity that still
	    has something is used; if they own everything, they get 150 coins.
	Robux (monthly themed) items are never given away.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local UpgradeConfig = require(ReplicatedStorage.Shared.Config.UpgradeConfig)
local WeaponConfig = require(ReplicatedStorage.Shared.Config.WeaponConfig)
local Net = require(ReplicatedStorage.Shared.Net.Net)
local RateLimiter = require(script.Parent.Parent.Components.RateLimiter)
local PlayerDataService = require(script.Parent.PlayerDataService)

type Category = ShopConfig.Category
type Prize = { item: ShopConfig.ShopItem?, weaponId: string?, level: number? }

local CATEGORIES: { Category } = { "Color", "Hat", "Skin", "Weapon", "Topping" }
local FALLBACK_COINS = 150

local DailyService = {}

local random = Random.new()
local limiter = RateLimiter.new(1, 2) -- one claim attempt per 2 seconds
local started = false

local function itemsIn(category: Category): { { Id: string } }
	if category == "Color" then
		return ShopConfig.Colors :: any
	elseif category == "Hat" then
		return ShopConfig.Hats :: any
	elseif category == "Skin" then
		return ShopConfig.Skins :: any
	elseif category == "Topping" then
		return ShopConfig.Toppings :: any
	end
	return ShopConfig.Weapons :: any
end

-- Every prize the player could win, grouped by rarity name.
local function prizesByRarity(player: Player): { [string]: { Prize } }
	local groups: { [string]: { Prize } } = {}
	local function add(rarity: string, prize: Prize)
		groups[rarity] = groups[rarity] or {}
		table.insert(groups[rarity], prize)
	end
	-- Coin items they don't own yet (never Robux items, never free ones).
	for _, category in CATEGORIES do
		for _, raw in itemsIn(category) do
			local item = ShopConfig.getItem(raw.Id)
			if item and item.Price > 0 and item.Robux == nil and not PlayerDataService.ownsItem(player, item.Id) then
				add(ShopConfig.rarityOf(item).Name, { item = item })
			end
		end
	end
	-- Upgrades for guns they own; the next level decides the rarity.
	for _, weapon in ShopConfig.Weapons do
		if ShopConfig.isFree(weapon.Id) or PlayerDataService.ownsItem(player, weapon.Id) then
			local nextLevel = PlayerDataService.getGunLevel(player, weapon.WeaponId) + 1
			local tier = UpgradeConfig.tier(nextLevel)
			if tier then
				add(tier.Rarity, { weaponId = weapon.WeaponId, level = nextLevel })
			end
		end
	end
	return groups
end

local function pickPrize(player: Player): Prize?
	local groups = prizesByRarity(player)
	local roll = random:NextNumber(0, 100) -- a fresh roll every time
	local rolled = #ShopConfig.Rarities
	for index, rarity in ShopConfig.Rarities do
		roll -= rarity.Chance
		if roll <= 0 then
			rolled = index
			break
		end
	end
	for distance = 0, #ShopConfig.Rarities do
		for _, index in { rolled - distance, rolled + distance } do
			local rarity = ShopConfig.Rarities[index]
			local group = rarity and groups[rarity.Name]
			if group and #group > 0 then
				return group[random:NextInteger(1, #group)]
			end
		end
	end
	return nil
end

local function claim(player: Player): { [string]: any }
	if not limiter:allow(player) then
		return { ok = false, message = "One moment..." }
	end
	if PlayerDataService.getData(player) == nil then
		return { ok = false, message = "Your items are still loading. Try again in a moment!" }
	end
	if not PlayerDataService.tryClaimDaily(player, os.time()) then
		return { ok = false, message = "Your next squishy isn't ready yet." }
	end

	local prize = pickPrize(player)
	local item = prize and prize.item
	if item then
		PlayerDataService.purchaseItem(player, item.Id, 0) -- a free gift: adds it, costs nothing
		PlayerDataService.saveNow(player)
		return {
			ok = true,
			kind = "Item",
			itemId = item.Id,
			displayName = item.DisplayName,
			category = item.Category,
			rarity = ShopConfig.rarityOf(item).Name,
		}
	end
	local weaponId = prize and prize.weaponId
	if weaponId then
		local newLevel = PlayerDataService.upgradeGun(player, weaponId)
		local tier = newLevel and UpgradeConfig.tier(newLevel)
		local stats = WeaponConfig.get(weaponId)
		if newLevel and tier and stats then
			PlayerDataService.saveNow(player)
			return {
				ok = true,
				kind = "Upgrade",
				displayName = `{stats.DisplayName} Lv. {newLevel}`,
				category = "Upgrade",
				rarity = tier.Rarity,
				upgradeColor = tier.Name,
			}
		end
	end
	PlayerDataService.addCoins(player, FALLBACK_COINS)
	PlayerDataService.saveNow(player)
	return { ok = true, kind = "Coins", coins = FALLBACK_COINS, displayName = `{FALLBACK_COINS} coins` }
end

function DailyService.start()
	if started then
		return
	end
	started = true
	Net.func("DailyClaim").OnServerInvoke = function(player: Player)
		if player.Parent ~= Players then
			return { ok = false, message = "" }
		end
		return claim(player)
	end
end

return DailyService
