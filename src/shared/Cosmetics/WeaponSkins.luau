--!strict
--[[
	WeaponSkins
	===========
	Paints a gun model with a skin from ShopConfig.

	A gun (see Server/Weapons/GunModel) is a Model with a part called "Body"
	plus some "trim" parts (the grip and the barrel). A skin recolors them
	and can add simple decorations: candy stripes, camo spots or a neon line.

	The first time a gun is painted, each part's original color is written
	down in an attribute, so the Classic skin can put it back later.
	The server uses this on real guns; the shop menu uses it on previews.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ShopConfig"))

type SkinItem = ShopConfig.SkinItem

local KEEP_VISIBLE_ATTRIBUTE = "IsBlobPart" -- see Server/Movement/BlobCharacter
local DECORATION_ATTRIBUTE = "SkinDecoration"
local ORIGINAL_COLOR_ATTRIBUTE = "OriginalColor"

local WeaponSkins = {}

WeaponSkins.SKIN_ATTRIBUTE = "SkinId"

local function makeDecoration(name: string, size: Vector3, color: Color3, material: Enum.Material, cframe: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	part.CanQuery = false -- bullets ignore it
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.CFrame = cframe
	part:SetAttribute(KEEP_VISIBLE_ATTRIBUTE, true)
	part:SetAttribute(DECORATION_ATTRIBUTE, true)
	return part
end

local function addDecorations(gun: Model, body: BasePart, skin: SkinItem)
	local colors = skin.PatternColors
	if skin.Pattern == "None" or #colors == 0 then
		return
	end
	local size = body.Size
	local pieces: { Part } = {}

	if skin.Pattern == "Stripes" then
		-- Thin rings around the body along its length, like a candy cane.
		local count = math.max(2, math.floor(size.Z / 0.55))
		for i = 1, count do
			local z = -size.Z / 2 + (i - 0.5) * (size.Z / count)
			local color = colors[(i - 1) % #colors + 1]
			table.insert(
				pieces,
				makeDecoration(
					"Stripe",
					Vector3.new(size.X + 0.04, size.Y + 0.04, 0.12),
					color,
					skin.PatternMaterial,
					body.CFrame * CFrame.new(0, 0, z)
				)
			)
		end
	elseif skin.Pattern == "Spots" then
		-- Flat patches on both sides and on top (always the same layout).
		local spots = {
			{ 0.25, -0.30, 0.18, 0.40 },
			{ -0.10, 0.05, 0.16, 0.30 },
			{ 0.15, 0.30, 0.20, 0.35 },
			{ -0.20, -0.05, 0.14, 0.25 },
		}
		for index, spot in spots do
			local y, zFraction, height, length = spot[1], spot[2], spot[3], spot[4]
			local color = colors[(index - 1) % #colors + 1]
			for _, side in { -1, 1 } do
				table.insert(
					pieces,
					makeDecoration(
						"Spot",
						Vector3.new(0.04, height, length),
						color,
						skin.PatternMaterial,
						body.CFrame * CFrame.new(side * (size.X / 2 + 0.02), y * size.Y / 2, zFraction * size.Z)
					)
				)
			end
			table.insert(
				pieces,
				makeDecoration(
					"Spot",
					Vector3.new(height, 0.04, length),
					colors[index % #colors + 1],
					skin.PatternMaterial,
					body.CFrame * CFrame.new(y * size.X / 2, size.Y / 2 + 0.02, -zFraction * size.Z)
				)
			)
		end
	elseif skin.Pattern == "Line" then
		-- A glowing strip along the top and both sides.
		table.insert(
			pieces,
			makeDecoration(
				"Line",
				Vector3.new(0.1, 0.05, size.Z * 0.85),
				colors[1],
				skin.PatternMaterial,
				body.CFrame * CFrame.new(0, size.Y / 2 + 0.025, 0)
			)
		)
		for _, side in { -1, 1 } do
			table.insert(
				pieces,
				makeDecoration(
					"Line",
					Vector3.new(0.05, 0.08, size.Z * 0.7),
					colors[1],
					skin.PatternMaterial,
					body.CFrame * CFrame.new(side * (size.X / 2 + 0.025), 0, 0)
				)
			)
		end
	end

	for _, piece in pieces do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = piece
		weld.Parent = piece
		piece.Parent = gun
	end
end

-- Paints `gun` with `skin`. Safe to call again with a different skin.
function WeaponSkins.apply(gun: Model, skin: SkinItem)
	local body: BasePart? = nil
	for _, child in gun:GetChildren() do
		if child:GetAttribute(DECORATION_ATTRIBUTE) then
			child:Destroy() -- remove the last skin's decorations
		elseif child:IsA("BasePart") then
			local original = child:GetAttribute(ORIGINAL_COLOR_ATTRIBUTE)
			if typeof(original) ~= "Color3" then
				original = child.Color
				child:SetAttribute(ORIGINAL_COLOR_ATTRIBUTE, original)
			end
			local isBody = child.Name == "Body"
			if isBody then
				body = child
			end
			local newColor = if isBody then skin.BodyColor else skin.TrimColor
			child.Color = newColor or original :: Color3
			child.Material = if isBody then skin.BodyMaterial else skin.TrimMaterial
			child.Reflectance = skin.Reflectance
		end
	end
	if body then
		addDecorations(gun, body, skin)
	end
	gun:SetAttribute(WeaponSkins.SKIN_ATTRIBUTE, skin.Id)
end

return WeaponSkins
