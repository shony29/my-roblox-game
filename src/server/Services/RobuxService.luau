--!strict
--[[
	RobuxService: grants items bought with Robux (the monthly themed items).

	Robux purchases go through Roblox: the player's client shows Roblox's own
	purchase window (MarketplaceService:PromptProductPurchase), and after they
	pay, Roblox calls ProcessReceipt here on the server. Only this server code
	ever grants a Robux item. For each receipt:
	  * the product must be one of ours (Config/ShopConfig.ProductIds);
	  * the item is added to their items, and the purchase id is remembered,
	    so the same purchase can never be granted twice;
	  * we only answer "PurchaseGranted" after their data has saved. If
	    anything fails we answer "NotProcessedYet" and Roblox tries again
	    later, so a player is never charged without getting their item.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ShopService = require(script.Parent.ShopService)

local RobuxService = {}
local started = false

local function processReceipt(receipt: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet -- they left; Roblox retries when they're back
	end
	local item = ShopConfig.getByProductId(receipt.ProductId)
	if not item then
		warn(`[RobuxService] Product {receipt.ProductId} isn't listed in ShopConfig.ProductIds; not granting.`)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local result = PlayerDataService.grantPurchase(player, item.Id, tostring(receipt.PurchaseId))
	if result == "NotLoaded" then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if not PlayerDataService.saveNow(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if result == "Granted" and item.Category ~= "Weapon" then
		ShopService.equip(player, item) -- put it on straight away
	end
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function RobuxService.start()
	if started then
		return
	end
	started = true
	MarketplaceService.ProcessReceipt = processReceipt
end

return RobuxService
