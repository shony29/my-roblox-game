--!strict
--[[
	RobuxShopConfig
	===============
	Everything in the shop's ROBUX tab:

	  * COIN PACKS: coins for Robux. Bigger packs give more coins per Robux.
	  * BUNDLES: several things at once, cheaper than buying them one by one.
	      Monthly Collection  all four of this month's themed items
	                          (blob colour, squishy, gun skin, charm packet)
	      Coin Rush           a pile of coins plus this month's gun skin
	                          and charm packet
	    Bundles always contain THIS month's themed items. Items the player
	    already owns are skipped (the rest still arrives).

	To put them on sale: publish the game, create one Developer Product per
	pack and bundle on the Creator Dashboard (Monetization -> Developer
	Products) with the same Robux price as below, then paste each product's
	id into ShopConfig.ProductIds, e.g. ["Coins_Jar"] = 1234567890.
	Without an id the button shows SOON.
]]

local ShopConfig = require(script.Parent:WaitForChild("ShopConfig"))

export type CoinPack = {
	Id: string,
	DisplayName: string,
	Coins: number,
	Robux: number,
	Badge: string?, -- a small ribbon such as "+20% BONUS"
}

export type ThemedPart = "Color" | "Squishy" | "Skin" | "Topping"

export type Bundle = {
	Id: string,
	DisplayName: string,
	Robux: number,
	Coins: number,
	Themed: { ThemedPart }, -- which of this month's themed items it includes
}

local RobuxShopConfig = {}

RobuxShopConfig.CoinPacks = {
	{ Id = "Coins_Pouch", DisplayName = "Pouch of Coins", Coins = 250, Robux = 49 },
	{ Id = "Coins_Jar", DisplayName = "Jar of Coins", Coins = 600, Robux = 99, Badge = "+20% BONUS" },
	{ Id = "Coins_Bucket", DisplayName = "Bucket of Coins", Coins = 1500, Robux = 199, Badge = "+50% BONUS" },
	{ Id = "Coins_Vault", DisplayName = "Vault of Coins", Coins = 5000, Robux = 499, Badge = "BEST VALUE" },
} :: { CoinPack }

RobuxShopConfig.Bundles = {
	{ Id = "Bundle_Monthly", DisplayName = "Monthly Collection", Robux = 249, Coins = 0, Themed = { "Color", "Squishy", "Skin", "Topping" } },
	{ Id = "Bundle_CoinRush", DisplayName = "Coin Rush", Robux = 349, Coins = 2000, Themed = { "Skin", "Topping" } },
} :: { Bundle }

-- What the parts of a monthly set are called (and their shop category).
local PART_CATEGORY: { [ThemedPart]: string } = { Color = "Color", Squishy = "Hat", Skin = "Skin", Topping = "Topping" }
RobuxShopConfig.PART_NAMES = { Color = "Blob colour", Squishy = "Squishy", Skin = "Gun skin", Topping = "Charm packet" }

-- The theme on sale in `month` (1-12), if any.
function RobuxShopConfig.themeFor(month: number): ShopConfig.Theme?
	for _, theme in ShopConfig.Themes do
		if theme.Month == month then
			return theme
		end
	end
	return nil
end

--[[
	What a bundle holds in `month`: the item Ids, the coins, and what it
	would cost bought one by one (in Robux; coins valued at the Pouch's rate).
]]
function RobuxShopConfig.bundleContents(bundle: Bundle, month: number): ({ string }, number, number)
	local itemIds: { string } = {}
	local worth = 0
	local theme = RobuxShopConfig.themeFor(month)
	if theme then
		for _, part in bundle.Themed do
			local item = ShopConfig.getItem(`Theme_{theme.Key}_{part}`)
			if item then
				table.insert(itemIds, item.Id)
				worth += item.Robux or (ShopConfig.RobuxPrices :: any)[PART_CATEGORY[part]] or 0
			end
		end
	end
	local pouch = RobuxShopConfig.CoinPacks[1]
	worth += math.floor(bundle.Coins * pouch.Robux / pouch.Coins + 0.5)
	return itemIds, bundle.Coins, worth
end

-- The developer product id for a pack or bundle (0 = not on sale yet).
function RobuxShopConfig.productId(id: string): number
	return ShopConfig.ProductIds[id] or 0
end

-- Which pack or bundle a developer product is (nil if it is neither).
function RobuxShopConfig.fromProductId(productId: number): (CoinPack?, Bundle?)
	for _, pack in RobuxShopConfig.CoinPacks do
		if RobuxShopConfig.productId(pack.Id) == productId then
			return pack, nil
		end
	end
	for _, bundle in RobuxShopConfig.Bundles do
		if RobuxShopConfig.productId(bundle.Id) == productId then
			return nil, bundle
		end
	end
	return nil, nil
end

return RobuxShopConfig
