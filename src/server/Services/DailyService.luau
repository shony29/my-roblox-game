--!strict
--[[
	DailyService: the Daily Squishy. Once every 24 hours a player can burst
	the squishy in the lobby and gets a new item.

	The client only asks "can I have my daily?" (the tapping and the burst
	are just animation). The server checks the player's data is loaded and
	the 24 hours have passed (PlayerDataService.tryClaimDaily, which can't
	be claimed twice), then picks the prize itself:
	  * a random item they don't own yet: a colour, hat, skin or gun
	    (guns are rarer), added to their items for free;
	  * or, if they already own everything, 150 coins.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local Net = require(ReplicatedStorage.Shared.Net.Net)
local RateLimiter = require(script.Parent.Parent.Components.RateLimiter)
local PlayerDataService = require(script.Parent.PlayerDataService)

type Category = ShopConfig.Category

-- How likely each kind of prize is (guns are rarer).
local CATEGORY_WEIGHTS: { { category: Category, weight: number } } = {
	{ category = "Color", weight = 35 },
	{ category = "Hat", weight = 25 },
	{ category = "Skin", weight = 25 },
	{ category = "Weapon", weight = 15 },
}
local FALLBACK_COINS = 150

local DailyService = {}

local random = Random.new()
local limiter = RateLimiter.new(1, 2) -- one claim attempt per 2 seconds
local started = false

local function itemsIn(category: Category): { { Id: string, Price: number } }
	if category == "Color" then
		return ShopConfig.Colors :: any
	elseif category == "Hat" then
		return ShopConfig.Hats :: any
	elseif category == "Skin" then
		return ShopConfig.Skins :: any
	end
	return ShopConfig.Weapons :: any
end

-- Picks a prize the player doesn't own yet, or nil if they own everything.
local function pickItem(player: Player): ShopConfig.ShopItem?
	local choices: { { category: Category, weight: number, ids: { string } } } = {}
	local total = 0
	for _, entry in CATEGORY_WEIGHTS do
		local ids: { string } = {}
		for _, item in itemsIn(entry.category) do
			if item.Price > 0 and not PlayerDataService.ownsItem(player, item.Id) then
				table.insert(ids, item.Id)
			end
		end
		if #ids > 0 then
			table.insert(choices, { category = entry.category, weight = entry.weight, ids = ids })
			total += entry.weight
		end
	end
	if total == 0 then
		return nil
	end
	local roll = random:NextNumber(0, total)
	for _, choice in choices do
		roll -= choice.weight
		if roll <= 0 or choice == choices[#choices] then
			return ShopConfig.getItem(choice.ids[random:NextInteger(1, #choice.ids)])
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
		return { ok = true, kind = "Item", itemId = item.Id, displayName = item.DisplayName, category = item.Category }
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
