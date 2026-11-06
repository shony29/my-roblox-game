--!strict
--[[
	ShopService (server)
	====================
	The server is in charge of the shop. A player's device can only ask
	"buy item X" or "equip item X". For every request the server checks:

	  1. Not too fast (a small cooldown stops button spamming).
	  2. The item Id is a short string and the item really exists.
	  3. Buying: they don't own it yet and have enough coins.
	     Equipping: they own it (free items are owned by everyone).
	     Upgrading a gun: they own the gun, it isn't at the top level yet,
	     and they have enough coins (price: Config/UpgradeConfig.cost).

	Only then does it change anything: coins and owned items are updated in
	PlayerDataService (which saves them), and Cosmetics shows the new look.
	The price always comes from ShopConfig on the server, never the client.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ShopConfig = require(Shared:WaitForChild("Config"):WaitForChild("ShopConfig"))
local ShopRemotes = require(Shared:WaitForChild("Net"):WaitForChild("ShopRemotes"))
local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local Cosmetics = require(script.Parent:WaitForChild("CosmeticsService"))
local UpgradeConfig = require(Shared:WaitForChild("Config"):WaitForChild("UpgradeConfig"))

local MAX_ID_LENGTH = 64

local ShopService = {}

local lastRequestAt: { [Player]: number } = {}
local saveScheduled: { [Player]: boolean } = {}

-- Returns true if the player is sending requests too quickly.
local function isTooFast(player: Player): boolean
	local now = os.clock()
	local last = lastRequestAt[player]
	if last and now - last < ShopConfig.RequestCooldown then
		return true
	end
	lastRequestAt[player] = now
	return false
end

-- Turns whatever the client sent into a real shop item, or nil.
local function readItem(raw: unknown): ShopConfig.ShopItem?
	if typeof(raw) ~= "string" or #raw == 0 or #raw > MAX_ID_LENGTH then
		return nil
	end
	return ShopConfig.getItem(raw)
end

-- Saves soon after a purchase. Quick purchases in a row share one save.
local function scheduleSave(player: Player)
	if saveScheduled[player] then
		return
	end
	saveScheduled[player] = true
	task.delay(ShopConfig.SaveDelay, function()
		saveScheduled[player] = nil
		if player.Parent == Players then
			PlayerDataService.saveNow(player)
		end
	end)
end

-- Equips an item the player owns. Also used right after buying.
function ShopService.equip(player: Player, item: ShopConfig.ShopItem): (boolean, string)
	if PlayerDataService.getData(player) == nil then
		return false, "Your items are still loading. Try again in a moment!"
	end
	if not PlayerDataService.ownsItem(player, item.Id) then
		return false, "You don't own " .. item.DisplayName .. " yet."
	end
	if item.Category == "Weapon" then
		return true, item.DisplayName .. " is in your loadout!" -- guns aren't worn, owning is enough
	end
	if not PlayerDataService.setEquippedItem(player, item.Category, item.Id) then
		return false, "Couldn't equip that. Try again!"
	end
	Cosmetics.refresh(player)
	return true, "Equipped " .. item.DisplayName .. "!"
end

-- Buys an item and puts it on straight away.
function ShopService.buy(player: Player, item: ShopConfig.ShopItem): (boolean, string)
	if item.Robux then
		return false, item.DisplayName .. " is bought with Robux." -- never with coins
	end
	local result = PlayerDataService.purchaseItem(player, item.Id, item.Price)
	if result == "NotLoaded" then
		return false, "Your coins are still loading. Try again in a moment!"
	elseif result == "AlreadyOwned" then
		return false, "You already own " .. item.DisplayName .. "."
	elseif result == "NotEnoughCoins" then
		return false, "Not enough coins yet. Keep playing to earn more!"
	end
	scheduleSave(player)
	ShopService.equip(player, item)
	return true, "You got " .. item.DisplayName .. "!"
end

local function onBuy(player: Player, rawId: unknown): (boolean, string)
	if isTooFast(player) then
		return false, "Slow down a little!"
	end
	local item = readItem(rawId)
	if item == nil then
		return false, "That item doesn't exist."
	end
	return ShopService.buy(player, item)
end

local function onEquip(player: Player, rawId: unknown): (boolean, string)
	if isTooFast(player) then
		return false, "Slow down a little!"
	end
	local item = readItem(rawId)
	if item == nil then
		return false, "That item doesn't exist."
	end
	return ShopService.equip(player, item)
end

-- Buys the next upgrade level for a gun the player owns.
local function onUpgrade(player: Player, rawId: unknown): (boolean, string)
	if isTooFast(player) then
		return false, "Slow down a little!"
	end
	local item = readItem(rawId)
	local gun = if item and item.Category == "Weapon" then ShopConfig.getWeapon(item.Id) else nil
	if item == nil or gun == nil then
		return false, "That gun doesn't exist."
	end
	local data = PlayerDataService.getData(player)
	if data == nil then
		return false, "Your coins are still loading. Try again in a moment!"
	end
	if not PlayerDataService.ownsItem(player, item.Id) then
		return false, "Get " .. item.DisplayName .. " first, then you can upgrade it."
	end
	local nextLevel = (data.gunLevels[gun.WeaponId] or 0) + 1
	local result, newLevel = PlayerDataService.buyGunUpgrade(player, gun.WeaponId, UpgradeConfig.cost(item.Price, nextLevel))
	if result == "MaxLevel" then
		return false, item.DisplayName .. " is already fully upgraded!"
	elseif result == "NotEnoughCoins" then
		return false, "Not enough coins yet. Keep playing to earn more!"
	elseif result ~= "Upgraded" then
		return false, "Your coins are still loading. Try again in a moment!"
	end
	scheduleSave(player)
	local tier = UpgradeConfig.tier(newLevel or nextLevel)
	return true, `{item.DisplayName} is now level {newLevel or nextLevel}{if tier then " (" .. tier.Name .. ")" else ""}!`
end

local started = false

function ShopService.start()
	if started then
		return
	end
	started = true

	local remotes = ShopRemotes.get()
	remotes.BuyItem.OnServerInvoke = onBuy
	remotes.EquipItem.OnServerInvoke = onEquip
	remotes.UpgradeGun.OnServerInvoke = onUpgrade

	Players.PlayerRemoving:Connect(function(player: Player)
		lastRequestAt[player] = nil
		saveScheduled[player] = nil
	end)

	Cosmetics.start()
end

return ShopService
