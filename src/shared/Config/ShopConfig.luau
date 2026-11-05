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

export type Category = "Color" | "Hat" | "Skin" | "Weapon"

-- What the shop needs to know about any item.
export type ShopItem = {
	Id: string,
	Category: Category,
	DisplayName: string,
	Price: number,
}

-- Blob colors
export type ColorItem = {
	Id: string,
	DisplayName: string,
	Price: number,
	Color: Color3,
	Material: Enum.Material, -- SmoothPlastic, or Neon to glow
	Reflectance: number, -- 0 = matte, 0.3 = shiny like metal
}

-- Hats. Shape picks which hat HatBuilder makes; the two colors paint it.
export type HatShape = "None" | "PartyHat" | "Cap" | "BunnyEars" | "TopHat" | "Crown"
export type HatItem = {
	Id: string,
	DisplayName: string,
	Price: number,
	Shape: HatShape,
	MainColor: Color3,
	AccentColor: Color3,
}

-- Weapon skins. "Body" is the main block of the gun, "trim" is the grip and
-- barrel. A nil color means "keep the gun's normal color".
export type SkinPattern = "None" | "Stripes" | "Spots" | "Line"
export type SkinItem = {
	Id: string,
	DisplayName: string,
	Price: number,
	BodyColor: Color3?,
	TrimColor: Color3?,
	BodyMaterial: Enum.Material,
	TrimMaterial: Enum.Material,
	Reflectance: number,
	Pattern: SkinPattern, -- extra decoration added on the gun body
	PatternColors: { Color3 },
	PatternMaterial: Enum.Material,
}

local rgb = Color3.fromRGB
local Smooth = Enum.Material.SmoothPlastic
local Neon = Enum.Material.Neon

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
	{
		Id = "Hat_None",
		DisplayName = "No Hat",
		Price = 0,
		Shape = "None",
		MainColor = rgb(255, 255, 255),
		AccentColor = rgb(255, 255, 255),
	},
	{
		Id = "Hat_Party",
		DisplayName = "Party Hat",
		Price = 50,
		Shape = "PartyHat",
		MainColor = rgb(80, 170, 255),
		AccentColor = rgb(255, 225, 60),
	},
	{
		Id = "Hat_Cap",
		DisplayName = "Sporty Cap",
		Price = 75,
		Shape = "Cap",
		MainColor = rgb(255, 70, 80),
		AccentColor = rgb(255, 255, 255),
	},
	{
		Id = "Hat_Bunny",
		DisplayName = "Bunny Ears",
		Price = 150,
		Shape = "BunnyEars",
		MainColor = rgb(255, 255, 255),
		AccentColor = rgb(255, 150, 200),
	},
	{
		Id = "Hat_TopHat",
		DisplayName = "Top Hat",
		Price = 250,
		Shape = "TopHat",
		MainColor = rgb(40, 40, 52),
		AccentColor = rgb(230, 60, 80),
	},
	{
		Id = "Hat_Crown",
		DisplayName = "Royal Crown",
		Price = 500,
		Shape = "Crown",
		MainColor = rgb(255, 200, 40),
		AccentColor = rgb(230, 40, 90),
	},
} :: { HatItem }

-- WEAPON SKINS (change the look of every gun) ------------------------------
ShopConfig.Skins = {
	{
		Id = "Skin_Classic",
		DisplayName = "Classic",
		Price = 0,
		BodyColor = nil,
		TrimColor = nil,
		BodyMaterial = Smooth,
		TrimMaterial = Smooth,
		Reflectance = 0,
		Pattern = "None",
		PatternColors = {},
		PatternMaterial = Smooth,
	},
	{
		Id = "Skin_Candy",
		DisplayName = "Candy Stripe",
		Price = 100,
		BodyColor = rgb(255, 120, 190),
		TrimColor = rgb(255, 255, 255),
		BodyMaterial = Smooth,
		TrimMaterial = Smooth,
		Reflectance = 0,
		Pattern = "Stripes",
		PatternColors = { rgb(255, 255, 255) },
		PatternMaterial = Smooth,
	},
	{
		Id = "Skin_Camo",
		DisplayName = "Camo",
		Price = 150,
		BodyColor = rgb(110, 132, 70),
		TrimColor = rgb(75, 60, 40),
		BodyMaterial = Smooth,
		TrimMaterial = Smooth,
		Reflectance = 0,
		Pattern = "Spots",
		PatternColors = { rgb(60, 85, 45), rgb(190, 170, 120), rgb(120, 90, 55) },
		PatternMaterial = Smooth,
	},
	{
		Id = "Skin_Neon",
		DisplayName = "Neon",
		Price = 300,
		BodyColor = rgb(0, 240, 255),
		TrimColor = rgb(35, 25, 60),
		BodyMaterial = Neon,
		TrimMaterial = Smooth,
		Reflectance = 0,
		Pattern = "Line",
		PatternColors = { rgb(255, 60, 220) },
		PatternMaterial = Neon,
	},
	{
		Id = "Skin_Gold",
		DisplayName = "Gold",
		Price = 500,
		BodyColor = rgb(255, 195, 45),
		TrimColor = rgb(215, 150, 30),
		BodyMaterial = Smooth,
		TrimMaterial = Smooth,
		Reflectance = 0.3,
		Pattern = "None",
		PatternColors = {},
		PatternMaterial = Smooth,
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
	{ Id = "Weapon_Pistol", WeaponId = "Pistol", DisplayName = "Pop Pistol", Price = 75, Blurb = "Precise sidearm" },
	{ Id = "Weapon_SMG", WeaponId = "SMG", DisplayName = "Buzz SMG", Price = 150, Blurb = "Fast, close range" },
	{ Id = "Weapon_Shotgun", WeaponId = "Shotgun", DisplayName = "Pump Shotgun", Price = 200, Blurb = "Huge up close" },
	{ Id = "Weapon_Sniper", WeaponId = "Sniper", DisplayName = "Sniper", Price = 300, Blurb = "One shot, long range" },
} :: { WeaponItem }

-- The shop item Id for a gun, e.g. "Rifle" -> "Weapon_Rifle".
function ShopConfig.weaponItemId(weaponId: string): string
	return "Weapon_" .. weaponId
end

-- Lookups (built once from the lists above) ---------------------------------

local items: { [string]: ShopItem } = {}
local colorsById: { [string]: ColorItem } = {}
local hatsById: { [string]: HatItem } = {}
local skinsById: { [string]: SkinItem } = {}
local weaponsById: { [string]: WeaponItem } = {}

local function register(id: string, category: Category, displayName: string, price: number)
	assert(items[id] == nil, "ShopConfig: duplicate item Id " .. id)
	assert(not string.find(id, ",", 1, true), "ShopConfig: item Ids can't contain commas: " .. id)
	items[id] = { Id = id, Category = category, DisplayName = displayName, Price = price }
end

for _, item in ShopConfig.Colors do
	register(item.Id, "Color", item.DisplayName, item.Price)
	colorsById[item.Id] = item
end
for _, item in ShopConfig.Hats do
	register(item.Id, "Hat", item.DisplayName, item.Price)
	hatsById[item.Id] = item
end
for _, item in ShopConfig.Skins do
	register(item.Id, "Skin", item.DisplayName, item.Price)
	skinsById[item.Id] = item
end
for _, item in ShopConfig.Weapons do
	register(item.Id, "Weapon", item.DisplayName, item.Price)
	weaponsById[item.Id] = item
end

function ShopConfig.getWeapon(id: string): WeaponItem?
	return weaponsById[id]
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
	return item ~= nil and item.Price <= 0
end

-- The default item Id for a category.
function ShopConfig.defaultFor(category: Category): string
	if category == "Color" then
		return ShopConfig.Defaults.Color
	elseif category == "Hat" then
		return ShopConfig.Defaults.Hat
	elseif category == "Weapon" then
		return ShopConfig.weaponItemId(ShopConfig.STARTER_WEAPON)
	end
	return ShopConfig.Defaults.Skin
end

assert(colorsById[ShopConfig.Defaults.Color], "ShopConfig: default color missing")
assert(hatsById[ShopConfig.Defaults.Hat], "ShopConfig: default hat missing")
assert(skinsById[ShopConfig.Defaults.Skin], "ShopConfig: default skin missing")

return ShopConfig
