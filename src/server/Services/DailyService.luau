--!strict
--[[
	DailyService: the Daily Squishy. Once every 24 hours a player can burst
	the squishy in the lobby and gets a new item.

	The client only asks "can I have my daily?" (the tapping and the burst
	are just animation). The server checks the player's data is loaded and
	the 24 hours have passed (PlayerDataService.tryClaimDaily, which can't
	be claimed twice), then picks the prize itself:
	  * first a rarity is rolled: 40% Common, 30% Uncommon, 20% Rare,
	    8% Epic, 2% Legendary (Config/ShopConfig.Rarities),
	  * then a random item of that rarity they don't own yet (a colour,
	    squishy, skin, topping or gun), added to their items for free;
	  * or, if they already own everything, 150 coins.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local Net = require(ReplicatedStorage.Shared.Net.Net)
local RateLimiter = require(script.Parent.Parent.Components.RateLimiter)
local PlayerDataService = require(script.Parent.PlayerDataService)

type Category = ShopConfig.Category

local FALLBACK_COINS = 150

local DailyService = {}

local random = Random.new()
local limiter = RateLimiter.new(1, 2) -- one claim attempt per 2 seconds
local started = false

local CATEGORIES: { Category } = { "Color", "Hat", "Skin", "Weapon", "Topping" }

local function itemsIn(category: Category): { { Id: string, Price: number, Robux: number? } }
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

-- Every coin item the player doesn't own yet, grouped by rarity name.
local function unownedByRarity(player: Player): { [string]: { ShopConfig.ShopItem } }
	local groups: { [string]: { ShopConfig.ShopItem } } = {}
	for _, category in CATEGORIES do
		for _, raw in itemsIn(category) do
			local item = ShopConfig.getItem(raw.Id)
			-- Coin items only: Robux (themed) and free items are never given away.
			if item and item.Price > 0 and item.Robux == nil and not PlayerDataService.ownsItem(player, item.Id) then
				local rarity = ShopConfig.rarityOf(item).Name
				groups[rarity] = groups[rarity] or {}
				table.insert(groups[rarity], item)
			end
		end
	end
	return groups
end

--[[
	Rolls a rarity (40% Common, 30% Uncommon, 20% Rare, 8% Epic, 2% Legendary,
	from ShopConfig.Rarities), then picks an unowned item of that rarity. If
	they own every item of that rarity, the nearest rarity that still has
	something (lower first) is used. Returns nil if they own everything.
]]
local function pickItem(player: Player): ShopConfig.ShopItem?
	local groups = unownedByRarity(player)
	local roll = random:NextNumber(0, 100)
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

	local item = pickItem(player)
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
