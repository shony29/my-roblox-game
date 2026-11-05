--!strict
--[[
	ShopService
	Handles buying and equipping jelly colors with coins.
	The client only sends the Id of the color it wants. The SERVER looks up
	the real price, checks the player can afford it and doesn't own it
	already, and only then takes the coins.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerData = require(script.Parent.PlayerData)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local MAX_ID_LENGTH = 40

local ShopService = {}

local canUseShop = RateLimiter.new(6, 2)

-- Shared checks for both buying and equipping.
local function validateRequest(player: Player, colorId: unknown): (string?, string?)
	if not canUseShop(player) then
		return nil, "Slow down a little!"
	end
	if typeof(colorId) ~= "string" or #colorId > MAX_ID_LENGTH then
		return nil, "That isn't a valid item."
	end
	if not ShopCatalog.find(colorId) then
		return nil, "That item doesn't exist."
	end
	if not PlayerData.get(player) then
		return nil, "Your data is still loading, try again in a moment."
	end
	return colorId, nil
end

local function onBuy(player: Player, colorId: unknown): (boolean, string)
	local id, problem = validateRequest(player, colorId)
	local item = if id then ShopCatalog.find(id) else nil
	local data = PlayerData.get(player)
	if not item or not data then
		return false, problem or "Something went wrong."
	end
	if data.OwnedColors[item.Id] then
		return false, "You already own this color."
	end
	if data.Coins < item.Price then
		return false, `You need {item.Price - data.Coins} more coins.`
	end

	PlayerData.update(player, function(d)
		d.Coins -= item.Price
		d.OwnedColors[item.Id] = true
		d.EquippedColor = item.Id
	end)
	PlayerData.requestSave(player) -- purchases are important, so save soon
	return true, `You bought {item.DisplayName}!`
end

local function onEquip(player: Player, colorId: unknown): (boolean, string)
	local id, problem = validateRequest(player, colorId)
	local data = PlayerData.get(player)
	if not id or not data then
		return false, problem or "Something went wrong."
	end
	if not data.OwnedColors[id] then
		return false, "You don't own that color yet."
	end
	PlayerData.update(player, function(d)
		d.EquippedColor = id
	end)
	return true, "Equipped!"
end

function ShopService.start()
	Remotes.func("BuyColor").OnServerInvoke = onBuy
	Remotes.func("EquipColor").OnServerInvoke = onEquip
end

return ShopService
