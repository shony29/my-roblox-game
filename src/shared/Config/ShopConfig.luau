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
	  * Price       Cost in coins. 0 means free: every player owns it.

	Items show in the shop in the same order as in these lists.
]]

export type Category = "Color" | "Hat" | "Skin" | "Weapon" | "Topping"

-- What the shop needs to know about any item.
export type ShopItem = {
	Id: string,
	Category: Category,
	DisplayName: string,
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
	{
		Id = "Color_Mint",
		DisplayName = "Jelly Mint",
		Price = 0,
		Color = rgb(90, 220, 140),
		Material = Smooth,
		Reflectance = 0,
	},
	{
		Id = "Color_Bubblegum",
		DisplayName = "Bubblegum",
		Price = 25,
		Color = rgb(255, 125, 200),
		Material = Smooth,
		Reflectance = 0,
	},
	{
		Id = "Color_Lemon",
		DisplayName = "Lemon Drop",
		Price = 25,
		Color = rgb(255, 225, 60),
		Material = Smooth,
		Reflectance = 0,
	},
	{
		Id = "Color_Sky",
		DisplayName = "Sky Blue",
		Price = 50,
		Color = rgb(85, 175, 255),
		Material = Smooth,
		Reflectance = 0,
	},
	{
		Id = "Color_Tangerine",
		DisplayName = "Tangerine",
		Price = 50,
		Color = rgb(255, 145, 45),
		Material = Smooth,
		Reflectance = 0,
	},
	{
		Id = "Color_Grape",
		DisplayName = "Grape Soda",
		Price = 75,
		Color = rgb(155, 95, 255),
		Material = Smooth,
		Reflectance = 0,
	},
	{
		Id = "Color_Cherry",
		DisplayName = "Cherry Pop",
		Price = 75,
		Color = rgb(255, 65, 85),
		Material = Smooth,
		Reflectance = 0,
	},
	{
		Id = "Color_Aqua",
		DisplayName = "Aqua Splash",
		Price = 100,
		Color = rgb(35, 220, 225),
		Material = Smooth,
		Reflectance = 0,
	},
	{
		Id = "Color_Lime",
		DisplayName = "Zesty Lime",
		Price = 100,
		Color = rgb(175, 240, 40),
		Material = Smooth,
		Reflectance = 0,
	},
	{
		Id = "Color_CottonCandy",
		DisplayName = "Cotton Candy",
		Price = 150,
		Color = rgb(240, 175, 255),
		Material = Smooth,
		Reflectance = 0,
	},
	{
		Id = "Color_GlowBerry",
		DisplayName = "Glow Berry",
		Price = 300,
		Color = rgb(255, 60, 200),
		Material = Neon,
		Reflectance = 0,
	},
	{
		Id = "Color_Gold",
		DisplayName = "Golden Blob",
		Price = 500,
		Color = rgb(255, 195, 40),
		Material = Smooth,
		Reflectance = 0.3,
	},
} :: { ColorItem }

-- HATS (built from simple parts in HatBuilder) ------------------------------
ShopConfig.Hats = {
	{ Id = "Hat_None", DisplayName = "No Squishy", Price = 0, Shape = "None", MainColor = rgb(255, 255, 255), AccentColor = rgb(255, 255, 255) },
	{ Id = "Squishy_DumplingPeach", DisplayName = "Peach Dumpling", Price = 40, Shape = "Dumpling", MainColor = rgb(255, 175, 80), AccentColor = rgb(255, 140, 150) },
	{ Id = "Squishy_DumplingLilac", DisplayName = "Lilac Dumpling", Price = 40, Shape = "Dumpling", MainColor = rgb(185, 150, 240), AccentColor = rgb(255, 140, 150) },
	{ Id = "Squishy_DumplingMint", DisplayName = "Mint Dumpling", Price = 40, Shape = "Dumpling", MainColor = rgb(150, 225, 170), AccentColor = rgb(255, 140, 150) },
	{ Id = "Squishy_Butter", DisplayName = "Butter Squishy", Price = 60, Shape = "Butter", MainColor = rgb(255, 240, 165), AccentColor = rgb(40, 70, 190) },
	{ Id = "Squishy_JellyCubeBlue", DisplayName = "Blue Jelly Cube", Price = 80, Shape = "JellyCube", MainColor = rgb(70, 190, 245), AccentColor = rgb(255, 255, 255) },
	{ Id = "Squishy_JellyCubePink", DisplayName = "Pink Jelly Cube", Price = 80, Shape = "JellyCube", MainColor = rgb(255, 110, 190), AccentColor = rgb(255, 255, 255) },
	{ Id = "Squishy_Donut", DisplayName = "Donut Squishy", Price = 70, Shape = "Donut", MainColor = rgb(255, 150, 200), AccentColor = rgb(215, 160, 100) },
	{ Id = "Squishy_Cake", DisplayName = "Layer Cake", Price = 90, Shape = "CakeSlice", MainColor = rgb(255, 252, 245), AccentColor = rgb(255, 230, 190) },
	{ Id = "Squishy_IceCream", DisplayName = "Ice Cream Cone", Price = 90, Shape = "IceCream", MainColor = rgb(150, 235, 200), AccentColor = rgb(220, 165, 95) },
	{ Id = "Squishy_Popcorn", DisplayName = "Popcorn Bucket", Price = 100, Shape = "Popcorn", MainColor = rgb(230, 50, 60), AccentColor = rgb(255, 255, 255) },
} :: { HatItem }

-- WEAPON SKINS (change the look of every gun) ------------------------------
ShopConfig.Skins = {
	{
		Id = "Skin_Classic",
		DisplayName = "Classic",
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
		Price = 60,
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
		Price = 100,
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
		Price = 150,
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
		Price = 220,
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
		Price = 300,
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
} :: { SkinItem }

-- GUNS --------------------------------------------------------------------
-- Owning a gun puts it in your loadout (keys 1-5 in matches). The Auto Rifle
-- is free, so everyone starts with it. Gun stats live in Config/WeaponConfig.
export type WeaponItem = {
	Id: string,
	WeaponId: string, -- the key in WeaponConfig.Weapons
	DisplayName: string,
	Price: number,
	Blurb: string,
}

ShopConfig.STARTER_WEAPON = "Rifle"

ShopConfig.Weapons = {
	{ Id = "Weapon_Rifle", WeaponId = "Rifle", DisplayName = "Auto Rifle", Price = 0, Blurb = "Steady all-rounder" },
	{ Id = "Weapon_Pistol", WeaponId = "Pistol", DisplayName = "Pop Pistol", Price = 0, Blurb = "Everyone's sidearm" },
	{ Id = "Weapon_SMG", WeaponId = "SMG", DisplayName = "Buzz SMG", Price = 150, Blurb = "Fast, close range" },
	{ Id = "Weapon_Shotgun", WeaponId = "Shotgun", DisplayName = "Pump Shotgun", Price = 200, Blurb = "Huge up close" },
	{ Id = "Weapon_Burst", WeaponId = "Burst", DisplayName = "Triple Burst", Price = 125, Blurb = "3 shots per click" },
	{ Id = "Weapon_Marksman", WeaponId = "Marksman", DisplayName = "Slimeshot Marksman", Price = 175, Blurb = "Semi-auto, hits hard" },
	{ Id = "Weapon_Sniper", WeaponId = "Sniper", DisplayName = "Sniper", Price = 300, Blurb = "One shot, long range" },
	{ Id = "Weapon_Launcher", WeaponId = "Launcher", DisplayName = "Blob Launcher", Price = 350, Blurb = "Explodes on impact" },
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
	Price: number,
	Style: ToppingStyle,
	Colors: { Color3 },
	Charms: { string }?, -- little charms (emoji) for "Charms" toppings
	-- Monthly themed items only (sold for Robux, see MONTHLY THEMES):
	Robux: number?,
	ProductId: number?,
	Month: number?,
	Theme: string?,
}

local RAINBOW = { rgb(255, 90, 110), rgb(255, 190, 60), rgb(255, 240, 90), rgb(110, 220, 120), rgb(90, 170, 255), rgb(190, 120, 255) }
local PASTEL = { rgb(255, 190, 210), rgb(190, 230, 255), rgb(200, 245, 200), rgb(255, 240, 180), rgb(225, 200, 255) }

ShopConfig.Toppings = {
	{ Id = "Topping_Slime", DisplayName = "Slime Splat", Price = 0, Style = "Slime", Colors = { rgb(120, 230, 160) } },
	{ Id = "Topping_Sprinkles", DisplayName = "Rainbow Sprinkles", Price = 60, Style = "Sprinkles", Colors = RAINBOW },
	{ Id = "Topping_Foam", DisplayName = "Foam Balls", Price = 80, Style = "Foam", Colors = PASTEL },
	{ Id = "Topping_Mermaid", DisplayName = "Mermaid Sprinkle Mix", Price = 120, Style = "Sprinkles", Colors = { rgb(60, 200, 190), rgb(150, 90, 230), rgb(110, 220, 255), rgb(255, 215, 90) } },
	{ Id = "Topping_Glitter", DisplayName = "Iridescent Glitter", Price = 100, Style = "Glitter", Colors = { rgb(255, 170, 230), rgb(170, 255, 230), rgb(210, 190, 255), rgb(255, 255, 255) } },
	{ Id = "Topping_CharmMix", DisplayName = "Assorted Charm Mix", Price = 150, Style = "Charms", Colors = RAINBOW, Charms = { "🍓", "⭐", "🌸", "🍋", "💎", "🧸" } },
	{ Id = "Topping_Birthday", DisplayName = "Birthday Bash Charms", Price = 150, Style = "Charms", Colors = PASTEL, Charms = { "🎂", "🧁", "🎈", "🍬", "🎁", "🧸" } },
	{ Id = "Topping_Munchies", DisplayName = "Munchie Squad Charms", Price = 150, Style = "Charms", Colors = RAINBOW, Charms = { "🍔", "🍕", "🍟", "🍞", "🍳", "🧀" } },
} :: { ToppingItem }

-- MONTHLY THEMES (Robux) ----------------------------------------------------
-- Every month has its own themed set: a blob colour, a squishy, a gun skin
-- and a charm-packet topping. They are sold for Robux, only during their
-- month (in UTC time), and stay yours forever once bought. Guns themselves
-- are never sold for Robux (that would be pay-to-win); skins are cosmetic.
--
-- To put them on sale: publish the game, create one Developer Product per
-- item on the Creator Dashboard (Monetization -> Developer Products), then
-- paste each product's id below, e.g. ["Theme_Christmas_Topping"] = 1234567890.
-- Items without an id show "Not on sale yet".
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
	{ Key = "Winter", Month = 1, Name = "Winter Wonderland", Main = rgb(190, 230, 255), Accent = rgb(255, 255, 255), Squishy = "Dumpling", Charms = { "❄️", "⛄", "☕", "🧤", "🧣" } },
	{ Key = "Sweetheart", Month = 2, Name = "Sweetheart", Main = rgb(255, 110, 150), Accent = rgb(255, 225, 235), Squishy = "CakeSlice", Charms = { "💖", "💌", "🍫", "🌹", "💘" } },
	{ Key = "Lucky", Month = 3, Name = "Lucky Clover", Main = rgb(80, 200, 110), Accent = rgb(255, 215, 80), Squishy = "Dumpling", Charms = { "🍀", "🌈", "🪙", "🎩", "✨" } },
	{ Key = "Bloom", Month = 4, Name = "Spring Bloom", Main = rgb(255, 190, 220), Accent = rgb(200, 240, 170), Squishy = "Donut", Charms = { "🌷", "🌸", "🐣", "🦋", "🌼" } },
	{ Key = "Berry", Month = 5, Name = "Berry Picnic", Main = rgb(240, 70, 100), Accent = rgb(255, 240, 220), Squishy = "IceCream", Charms = { "🍓", "🧺", "🐝", "🌼", "🍰" } },
	{ Key = "Splash", Month = 6, Name = "Summer Splash", Main = rgb(70, 210, 240), Accent = rgb(255, 230, 120), Squishy = "JellyCube", Charms = { "🌊", "🐚", "🍉", "🕶️", "🏖️" } },
	{ Key = "Sparkler", Month = 7, Name = "Sparkler Night", Main = rgb(90, 110, 255), Accent = rgb(255, 80, 90), Squishy = "Popcorn", Charms = { "🎆", "🎇", "⭐", "🍦", "🎉" } },
	{ Key = "Tropical", Month = 8, Name = "Tropical", Main = rgb(255, 190, 60), Accent = rgb(60, 200, 120), Squishy = "Donut", Charms = { "🍍", "🌴", "🥥", "🦜", "🌺" } },
	{ Key = "School", Month = 9, Name = "Back to School", Main = rgb(255, 220, 70), Accent = rgb(230, 60, 60), Squishy = "Butter", Charms = { "📚", "✏️", "🍎", "🎒", "📏" } },
	{ Key = "Spooky", Month = 10, Name = "Spooky", Main = rgb(255, 140, 40), Accent = rgb(120, 60, 170), Squishy = "Dumpling", Charms = { "🎃", "👻", "🍬", "🦇", "🕸️" } },
	{ Key = "Harvest", Month = 11, Name = "Cozy Harvest", Main = rgb(200, 110, 50), Accent = rgb(250, 215, 140), Squishy = "CakeSlice", Charms = { "🍂", "🥧", "🌽", "🍁", "🧣" } },
	{ Key = "Christmas", Month = 12, Name = "Christmas", Main = rgb(220, 40, 50), Accent = rgb(40, 150, 80), Squishy = "IceCream", Charms = { "🎄", "🎁", "🍭", "🍪", "🌿", "🎅", "🔔" } },
} :: { Theme }

-- Builds each month's four themed items into the lists above.
for _, theme in ShopConfig.Themes do
	local base = "Theme_" .. theme.Key .. "_"
	local function robux(category: string, id: string)
		return (ShopConfig.RobuxPrices :: { [string]: number })[category], ShopConfig.ProductIds[id] or 0
	end
	local colorRobux, colorProduct = robux("Color", base .. "Color")
	table.insert(ShopConfig.Colors, {
		Id = base .. "Color", DisplayName = theme.Name .. " Jelly", Price = ShopConfig.ROBUX_ONLY,
		Color = theme.Main, Material = Enum.Material.SmoothPlastic, Reflectance = 0.2,
		Robux = colorRobux, ProductId = colorProduct, Month = theme.Month, Theme = theme.Name,
	})
	local hatRobux, hatProduct = robux("Hat", base .. "Squishy")
	table.insert(ShopConfig.Hats, {
		Id = base .. "Squishy", DisplayName = theme.Name .. " Squishy", Price = ShopConfig.ROBUX_ONLY,
		Shape = theme.Squishy, MainColor = theme.Main, AccentColor = theme.Accent,
		Robux = hatRobux, ProductId = hatProduct, Month = theme.Month, Theme = theme.Name,
	})
	local skinRobux, skinProduct = robux("Skin", base .. "Skin")
	table.insert(ShopConfig.Skins, {
		Id = base .. "Skin", DisplayName = theme.Name .. " Gun", Price = ShopConfig.ROBUX_ONLY,
		BodyColor = theme.Main, TrimColor = theme.Accent, AccentColor = rgb(255, 255, 255), BodyMaterial = Smooth, TrimMaterial = Smooth,
		Reflectance = 0.1, Pattern = "Stripes", PatternColors = { theme.Accent, rgb(255, 255, 255) }, PatternMaterial = Neon,
		Robux = skinRobux, ProductId = skinProduct, Month = theme.Month, Theme = theme.Name,
	})
	local toppingRobux, toppingProduct = robux("Topping", base .. "Topping")
	table.insert(ShopConfig.Toppings, {
		Id = base .. "Topping", DisplayName = theme.Name .. " Charm Packet", Price = ShopConfig.ROBUX_ONLY,
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
-- Every item has a rarity, worked out from its coin price (pricier = rarer).
-- Monthly Robux items are Legendary. The Daily Squishy rolls a rarity with
-- these chances first, then picks an item of that rarity.
export type Rarity = "Common" | "Uncommon" | "Rare" | "Epic" | "Legendary"
export type RarityInfo = { Name: Rarity, Chance: number, Color: Color3, MaxPrice: number }

ShopConfig.Rarities = {
	{ Name = "Common", Chance = 40, Color = rgb(200, 205, 215), MaxPrice = 60 },
	{ Name = "Uncommon", Chance = 30, Color = rgb(110, 220, 120), MaxPrice = 100 },
	{ Name = "Rare", Chance = 20, Color = rgb(90, 170, 255), MaxPrice = 160 },
	{ Name = "Epic", Chance = 8, Color = rgb(190, 110, 255), MaxPrice = 250 },
	{ Name = "Legendary", Chance = 2, Color = rgb(255, 200, 60), MaxPrice = math.huge },
} :: { RarityInfo }

function ShopConfig.rarityOf(item: ShopItem): RarityInfo
	if item.Robux then
		return ShopConfig.Rarities[#ShopConfig.Rarities]
	end
	for _, rarity in ShopConfig.Rarities do
		if item.Price <= rarity.MaxPrice then
			return rarity
		end
	end
	return ShopConfig.Rarities[#ShopConfig.Rarities]
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
