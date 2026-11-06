--!strict
--[[
	ItemPreview
	===========
	The little 3D pictures on each shop card:
	  * Colors:     the real jelly slime, painted in that colour.
	  * Squishies:  the slime (in your colour) wearing the squishy.
	  * Skins:      a gun painted with the skin.
	The slime comes from Shared/Cosmetics/BlobLook (the same shape as the
	real character) and the squishies and skins use the exact same
	building code as the game (HatBuilder and WeaponSkins), so what you
	see is what you get.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ShopConfig = require(Shared:WaitForChild("Config"):WaitForChild("ShopConfig"))
local HatBuilder = require(Shared:WaitForChild("Cosmetics"):WaitForChild("HatBuilder"))
local WeaponSkins = require(Shared:WaitForChild("Cosmetics"):WaitForChild("WeaponSkins"))
local BlobLook = require(Shared:WaitForChild("Cosmetics"):WaitForChild("BlobLook"))
local WeaponConfig = require(Shared:WaitForChild("Config"):WaitForChild("WeaponConfig"))
local MovementConfig = require(Shared:WaitForChild("Config"):WaitForChild("MovementConfig"))

local TRIM_COLOR = Color3.fromRGB(45, 45, 55) -- matches Server/Weapons/GunModel

local ItemPreview = {}

local function makeViewport(parent: GuiObject, cameraCFrame: CFrame, fieldOfView: number): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "Preview"
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(190, 190, 200)
	viewport.LightColor = Color3.new(1, 1, 1)
	viewport.LightDirection = Vector3.new(-1, -2, 1)
	viewport.Parent = parent

	local camera = Instance.new("Camera")
	camera.FieldOfView = fieldOfView
	camera.CFrame = cameraCFrame
	camera.Parent = viewport
	viewport.CurrentCamera = camera
	return viewport
end

local function previewPart(name: string, size: Vector3, color: Color3, cframe: CFrame, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CFrame = cframe
	part.Parent = parent
	return part
end

-- The real jelly slime in this colour (shine, glow and all).
function ItemPreview.color(parent: GuiObject, item: ShopConfig.ColorItem)
	local viewport = makeViewport(parent, CFrame.lookAt(Vector3.new(2.4, 3.4, -8.2), Vector3.new(0, 1.9, 0)), 40)
	local blob = BlobLook.build(item.Color, item.Material, item.Reflectance)
	blob.Parent = viewport
end

--[[
	The slime wearing `hat`. Returns a function that recolours the slime,
	so the picture can match the player's equipped colour.
]]
function ItemPreview.hat(parent: GuiObject, hat: ShopConfig.HatItem, blobColor: Color3): (Color3) -> ()
	local viewport = makeViewport(parent, CFrame.lookAt(Vector3.new(2.6, 5.6, -9.2), Vector3.new(0, 4, 0)), 40)
	local blob = BlobLook.build(blobColor)
	blob.Parent = viewport

	-- Placed exactly like the real game: on top of the slime's hitbox.
	local hitbox = MovementConfig.BlobHitboxSize
	local model = HatBuilder.build(hat, CFrame.new(0, hitbox.Y / 2, 0), hitbox)
	if model then
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end
		model.Parent = viewport
	end

	return function(color: Color3)
		BlobLook.recolor(blob, color)
	end
end

-- A small gun painted with `skin`.
function ItemPreview.skin(parent: GuiObject, skin: ShopConfig.SkinItem)
	local viewport = makeViewport(parent, CFrame.lookAt(Vector3.new(4.2, 1.5, -1.6), Vector3.new(0, -0.1, -0.35)), 40)

	local firstWeapon = WeaponConfig.get(WeaponConfig.Order[1])
	local bodyColor = if firstWeapon then firstWeapon.GunColor else Color3.fromRGB(80, 170, 255)
	local length = if firstWeapon then firstWeapon.GunLength else 2.2

	-- The same three blocks as Server/Weapons/GunModel.
	local gun = Instance.new("Model")
	gun.Name = "PreviewGun"
	local body = previewPart("Body", Vector3.new(0.35, 0.45, length), bodyColor, CFrame.new(), gun)
	previewPart("Grip", Vector3.new(0.3, 0.6, 0.35), TRIM_COLOR, CFrame.new(0, -0.45, length / 2 - 0.25), gun)
	previewPart(
		"Barrel",
		Vector3.new(0.2, 0.2, 0.5),
		TRIM_COLOR,
		body.CFrame * CFrame.new(0, 0.05, -length / 2 - 0.25),
		gun
	)
	gun.Parent = viewport

	WeaponSkins.apply(gun, skin)
	for _, part in gun:GetChildren() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
end

return ItemPreview
