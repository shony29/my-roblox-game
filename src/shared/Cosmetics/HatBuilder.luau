--!strict
--[[
	HatBuilder
	==========
	Builds each low-poly hat out of simple parts (blocks, balls, cylinders).

	HatBuilder.build(hat, bodyCFrame, bodySize) returns a Model with every
	part already placed on top of a blob body at `bodyCFrame` (or nil for
	"No Hat"). The server glues it onto real blobs; the shop menu uses the
	same code for its little 3D previews.

	Directions used below, from the blob's middle: +Y is up, -Z is the front
	(where the face is), X is left/right.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ShopConfig"))

type HatItem = ShopConfig.HatItem

-- The blob system hides every part added to a character unless it has this
-- attribute (see Server/Movement/BlobCharacter), so hats must carry it.
local KEEP_VISIBLE_ATTRIBUTE = "IsBlobPart"

-- Cylinders in Roblox lie on their side (along X). This stands them up.
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90))

local HatBuilder = {}

HatBuilder.MODEL_NAME = "ShopHat"

type Builder = {
	origin: CFrame,
	model: Model,
}

local function addPart(b: Builder, name: string, size: Vector3, color: Color3, localCFrame: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
	-- Bullets fly straight through hats, so a hat can never change your hitbox.
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = true
	part:SetAttribute(KEEP_VISIBLE_ATTRIBUTE, true)
	part.CFrame = b.origin * localCFrame
	part.Parent = b.model
	return part
end

local function ball(b: Builder, name: string, diameter: number, color: Color3, position: Vector3): Part
	local part = addPart(b, name, Vector3.one * diameter, color, CFrame.new(position))
	part.Shape = Enum.PartType.Ball
	return part
end

-- An upright cylinder whose bottom sits at `bottom`.
local function cylinder(b: Builder, name: string, diameter: number, height: number, color: Color3, bottom: CFrame): Part
	local part = addPart(
		b,
		name,
		Vector3.new(height, diameter, diameter),
		color,
		bottom * CFrame.new(0, height / 2, 0) * UPRIGHT
	)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- A squashed ball (a block with a sphere mesh), like the blob body itself.
local function ellipsoid(b: Builder, name: string, size: Vector3, color: Color3, localCFrame: CFrame): Part
	local part = addPart(b, name, size, color, localCFrame)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- Each hat ---------------------------------------------------------------

-- A striped cone made of stacked cylinders, tilted a little for fun.
local function partyHat(b: Builder, hat: HatItem, top: number)
	local base = CFrame.new(0, top - 0.25, 0) * CFrame.Angles(0, 0, math.rad(-12))
	local tiers = 5
	local tierHeight = 0.48
	for i = 1, tiers do
		local t = (i - 1) / (tiers - 1)
		local diameter = 2.0 + (0.45 - 2.0) * t
		local color = if i % 2 == 1 then hat.MainColor else hat.AccentColor
		cylinder(b, "Tier", diameter, tierHeight, color, base * CFrame.new(0, (i - 1) * tierHeight, 0))
	end
	ball(b, "Pompom", 0.6, hat.AccentColor, (base * CFrame.new(0, tiers * tierHeight + 0.15, 0)).Position)
end

-- A snug dome with a round brim over the eyes.
local function cap(b: Builder, hat: HatItem, top: number)
	local domeCenter = top - 0.65
	ellipsoid(b, "Dome", Vector3.new(3.5, 2.0, 3.5), hat.MainColor, CFrame.new(0, domeCenter, 0))
	local brim = cylinder(
		b,
		"Brim",
		2.2,
		0.14,
		hat.MainColor,
		CFrame.new(0, domeCenter - 0.1, -1.55) * CFrame.Angles(math.rad(-8), 0, 0)
	)
	brim.Color = hat.MainColor:Lerp(Color3.new(0, 0, 0), 0.15)
	ball(b, "Button", 0.35, hat.AccentColor, Vector3.new(0, domeCenter + 1.0, 0))
	-- A white stripe across the front.
	ellipsoid(b, "Stripe", Vector3.new(0.35, 1.6, 3.55), hat.AccentColor, CFrame.new(0, domeCenter + 0.1, 0))
end

-- Two tall ears with pink insides, leaning outwards.
local function bunnyEars(b: Builder, hat: HatItem, top: number)
	for _, side in { -1, 1 } do
		local ear = CFrame.new(side * 0.7, top - 0.3, 0)
			* CFrame.Angles(0, 0, math.rad(-side * 14))
			* CFrame.new(0, 1.1, 0)
		ellipsoid(b, "Ear", Vector3.new(0.75, 2.4, 0.4), hat.MainColor, ear)
		ellipsoid(b, "EarInside", Vector3.new(0.42, 1.7, 0.12), hat.AccentColor, ear * CFrame.new(0, -0.05, -0.16))
	end
end

-- A wide brim, a tall crown and a colored band.
local function topHat(b: Builder, hat: HatItem, top: number)
	local base = CFrame.new(0, top - 0.3, 0) * CFrame.Angles(0, 0, math.rad(8))
	cylinder(b, "Brim", 2.9, 0.16, hat.MainColor, base)
	cylinder(b, "Crown", 1.85, 1.9, hat.MainColor, base * CFrame.new(0, 0.16, 0))
	cylinder(b, "Band", 1.9, 0.38, hat.AccentColor, base * CFrame.new(0, 0.16, 0))
end

-- A gold band with pointy diamonds on top and gems around it.
local function crown(b: Builder, hat: HatItem, top: number)
	local base = CFrame.new(0, top - 0.3, 0)
	local band = cylinder(b, "Band", 2.3, 0.6, hat.MainColor, base)
	band.Reflectance = 0.2
	local points = 6
	for i = 1, points do
		local around = base * CFrame.Angles(0, (i - 1) * (2 * math.pi / points), 0)
		-- A block turned 45 degrees looks like a diamond; its top half pokes up.
		local spike = addPart(
			b,
			"Point",
			Vector3.new(0.62, 0.62, 0.18),
			hat.MainColor,
			around * CFrame.new(0, 0.6, -1.08) * CFrame.Angles(0, 0, math.rad(45))
		)
		spike.Reflectance = 0.2
		ball(b, "TipGem", 0.24, hat.AccentColor, (around * CFrame.new(0, 1.05, -1.08)).Position)
		ball(b, "Gem", 0.3, hat.AccentColor, (around * CFrame.new(0, 0.3, -1.17)).Position)
	end
end

--[[
	Builds the hat for `hat`, sitting on a blob body at `bodyCFrame` whose
	size is `bodySize`. Returns nil for "No Hat". The parts are not glued
	to anything yet; the caller does that.
]]
function HatBuilder.build(hat: HatItem, bodyCFrame: CFrame, bodySize: Vector3): Model?
	if hat.Shape == "None" then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = HatBuilder.MODEL_NAME
	model:SetAttribute(KEEP_VISIBLE_ATTRIBUTE, true)
	model:SetAttribute("HatId", hat.Id)

	local b: Builder = { origin = bodyCFrame, model = model }
	local top = bodySize.Y / 2 -- the top of the blob, measured from its middle

	if hat.Shape == "PartyHat" then
		partyHat(b, hat, top)
	elseif hat.Shape == "Cap" then
		cap(b, hat, top)
	elseif hat.Shape == "BunnyEars" then
		bunnyEars(b, hat, top)
	elseif hat.Shape == "TopHat" then
		topHat(b, hat, top)
	elseif hat.Shape == "Crown" then
		crown(b, hat, top)
	end
	return model
end

return HatBuilder
