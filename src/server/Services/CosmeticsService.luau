--!strict
--[[
	Cosmetics
	=========
	Puts each player's equipped shop items on their character:
	  * Blob color: paints the blob's body.
	  * Hat: builds the hat and glues it on top of the blob.
	  * Weapon skin: paints whichever gun they are holding.

	When does it run?
	  * Every time a blob or a gun is added to a character (so after every
	    respawn and every weapon swap).
	  * Right away when the player equips something new.

	It runs on the server, so every player sees everyone's looks.
	It reads the Equipped... attributes that PlayerDataService sets.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ShopConfig = require(Shared:WaitForChild("Config"):WaitForChild("ShopConfig"))
local HatBuilder = require(Shared:WaitForChild("Cosmetics"):WaitForChild("HatBuilder"))
local BlobCharacter = require(script.Parent.Parent.Components.BlobCharacter)
local WeaponSkins = require(Shared:WaitForChild("Cosmetics"):WaitForChild("WeaponSkins"))
local GunUpgrade = require(Shared:WaitForChild("Cosmetics"):WaitForChild("GunUpgrade"))
local UpgradeConfig = require(Shared:WaitForChild("Config"):WaitForChild("UpgradeConfig"))
local GameContract = require(Shared:WaitForChild("Net"):WaitForChild("GameContract"))

local ATTR = GameContract.PlayerAttributes

-- Names used by the other systems:
local BLOB_MODEL_NAME = "Blob" -- server/Components/BlobCharacter
local BLOB_BODY_NAME = "Body"
local GUN_MODEL_NAME = "EquippedGun" -- Server/Weapons/GunModel
local BLOB_COLOR_ATTRIBUTE = "BlobColor" -- Server/Movement/MovementService builds the blob in this color

local Cosmetics = {}

local function readString(player: Player, attribute: string): string?
	local value = player:GetAttribute(attribute)
	return if typeof(value) == "string" then value else nil
end

-- Paints the blob body and puts on the hat.
local function dressBlob(player: Player, blob: Instance)
	local body = blob:FindFirstChild(BLOB_BODY_NAME)
	if not (body and body:IsA("BasePart")) then
		return
	end

	local color = ShopConfig.getColor(readString(player, ATTR.EquippedColor))
	-- The visible blob is several pieces ("Body" is the invisible hitbox).
	BlobCharacter.setColor(blob, color.Color, color.Material, color.Reflectance)

	local hat = ShopConfig.getHat(readString(player, ATTR.EquippedHat))
	local oldHat = blob:FindFirstChild(HatBuilder.MODEL_NAME)
	if oldHat then
		if oldHat:GetAttribute("HatId") == hat.Id then
			return -- already wearing it
		end
		oldHat:Destroy()
	end
	local hatModel = HatBuilder.build(hat, body.CFrame, body.Size)
	if hatModel then
		-- Glue every hat part to the body so it follows the blob around.
		for _, part in hatModel:GetChildren() do
			if part:IsA("BasePart") then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = body
				weld.Part1 = part
				weld.Parent = part
			end
		end
		hatModel.Parent = blob
	end
end

local function paintGun(player: Player, gun: Instance)
	if not gun:IsA("Model") then
		return
	end
	local skin = ShopConfig.getSkin(readString(player, ATTR.EquippedSkin))
	if gun:GetAttribute(WeaponSkins.SKIN_ATTRIBUTE) ~= skin.Id then
		WeaponSkins.apply(gun, skin)
		gun:SetAttribute(GunUpgrade.LEVEL_ATTRIBUTE, nil) -- the skin repainted the body: re-apply the upgrade
	end
	-- Upgrade colour for the gun they're holding (Daily Squishy prize).
	local weaponId = player:GetAttribute("EquippedWeapon")
	local levels = UpgradeConfig.parse(player:GetAttribute("GunLevels"))
	GunUpgrade.apply(gun, if typeof(weaponId) == "string" then levels[weaponId] or 0 else 0)
end

local function onCharacterChild(player: Player, character: Model, child: Instance)
	if child.Parent ~= character or player.Character ~= character then
		return
	end
	if child.Name == BLOB_MODEL_NAME then
		dressBlob(player, child)
	elseif child.Name == GUN_MODEL_NAME then
		paintGun(player, child)
	end
end

local function onCharacterAdded(player: Player, character: Model)
	character.ChildAdded:Connect(function(child: Instance)
		onCharacterChild(player, character, child)
	end)
	-- The blob or gun may already be there if they were built first.
	for _, child in character:GetChildren() do
		onCharacterChild(player, character, child)
	end
end

-- Re-applies everything to the player's current character.
function Cosmetics.refresh(player: Player)
	local color = ShopConfig.getColor(readString(player, ATTR.EquippedColor))
	player:SetAttribute(BLOB_COLOR_ATTRIBUTE, color.Color)

	local character = player.Character
	if character then
		for _, child in character:GetChildren() do
			onCharacterChild(player, character, child)
		end
	end
end

local function onPlayerAdded(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
	for _, attribute in { ATTR.EquippedColor, ATTR.EquippedHat, ATTR.EquippedSkin, "GunLevels" } do
		player:GetAttributeChangedSignal(attribute):Connect(function()
			Cosmetics.refresh(player)
		end)
	end
	if player:GetAttribute(ATTR.EquippedColor) ~= nil then
		Cosmetics.refresh(player)
	end
end

local started = false

function Cosmetics.start()
	if started then
		return
	end
	started = true
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
end

return Cosmetics
