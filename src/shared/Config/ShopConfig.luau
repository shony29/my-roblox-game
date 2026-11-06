--!strict
--[[
	ShopConfig
	==========
	Every shop item, price and name lives in this one file.
	Everything here is cosmetic only: it changes how you look, never how
	you play.

	Want to add an item? Copy a line in one of the lists below and change it.
	  * Id          A unique name the save file uses. Never change or reuse an
	                Id after players have bought it (DisplayName is fine to change).
	  * DisplayName The name shown in the shop.
	  * Rarity      Common, Uncommon, Rare, Epic or Legendary.
	  * Price       Cost in coins: PRICE.<its rarity>, or 0 for a free item
	                that every player owns.

	RARITY RULES (the shop is organised by these):
	  * Every tab has items of all five rarities, shown Common first and
	    Legendary last (cheapest first inside a rarity).
	  * Every tab has exactly ONE Legendary: the month's themed Robux item,
	    or for guns, the Blob Launcher. (A warning prints if a tab breaks this.)
	  * Prices grow about 3x with each rarity (see PRICE below).
]]

export type Category = "Color" | "Hat" | "Skin" | "Weapon" | "Topping"
export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"

-- What the shop needs to know about any item.
export type ShopItem = {
	Id: string,
	Category: Category,
	DisplayName: string,
	Rarity: Rarity,
	Price: number,
	-- Monthly themed items only (sold for Robux, see MONTHLY THEMES):
	Robux: number?,
	ProductId: number?,
	Month: number?,
	Theme: string?,
}

-- Blob colors
export type ColorItem = {
	Id: string,
	DisplayName: string,
	Rarity: Rarity,
	Price: number,
	Color: Color3,
	Material: Enum.Material, -- SmoothPlastic, or Neon to glow
	Reflectance: number, -- 0 = matte, 0.3 = shiny like metal
	-- Monthly themed items only (sold for Robux, see MONTHLY THEMES):
	Robux: number?,
	ProductId: number?,
	Month: number?,
	Theme: string?,
}

-- Hats. Shape picks which hat HatBuilder makes; the two colors paint it.
-- (Category "Hat" = the Squishies tab: a squishy toy worn on top of the slime.)
export type HatShape = "None" | "Dumpling" | "Butter" | "JellyCube" | "Donut" | "CakeSlice" | "IceCream" | "Popcorn"
export type HatItem = {
	Id: string,
	DisplayName: string,
	Rarity: Rarity,
	Price: number,
	Shape: HatShape,
	MainColor: Color3,
	AccentColor: Color3,
	-- Monthly themed items only (sold for Robux, see MONTHLY THEMES):
	Robux: number?,
	ProductId: number?,
	Month: number?,
	Theme: string?,
}

-- Weapon skins, named after slime ingredients. They repaint a gun's pieces
-- by role (see Cosmetics/GunBuilder): Body = the main colour, Trim = grips,
-- magazines and caps, Accent = small details. A nil colour means "keep the
-- gun's own colour". Pattern adds details (Cosmetics/WeaponSkins).
export type SkinPattern = "None" | "Stripes" | "Spots" | "Line" | "Bubbles" | "Drips"
export type SkinItem = {
	Id: string,
	DisplayName: string,
	Rarity: Rarity,
	Price: number,
	BodyColor: Color3?,
	TrimColor: Color3?,
	AccentColor: Color3?,
	BodyTransparency: number?, -- see-through skins (activator, water)
	BodyMaterial: Enum.Material,
	TrimMaterial: Enum.Material,
	Reflectance: number,
	Pattern: SkinPattern, -- extra decoration added on the gun body
	PatternColors: { Color3 },
	PatternMaterial: Enum.Material,
	-- Monthly themed items only (sold for Robux, see MONTHLY THEMES):
	Robux: number?,
	ProductId: number?,
	Month: number?,
	Theme: string?,
}

local rgb = Color3.fromRGB
local Smooth = Enum.Material.SmoothPlastic
local Neon = Enum.Material.Neon
local Glass = Enum.Material.Glass

local ShopConfig = {}

-- PRICES -----------------------------------------------------------------
-- What each rarity costs in coins. They grow about 3x per rarity, so rarer
-- items are a real goal. Change a number here and every item of that
-- rarity follows.
local PRICE = {
	Common = 50,
	Uncommon = 150,
	Rare = 500,
	Epic = 1500,
	Legendary = 5000,
}
ShopConfig.Prices = PRICE

-- Seconds a player must wait between shop requests (stops button spam).
ShopConfig.RequestCooldown = 0.5

-- After a purchase, save within this many seconds. Several quick purchases
-- share one save, which keeps us inside Roblox's DataStore limits.
ShopConfig.SaveDelay = 6

-- The free items every player starts with.
ShopConfig.Defaults = {
	Color = "Color_Mint",
	Hat = "Hat_None",
	Skin = "Skin_Classic",
	Topping = "Topping_Slime",
}

-- BLOB COLORS -------------------------------------------------------------
ShopConfig.Colors = {
	-- Common
	{ Id = "Color_Mint", DisplayName = "Jelly Mint", Rarity = "Common", Price = 0, Color = rgb(90, 220, 140), Material = Smooth, Reflectance = 0 },
	{ Id = "Color_Bubblegum", DisplayName = "Bubblegum", Rarity = "Common", Price = PRICE.Common, Color = rgb(255, 125, 200), Material = Smooth, Reflectance = 0 },
	{ Id = "Color_Lemon", DisplayName = "Lemon Drop", Rarity = "Common", Price = PRICE.Common, Color = rgb(255, 225, 60), Material = Smooth, Reflectance = 0 },
	-- Uncommon
	{ Id = "Color_Sky", DisplayName = "Sky Blue", Rarity = "Uncommon", Price = PRICE.Uncommon, Color = rgb(85, 175, 255), Material = Smooth, Reflectance = 0 },
	{ Id = "Color_Tangerine", DisplayName = "Tangerine", Rarity = "Uncommon", Price = PRICE.Uncommon, Color = rgb(255, 145, 45), Material = Smooth, Reflectance = 0 },
	{ Id = "Color_Lime", DisplayName = "Zesty Lime", Rarity = "Uncommon", Price = PRICE.Uncommon, Color = rgb(175, 240, 40), Material = Smooth, Reflectance = 0 },
	-- Rare
	{ Id = "Color_Grape", DisplayName = "Grape Soda", Rarity = "Rare", Price = PRICE.Rare, Color = rgb(155, 95, 255), Material = Smooth, Reflectance = 0 },
	{ Id = "Color_Cherry", DisplayName = "Cherry Pop", Rarity = "Rare", Price = PRICE.Rare, Color = rgb(255, 65, 85), Material = Smooth, Reflectance = 0 },
	{ Id = "Color_Aqua", DisplayName = "Aqua Splash", Rarity = "Rare", Price = PRICE.Rare, Color = rgb(35, 220, 225), Material = Smooth, Reflectance = 0 },
	{ Id = "Color_CottonCandy", DisplayName = "Cotton Candy", Rarity = "Rare", Price = PRICE.Rare, Color = rgb(240, 175, 255), Material = Smooth, Reflectance = 0 },
	-- Epic
	{ Id = "Color_GlowBerry", DisplayName = "Glow Berry", Rarity = "Epic", Price = PRICE.Epic, Color = rgb(255, 60, 200), Material = Neon, Reflectance = 0 },
	{ Id = "Color_Gold", DisplayName = "Golden Blob", Rarity = "Epic", Price = PRICE.Epic, Color = rgb(255, 195, 40), Material = Smooth, Reflectance = 0.3 },
	-- Legendary: the month's themed jelly (added below, see MONTHLY THEMES)
} :: { ColorItem }

-- HATS (built from simple parts in HatBuilder) ------------------------------
ShopConfig.Hats = {
	-- Common
	{ Id = "Hat_None", DisplayName = "No Squishy", Rarity = "Common", Price = 0, Shape = "None", MainColor = rgb(255, 255, 255), AccentColor = rgb(255, 255, 255) },
	{ Id = "Squishy_DumplingPeach", DisplayName = "Peach Dumpling", Rarity = "Common", Price = PRICE.Common, Shape = "Dumpling", MainColor = rgb(255, 175, 80), AccentColor = rgb(255, 140, 150) },
	{ Id = "Squishy_DumplingLilac", DisplayName = "Lilac Dumpling", Rarity = "Common", Price = PRICE.Common, Shape = "Dumpling", MainColor = rgb(185, 150, 240), AccentColor = rgb(255, 140, 150) },
	{ Id = "Squishy_DumplingMint", DisplayName = "Mint Dumpling", Rarity = "Common", Price = PRICE.Common, Shape = "Dumpling", MainColor = rgb(150, 225, 170), AccentColor = rgb(255, 140, 150) },
	-- Uncommon
	{ Id = "Squishy_Butter", DisplayName = "Butter Squishy", Rarity = "Uncommon", Price = PRICE.Uncommon, Shape = "Butter", MainColor = rgb(255, 240, 165), AccentColor = rgb(40, 70, 190) },
	{ Id = "Squishy_Donut", DisplayName = "Donut Squishy", Rarity = "Uncommon", Price = PRICE.Uncommon, Shape = "Donut", MainColor = rgb(255, 150, 200), AccentColor = rgb(215, 160, 100) },
	-- Rare
	{ Id = "Squishy_JellyCubeBlue", DisplayName = "Blue Jelly Cube", Rarity = "Rare", Price = PRICE.Rare, Shape = "JellyCube", MainColor = rgb(70, 190, 245), AccentColor = rgb(255, 255, 255) },
	{ Id = "Squishy_JellyCubePink", DisplayName = "Pink Jelly Cube", Rarity = "Rare", Price = PRICE.Rare, Shape = "JellyCube", MainColor = rgb(255, 110, 190), AccentColor = rgb(255, 255, 255) },
	{ Id = "Squishy_IceCream", DisplayName = "Ice Cream Cone", Rarity = "Rare", Price = PRICE.Rare, Shape = "IceCream", MainColor = rgb(150, 235, 200), AccentColor = rgb(220, 165, 95) },
	-- Epic
	{ Id = "Squishy_Cake", DisplayName = "Layer Cake", Rarity = "Epic", Price = PRICE.Epic, Shape = "CakeSlice", MainColor = rgb(255, 252, 245), AccentColor = rgb(255, 230, 190) },
	{ Id = "Squishy_Popcorn", DisplayName = "Popcorn Bucket", Rarity = "Epic", Price = PRICE.Epic, Shape = "Popcorn", MainColor = rgb(230, 50, 60), AccentColor = rgb(255, 255, 255) },
	-- Legendary: the month's themed squishy (added below, see MONTHLY THEMES)
} :: { HatItem }

-- WEAPON SKINS (change the look of every gun) ------------------------------
ShopConfig.Skins = {
	{
		Id = "Skin_Classic",
		DisplayName = "Classic",
		Rarity = "Common",
		Price = 0,
		-- No colours: every gun keeps its own toy colours.
		BodyMaterial = Smooth,
		TrimMaterial = Smooth,
		Reflectance = 0.04,
		Pattern = "None",
		PatternColors = {},
		PatternMaterial = Smooth,
	},
	{
		Id = "Skin_Glue",
		DisplayName = "Glue Gun",
		Rarity = "Common",
		Price = PRICE.Common,
		BodyColor = rgb(250, 250, 252),
		TrimColor = rgb(255, 140, 40),
		AccentColor = rgb(60, 130, 235),
		BodyMaterial = Smooth,
		TrimMaterial = Smooth,
		Reflectance = 0.15,
		Pattern = "Drips",
		PatternColors = { rgb(255, 255, 255) },
		PatternMaterial = Smooth,
	},
	{
		Id = "Skin_Activator",
		DisplayName = "Activator Gun",
		Rarity = "Uncommon",
		Price = PRICE.Uncommon,
		BodyColor = rgb(70, 190, 255),
		TrimColor = rgb(235, 250, 255),
		AccentColor = rgb(20, 90, 210),
		BodyTransparency = 0.15,
		BodyMaterial = Glass,
		TrimMaterial = Smooth,
		Reflectance = 0.1,
		Pattern = "Bubbles",
		PatternColors = { rgb(255, 255, 255) },
		PatternMaterial = Glass,
	},
	{
		Id = "Skin_Foam",
		DisplayName = "Foam Gun",
		Rarity = "Rare",
		Price = PRICE.Rare,
		BodyColor = rgb(255, 185, 215),
		TrimColor = rgb(255, 235, 150),
		AccentColor = rgb(150, 225, 200),
		BodyMaterial = Smooth,
		TrimMaterial = Smooth,
		Reflectance = 0.02,
		Pattern = "Spots",
		PatternColors = { rgb(255, 120, 150), rgb(255, 210, 90), rgb(120, 210, 255), rgb(160, 230, 140), rgb(200, 160, 255) },
		PatternMaterial = Smooth,
	},
	{
		Id = "Skin_Clay",
		DisplayName = "Clay Gun",
		Rarity = "Rare",
		Price = PRICE.Rare,
		BodyColor = rgb(255, 200, 155),
		TrimColor = rgb(190, 160, 240),
		AccentColor = rgb(150, 225, 190),
		BodyMaterial = Smooth,
		TrimMaterial = Smooth,
		Reflectance = 0,
		Pattern = "Stripes",
		PatternColors = { rgb(255, 225, 190), rgb(255, 170, 140) },
		PatternMaterial = Smooth,
	},
	{
		Id = "Skin_Water",
		DisplayName = "Water Gun",
		Rarity = "Epic",
		Price = PRICE.Epic,
		BodyColor = rgb(90, 215, 255),
		TrimColor = rgb(255, 150, 40),
		AccentColor = rgb(255, 230, 70),
		BodyTransparency = 0.25,
		BodyMaterial = Glass,
		TrimMaterial = Smooth,
		Reflectance = 0.12,
		Pattern = "Line",
		PatternColors = { rgb(255, 255, 255) },
		PatternMaterial = Neon,
	},
	-- Legendary: the month's themed gun skin (added below, see MONTHLY THEMES)
} :: { SkinItem }

-- GUNS --------------------------------------------------------------------
-- Owning a gun puts it in your loadout (keys 1-5 in matches). The Auto Rifle
-- is free, so everyone starts with it. Gun stats live in Config/WeaponConfig.
export type WeaponItem = {
	Id: string,
	WeaponId: string, -- the key in WeaponConfig.Weapons
	DisplayName: string,
	Rarity: Rarity,
	Price: number,
	Blurb: string,
}

ShopConfig.STARTER_WEAPON = "Rifle"

ShopConfig.Weapons = {
	{ Id = "Weapon_Rifle", WeaponId = "Rifle", DisplayName = "Auto Rifle", Rarity = "Common", Price = 0, Blurb = "Steady all-rounder" },
	{ Id = "Weapon_Pistol", WeaponId = "Pistol", DisplayName = "Pop Pistol", Rarity = "Common", Price = 0, Blurb = "Everyone's sidearm" },
	{ Id = "Weapon_SMG", WeaponId = "SMG", DisplayName = "Buzz SMG", Rarity = "Uncommon", Price = PRICE.Uncommon, Blurb = "Fast, close range" },
	{ Id = "Weapon_Burst", WeaponId = "Burst", DisplayName = "Triple Burst", Rarity = "Uncommon", Price = PRICE.Uncommon, Blurb = "3 shots per click" },
	{ Id = "Weapon_Shotgun", WeaponId = "Shotgun", DisplayName = "Pump Shotgun", Rarity = "Rare", Price = PRICE.Rare, Blurb = "Huge up close" },
	{ Id = "Weapon_Marksman", WeaponId = "Marksman", DisplayName = "Slimeshot Marksman", Rarity = "Rare", Price = PRICE.Rare, Blurb = "Semi-auto, hits hard" },
	{ Id = "Weapon_Sniper", WeaponId = "Sniper", DisplayName = "Sniper", Rarity = "Epic", Price = PRICE.Epic, Blurb = "One shot, long range" },
	-- The one Legendary gun (guns are never sold for Robux).
	{ Id = "Weapon_Launcher", WeaponId = "Launcher", DisplayName = "Blob Launcher", Rarity = "Legendary", Price = PRICE.Legendary, Blurb = "Explodes on impact" },
} :: { WeaponItem }

-- The shop item Id for a gun, e.g. "Rifle" -> "Weapon_Rifle".
function ShopConfig.weaponItemId(weaponId: string): string
	return "Weapon_" .. weaponId
end

-- TOPPINGS (kill effects) ------------------------------------------------
-- When YOU eliminate someone, they burst into your equipped topping.
-- Purely visual (client/Effects/ToppingEffects).
export type ToppingStyle = "Slime" | "Sprinkles" | "Foam" | "Glitter" | "Charms"
export type ToppingItem = {
	Id: string,
	DisplayName: string,
	Rarity: Rarity,
	Price: number,
	Style: ToppingStyle,
	Colors: { Color3 },
	Charms: { string }?, -- little 3D charms for "Charms" toppings (names from Cosmetics/CharmBuilder)
	-- Monthly themed items only (sold for Robux, see MONTHLY THEMES):
	Robux: number?,
	ProductId: number?,
	Month: number?,
	Theme: string?,
}

local RAINBOW = { rgb(255, 90, 110), rgb(255, 190, 60), rgb(255, 240, 90), rgb(110, 220, 120), rgb(90, 170, 255), rgb(190, 120, 255) }
local PASTEL = { rgb(255, 190, 210), rgb(190, 230, 255), rgb(200, 245, 200), rgb(255, 240, 180), rgb(225, 200, 255) }

ShopConfig.Toppings = {
	-- Common
	{ Id = "Topping_Slime", DisplayName = "Slime Splat", Rarity = "Common", Price = 0, Style = "Slime", Colors = { rgb(120, 230, 160) } },
	{ Id = "Topping_Sprinkles", DisplayName = "Rainbow Sprinkles", Rarity = "Common", Price = PRICE.Common, Style = "Sprinkles", Colors = RAINBOW },
	-- Uncommon
	{ Id = "Topping_Foam", DisplayName = "Foam Balls", Rarity = "Uncommon", Price = PRICE.Uncommon, Style = "Foam", Colors = PASTEL },
	{ Id = "Topping_Glitter", DisplayName = "Iridescent Glitter", Rarity = "Uncommon", Price = PRICE.Uncommon, Style = "Glitter", Colors = { rgb(255, 170, 230), rgb(170, 255, 230), rgb(210, 190, 255), rgb(255, 255, 255) } },
	-- Rare
	{ Id = "Topping_Mermaid", DisplayName = "Mermaid Sprinkle Mix", Rarity = "Rare", Price = PRICE.Rare, Style = "Sprinkles", Colors = { rgb(60, 200, 190), rgb(150, 90, 230), rgb(110, 220, 255), rgb(255, 215, 90) } },
	{ Id = "Topping_CharmMix", DisplayName = "Assorted Charm Mix", Rarity = "Rare", Price = PRICE.Rare, Style = "Charms", Colors = RAINBOW, Charms = { "Strawberry", "Star", "Flower", "Lemon", "Gem", "Bear" } },
	-- Epic
	{ Id = "Topping_Birthday", DisplayName = "Birthday Bash Charms", Rarity = "Epic", Price = PRICE.Epic, Style = "Charms", Colors = PASTEL, Charms = { "Cake", "Cupcake", "Balloon", "Candy", "Gift", "Bear" } },
	{ Id = "Topping_Munchies", DisplayName = "Munchie Squad Charms", Rarity = "Epic", Price = PRICE.Epic, Style = "Charms", Colors = RAINBOW, Charms = { "Burger", "Pizza", "Fries", "Toast", "Egg", "Cheese" } },
	-- Legendary: the month's charm packet (added below, see MONTHLY THEMES)
} :: { ToppingItem }

-- MONTHLY THEMES (Robux) ----------------------------------------------------
-- Every month has its own themed set: a blob colour, a squishy, a gun skin
-- and a charm-packet topping. They are each tab's Legendary, sold for Robux,
-- only during their month (in UTC time), and stay yours forever once bought.
-- Guns themselves are never sold for Robux (that would be pay-to-win);
-- skins are cosmetic.
--
-- To put them on sale: publish the game, create one Developer Product per
-- item on the Creator Dashboard (Monetization -> Developer Products), then
-- paste each product's id below, e.g. ["Theme_Christmas_Topping"] = 1234567890.
-- Items without an id show "Not on sale yet". The ROBUX tab's coin packs and
-- bundles (Config/RobuxShopConfig) put their ids here too, e.g. ["Coins_Jar"] = 123.
ShopConfig.ROBUX_ONLY = 1e9 -- coin price of Robux items: they can never be bought with coins
ShopConfig.RobuxPrices = { Color = 49, Hat = 99, Skin = 79, Topping = 129 }
ShopConfig.ProductIds = {} :: { [string]: number }

export type Theme = {
	Key: string,
	Month: number,
	Name: string,
	Main: Color3,
	Accent: Color3,
	Squishy: HatShape,
	Charms: { string },
}

ShopConfig.Themes = {
	{ Key = "Winter", Month = 1, Name = "Winter Wonderland", Main = rgb(190, 230, 255), Accent = rgb(255, 255, 255), Squishy = "Dumpling", Charms = { "Snowflake", "Snowman", "Mug", "Mitten", "Cookie" } },
	{ Key = "Sweetheart", Month = 2, Name = "Sweetheart", Main = rgb(255, 110, 150), Accent = rgb(255, 225, 235), Squishy = "CakeSlice", Charms = { "Heart", "Letter", "Chocolate", "Rose", "Cupcake" } },
	{ Key = "Lucky", Month = 3, Name = "Lucky Clover", Main = rgb(80, 200, 110), Accent = rgb(255, 215, 80), Squishy = "Dumpling", Charms = { "Clover", "Coin", "TopHat", "Star", "Gem" } },
	{ Key = "Bloom", Month = 4, Name = "Spring Bloom", Main = rgb(255, 190, 220), Accent = rgb(200, 240, 170), Squishy = "Donut", Charms = { "Tulip", "Flower", "Chick", "Butterfly", "Daisy" } },
	{ Key = "Berry", Month = 5, Name = "Berry Picnic", Main = rgb(240, 70, 100), Accent = rgb(255, 240, 220), Squishy = "IceCream", Charms = { "Strawberry", "Basket", "Bee", "Daisy", "Cake" } },
	{ Key = "Splash", Month = 6, Name = "Summer Splash", Main = rgb(70, 210, 240), Accent = rgb(255, 230, 120), Squishy = "JellyCube", Charms = { "Shell", "Watermelon", "Sunglasses", "BeachBall", "Starfish" } },
	{ Key = "Sparkler", Month = 7, Name = "Sparkler Night", Main = rgb(90, 110, 255), Accent = rgb(255, 80, 90), Squishy = "Popcorn", Charms = { "Firework", "Sparkle", "Star", "IceCream", "Balloon" } },
	{ Key = "Tropical", Month = 8, Name = "Tropical", Main = rgb(255, 190, 60), Accent = rgb(60, 200, 120), Squishy = "Donut", Charms = { "Pineapple", "Palm", "Coconut", "Hibiscus", "Watermelon" } },
	{ Key = "School", Month = 9, Name = "Back to School", Main = rgb(255, 220, 70), Accent = rgb(230, 60, 60), Squishy = "Butter", Charms = { "Book", "Pencil", "Apple", "Backpack", "Ruler" } },
	{ Key = "Spooky", Month = 10, Name = "Spooky", Main = rgb(255, 140, 40), Accent = rgb(120, 60, 170), Squishy = "Dumpling", Charms = { "Pumpkin", "Ghost", "Candy", "Bat", "Moon" } },
	{ Key = "Harvest", Month = 11, Name = "Cozy Harvest", Main = rgb(200, 110, 50), Accent = rgb(250, 215, 140), Squishy = "CakeSlice", Charms = { "Leaf", "Pie", "Corn", "Acorn", "MapleLeaf" } },
	{ Key = "Christmas", Month = 12, Name = "Christmas", Main = rgb(220, 40, 50), Accent = rgb(40, 150, 80), Squishy = "IceCream", Charms = { "Tree", "Gift", "Lollipop", "Cookie", "CandyCane", "Bell", "Snowflake" } },
} :: { Theme }

-- Builds each month's four themed items into the lists above.
for _, theme in ShopConfig.Themes do
	local base = "Theme_" .. theme.Key .. "_"
	local function robux(category: string, id: string)
		return (ShopConfig.RobuxPrices :: { [string]: number })[category], ShopConfig.ProductIds[id] or 0
	end
	local colorRobux, colorProduct = robux("Color", base .. "Color")
	table.insert(ShopConfig.Colors, {
		Id = base .. "Color", DisplayName = theme.Name .. " Jelly", Rarity = "Legendary", Price = ShopConfig.ROBUX_ONLY,
		Color = theme.Main, Material = Enum.Material.SmoothPlastic, Reflectance = 0.2,
		Robux = colorRobux, ProductId = colorProduct, Month = theme.Month, Theme = theme.Name,
	})
	local hatRobux, hatProduct = robux("Hat", base .. "Squishy")
	table.insert(ShopConfig.Hats, {
		Id = base .. "Squishy", DisplayName = theme.Name .. " Squishy", Rarity = "Legendary", Price = ShopConfig.ROBUX_ONLY,
		Shape = theme.Squishy, MainColor = theme.Main, AccentColor = theme.Accent,
		Robux = hatRobux, ProductId = hatProduct, Month = theme.Month, Theme = theme.Name,
	})
	local skinRobux, skinProduct = robux("Skin", base .. "Skin")
	table.insert(ShopConfig.Skins, {
		Id = base .. "Skin", DisplayName = theme.Name .. " Gun", Rarity = "Legendary", Price = ShopConfig.ROBUX_ONLY,
		BodyColor = theme.Main, TrimColor = theme.Accent, AccentColor = rgb(255, 255, 255), BodyMaterial = Smooth, TrimMaterial = Smooth,
		Reflectance = 0.1, Pattern = "Stripes", PatternColors = { theme.Accent, rgb(255, 255, 255) }, PatternMaterial = Neon,
		Robux = skinRobux, ProductId = skinProduct, Month = theme.Month, Theme = theme.Name,
	})
	local toppingRobux, toppingProduct = robux("Topping", base .. "Topping")
	table.insert(ShopConfig.Toppings, {
		Id = base .. "Topping", DisplayName = theme.Name .. " Charm Packet", Rarity = "Legendary", Price = ShopConfig.ROBUX_ONLY,
		Style = "Charms", Colors = { theme.Main, theme.Accent }, Charms = theme.Charms,
		Robux = toppingRobux, ProductId = toppingProduct, Month = theme.Month, Theme = theme.Name,
	})
end

-- Lookups (built once from the lists above) ---------------------------------

local items: { [string]: ShopItem } = {}
local colorsById: { [string]: ColorItem } = {}
local hatsById: { [string]: HatItem } = {}
local skinsById: { [string]: SkinItem } = {}
local weaponsById: { [string]: WeaponItem } = {}
local toppingsById: { [string]: ToppingItem } = {}
local byProductId: { [number]: ShopItem } = {}

local function register(item: any, category: Category)
	local id: string = item.Id
	assert(items[id] == nil, "ShopConfig: duplicate item Id " .. id)
	assert(not string.find(id, ",", 1, true), "ShopConfig: item Ids can't contain commas: " .. id)
	local entry: ShopItem = {
		Id = id,
		Category = category,
		DisplayName = item.DisplayName,
		Rarity = item.Rarity,
		Price = item.Price,
		Robux = item.Robux,
		ProductId = item.ProductId,
		Month = item.Month,
		Theme = item.Theme,
	}
	items[id] = entry
	if entry.ProductId and entry.ProductId > 0 then
		byProductId[entry.ProductId] = entry
	end
end

for _, item in ShopConfig.Colors do
	register(item, "Color")
	colorsById[item.Id] = item
end
for _, item in ShopConfig.Hats do
	register(item, "Hat")
	hatsById[item.Id] = item
end
for _, item in ShopConfig.Skins do
	register(item, "Skin")
	skinsById[item.Id] = item
end
for _, item in ShopConfig.Weapons do
	register(item, "Weapon")
	weaponsById[item.Id] = item
end

function ShopConfig.getWeapon(id: string): WeaponItem?
	return weaponsById[id]
end
for _, item in ShopConfig.Toppings do
	register(item, "Topping")
	toppingsById[item.Id] = item
end

function ShopConfig.getTopping(id: string?): ToppingItem
	return (if id then toppingsById[id] else nil) or toppingsById[ShopConfig.Defaults.Topping]
end

-- The item sold as this Robux Developer Product, if any.
function ShopConfig.getByProductId(productId: number): ShopItem?
	return byProductId[productId]
end

-- RARITY -----------------------------------------------------------------
-- Every item has a rarity (see the RARITY RULES at the top). The Daily
-- Squishy rolls a rarity with these chances first, then picks an item of
-- that rarity.
export type RarityInfo = { Name: Rarity, Rank: number, Chance: number, Color: Color3 }

ShopConfig.Rarities = {
	{ Name = "Common", Rank = 1, Chance = 40, Color = rgb(200, 205, 215) },
	{ Name = "Uncommon", Rank = 2, Chance = 30, Color = rgb(110, 220, 120) },
	{ Name = "Rare", Rank = 3, Chance = 20, Color = rgb(90, 170, 255) },
	{ Name = "Epic", Rank = 4, Chance = 8, Color = rgb(190, 110, 255) },
	{ Name = "Legendary", Rank = 5, Chance = 2, Color = rgb(255, 200, 60) },
} :: { RarityInfo }

local rarityByName: { [string]: RarityInfo } = {}
for _, info in ShopConfig.Rarities do
	rarityByName[info.Name] = info
end

function ShopConfig.rarityOf(item: ShopItem): RarityInfo
	return rarityByName[item.Rarity] or ShopConfig.Rarities[1]
end

-- A copy of `list` in shop order: Common first, Legendary last, cheapest
-- first inside a rarity (ties keep their order in the list above).
function ShopConfig.sortByRarity(list: { ShopItem }): { ShopItem }
	local position: { [string]: number } = {}
	local sorted = table.clone(list)
	for index, item in sorted do
		position[item.Id] = index
	end
	table.sort(sorted, function(a: ShopItem, b: ShopItem): boolean
		local rankA, rankB = ShopConfig.rarityOf(a).Rank, ShopConfig.rarityOf(b).Rank
		if rankA ~= rankB then
			return rankA < rankB
		end
		if a.Price ~= b.Price then
			return a.Price < b.Price
		end
		return position[a.Id] < position[b.Id]
	end)
	return sorted
end

-- Checks the RARITY RULES and prints a warning (the game still runs) if a
-- tab is missing a rarity or has more than one Legendary on sale at once.
-- Monthly themed items count as one, because only one month is on sale.
do
	local lists: { [string]: { any } } = {
		Colors = ShopConfig.Colors, Squishies = ShopConfig.Hats, Skins = ShopConfig.Skins,
		Guns = ShopConfig.Weapons, Toppings = ShopConfig.Toppings,
	}
	for tab, list in lists do
		local seen: { [string]: boolean } = {}
		local legendaries, hasMonthly = 0, false
		for _, item in list do
			seen[item.Rarity] = true
			if item.Month then
				hasMonthly = true
			elseif item.Rarity == "Legendary" then
				legendaries += 1
			end
		end
		if hasMonthly then
			legendaries += 1
		end
		for _, info in ShopConfig.Rarities do
			if not seen[info.Name] then
				warn(`ShopConfig: the {tab} tab has no {info.Name} item`)
			end
		end
		if legendaries ~= 1 then
			warn(`ShopConfig: the {tab} tab should have exactly one Legendary (it has {legendaries})`)
		end
	end
end

-- This month (1-12), in UTC so the server and every player agree.
function ShopConfig.currentMonth(): number
	local date = os.date("!*t", math.floor(workspace:GetServerTimeNow()))
	return (date :: any).month
end

-- Themed items are only on sale during their month; others always are.
function ShopConfig.isOnSale(item: ShopItem, month: number): boolean
	return item.Month == nil or item.Month == month
end

-- Returns the item with this Id, or nil if there is no such item.
function ShopConfig.getItem(id: string): ShopItem?
	return items[id]
end

function ShopConfig.getColor(id: string?): ColorItem
	return (if id then colorsById[id] else nil) or colorsById[ShopConfig.Defaults.Color]
end

function ShopConfig.getHat(id: string?): HatItem
	return (if id then hatsById[id] else nil) or hatsById[ShopConfig.Defaults.Hat]
end

function ShopConfig.getSkin(id: string?): SkinItem
	return (if id then skinsById[id] else nil) or skinsById[ShopConfig.Defaults.Skin]
end

-- Free items (price 0) are owned by everyone.
function ShopConfig.isFree(id: string): boolean
	local item = items[id]
	return item ~= nil and item.Price <= 0 and item.Robux == nil
end

-- The default item Id for a category.
function ShopConfig.defaultFor(category: Category): string
	if category == "Color" then
		return ShopConfig.Defaults.Color
	elseif category == "Hat" then
		return ShopConfig.Defaults.Hat
	elseif category == "Weapon" then
		return ShopConfig.weaponItemId(ShopConfig.STARTER_WEAPON)
	elseif category == "Topping" then
		return ShopConfig.Defaults.Topping
	end
	return ShopConfig.Defaults.Skin
end

assert(colorsById[ShopConfig.Defaults.Color], "ShopConfig: default color missing")
assert(hatsById[ShopConfig.Defaults.Hat], "ShopConfig: default hat missing")
assert(skinsById[ShopConfig.Defaults.Skin], "ShopConfig: default skin missing")

return ShopConfig
