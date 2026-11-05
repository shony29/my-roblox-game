--!strict
--[[
	ItemPreview
	===========
	The little pictures on each shop card:
	  * Colors: a flat round blob face in that color.
	  * Hats:   a tiny 3D blob wearing the hat (in a ViewportFrame).
	  * Skins:  a tiny 3D gun painted with the skin.
	Hats and skins use the exact same building code as the real game
	(Shared/Shop/HatBuilder and WeaponSkins), so what you see is what you get.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ShopConfig = require(Shared:WaitForChild("Shop"):WaitForChild("ShopConfig"))
local HatBuilder = require(Shared:WaitForChild("Shop"):WaitForChild("HatBuilder"))
local WeaponSkins = require(Shared:WaitForChild("Shop"):WaitForChild("WeaponSkins"))
local WeaponConfig = require(Shared:WaitForChild("Weapons"):WaitForChild("WeaponConfig"))
local MovementConfig = require(Shared:WaitForChild("Movement"):WaitForChild("MovementConfig"))

local INK = Color3.fromRGB(35, 40, 60)
local TRIM_COLOR = Color3.fromRGB(45, 45, 55) -- matches Server/Weapons/GunModel

local ItemPreview = {}

local function round(parent: GuiObject)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = parent
end

-- A flat blob face: a colored circle with two googly eyes.
function ItemPreview.color(parent: GuiObject, item: ShopConfig.ColorItem)
	local blob = Instance.new("Frame")
	blob.Name = "Swatch"
	blob.AnchorPoint = Vector2.new(0.5, 0.5)
	blob.Position = UDim2.fromScale(0.5, 0.55)
	blob.Size = UDim2.fromOffset(84, 74)
	blob.BackgroundColor3 = item.Color
	blob.BorderSizePixel = 0
	round(blob)
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 3
	stroke.Parent = blob
	if item.Material == Enum.Material.Neon or item.Reflectance > 0 then
		-- A soft shine so glowing and shiny colors stand out.
		local gradient = Instance.new("UIGradient")
		gradient.Rotation = -45
		gradient.Color = ColorSequence.new(Color3.new(1, 1, 1), item.Color)
		gradient.Transparency = NumberSequence.new(0, 0)
		gradient.Offset = Vector2.new(-0.4, -0.4)
		gradient.Parent = blob
	end
	blob.Parent = parent

	for _, side in { -1, 1 } do
		local eye = Instance.new("Frame")
		eye.Name = "Eye"
		eye.AnchorPoint = Vector2.new(0.5, 0.5)
		eye.Position = UDim2.new(0.5, side * 16, 0.4, 0)
		eye.Size = UDim2.fromOffset(22, 22)
		eye.BackgroundColor3 = Color3.new(1, 1, 1)
		eye.BorderSizePixel = 0
		round(eye)
		eye.Parent = blob

		local pupil = Instance.new("Frame")
		pupil.Name = "Pupil"
		pupil.AnchorPoint = Vector2.new(0.5, 0.5)
		pupil.Position = UDim2.fromScale(0.5, 0.6)
		pupil.Size = UDim2.fromOffset(11, 11)
		pupil.BackgroundColor3 = INK
		pupil.BorderSizePixel = 0
		round(pupil)
		pupil.Parent = eye
	end
end

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

--[[
	A small blob wearing `hat`. Returns a function that recolors the blob,
	so the preview can match the player's equipped color.
]]
function ItemPreview.hat(parent: GuiObject, hat: ShopConfig.HatItem, blobColor: Color3): (Color3) -> ()
	local viewport = makeViewport(parent, CFrame.lookAt(Vector3.new(3, 3.2, -8.6), Vector3.new(0, 1.2, 0)), 40)

	local bodySize = MovementConfig.BlobBodySize
	local body = previewPart("Body", bodySize, blobColor, CFrame.new(), viewport)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = body

	for _, side in { -1, 1 } do
		local eye =
			previewPart("Eye", Vector3.one * 1.1, Color3.new(1, 1, 1), CFrame.new(side * 0.75, 0.45, -1.75), viewport)
		eye.Shape = Enum.PartType.Ball
		local pupil = previewPart("Pupil", Vector3.one * 0.55, INK, CFrame.new(side * 0.75, 0.4, -2.1), viewport)
		pupil.Shape = Enum.PartType.Ball
	end

	local model = HatBuilder.build(hat, CFrame.new(), bodySize)
	if model then
		for _, part in model:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end
		model.Parent = viewport
	end

	return function(color: Color3)
		body.Color = color
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
