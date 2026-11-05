--!strict
--[[
	ShopCatalog
	The list of jelly colors players can buy with coins.
	The client uses it to draw the shop; the SERVER uses it to decide what
	things really cost, so a cheater can't change a price.

	To add a color, copy a line and give it a new, unique Id.
]]

local Types = require(script.Parent.Types)

local ShopCatalog = {}

-- Everybody owns this one for free.
ShopCatalog.DefaultColorId = "Lime"

local COLORS: { Types.ColorItem } = {
	{ Id = "Lime", DisplayName = "Lime", Color = Color3.fromRGB(140, 230, 90), Price = 0 },
	{ Id = "Bubblegum", DisplayName = "Bubblegum", Color = Color3.fromRGB(255, 130, 190), Price = 30 },
	{ Id = "Blueberry", DisplayName = "Blueberry", Color = Color3.fromRGB(90, 140, 255), Price = 50 },
	{ Id = "Tangerine", DisplayName = "Tangerine", Color = Color3.fromRGB(255, 160, 60), Price = 75 },
	{ Id = "Grape", DisplayName = "Grape", Color = Color3.fromRGB(160, 100, 230), Price = 100 },
	{ Id = "Lemon", DisplayName = "Lemon", Color = Color3.fromRGB(255, 230, 80), Price = 150 },
	{ Id = "Midnight", DisplayName = "Midnight", Color = Color3.fromRGB(45, 45, 70), Price = 250 },
}
ShopCatalog.Colors = COLORS

-- Look up a color by its Id. Returns nil if it doesn't exist.
function ShopCatalog.find(id: string): Types.ColorItem?
	for _, item in COLORS do
		if item.Id == id then
			return item
		end
	end
	return nil
end

return ShopCatalog
