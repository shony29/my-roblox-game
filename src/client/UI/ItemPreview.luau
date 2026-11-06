--!strict
--[[
	ItemPreview
	===========
	The little 3D pictures on each shop card:
	  * Colors:     the real jelly slime, painted in that colour.
	  * Squishies:  the slime (in your colour) wearing the squishy.
	  * Skins:      the Auto Rifle painted with the skin.
	  * Guns:       each gun in its own colours (Cosmetics/GunBuilder).
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
local GunBuilder = require(Shared:WaitForChild("Cosmetics"):WaitForChild("GunBuilder"))
local WeaponConfig = require(Shared:WaitForChild("Config"):WaitForChild("WeaponConfig"))
local MovementConfig = require(Shared:WaitForChild("Config"):WaitForChild("MovementConfig"))

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

-- Shows a gun from the side (a little from above), filling the picture.
local function showGun(parent: GuiObject, gun: Model)
	for _, part in gun:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	local box, size = gun:GetBoundingBox()
	local center = box.Position
	local distance = math.max(size.Z, size.Y * 1.6) * 1.75
	local viewport = makeViewport(parent, CFrame.lookAt(center + Vector3.new(distance, distance * 0.3, distance * 0.12), center), 30)
	gun.Parent = viewport
end

-- The Auto Rifle painted with `skin`.
function ItemPreview.skin(parent: GuiObject, skin: ShopConfig.SkinItem)
	local stats = WeaponConfig.get(WeaponConfig.Order[1])
	if not stats then
		return
	end
	local gun = GunBuilder.build(stats, CFrame.new(), { anchored = true })
	WeaponSkins.apply(gun, skin)
	showGun(parent, gun)
end

-- A gun in its own colours (the Guns tab and its details window).
function ItemPreview.weapon(parent: GuiObject, stats: WeaponConfig.WeaponStats)
	showGun(parent, GunBuilder.build(stats, CFrame.new(), { anchored = true }))
end

return ItemPreview
