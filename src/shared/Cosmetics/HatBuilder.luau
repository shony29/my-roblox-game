--!strict
--[[
	HatBuilder: builds the SQUISHY a slime wears on top (the shop's
	"Squishies" tab). Used by the server (on real characters) and by the
	shop's 3D pictures, so what you see in the shop is what you get.

	Each squishy is modelled on real squishy toys: soft rounded shapes
	(stretched spheres), pastel colours and, on most of them, a cute face
	with shiny eyes, rosy cheeks and a little smile. The face is made of
	tiny parts (not a SurfaceGui) so it shows in the shop pictures too.

	  Dumpling   a soft bun with swirled pleats and a blushing peak
	  Butter     a chunky butter block with a melting pat and drips
	  JellyCube  a see-through jelly cube with glitter floating inside
	  Donut      a frosted ring donut with sprinkles
	  CakeSlice  a little layer cake with frosting drips and a cherry
	  IceCream   a waffle cone with a scoop, choc chips and a cherry
	  Popcorn    a striped bucket heaped with popcorn

	(HatBuilder.buildBall also makes the round squishy ball with a face
	that floats in the Daily Squishy room's glass dome.)

	They never collide and bullets fly straight through them, so a squishy
	can never change your hitbox. (Internally the category is still "Hat",
	so older saves and the EquippedHat attribute keep working.)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ShopConfig"))

type HatItem = ShopConfig.HatItem

-- The blob hides every part added to a character unless it has this
-- attribute (see server/Components/BlobCharacter), so squishies carry it.
local KEEP_VISIBLE_ATTRIBUTE = "IsBlobPart"
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- stands a cylinder up
local INK = Color3.fromRGB(45, 32, 58)
local CHEEK = Color3.fromRGB(255, 125, 160)
local WHITE = Color3.new(1, 1, 1)
local BLACK = Color3.new(0, 0, 0)
local SPRINKLES = {
	Color3.fromRGB(255, 90, 110),
	Color3.fromRGB(255, 200, 60),
	Color3.fromRGB(110, 210, 120),
	Color3.fromRGB(90, 170, 255),
	Color3.fromRGB(190, 120, 255),
	Color3.fromRGB(255, 255, 255),
}

local HatBuilder = {}

HatBuilder.MODEL_NAME = "ShopHat"

type Builder = {
	origin: CFrame, -- the middle of the slime's hitbox
	model: Model,
	random: Random, -- seeded from the item, so every player sees the same sprinkles
}

local function addPart(b: Builder, name: string, size: Vector3, color: Color3, localCFrame: CFrame): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Reflectance = 0.03 -- a soft-touch sheen
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = false
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
	local part = addPart(b, name, Vector3.new(height, diameter, diameter), color, bottom * CFrame.new(0, height / 2, 0) * UPRIGHT)
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- A squashed ball (a block with a sphere mesh): soft, like a real squishy.
local function ellipsoid(b: Builder, name: string, size: Vector3, color: Color3, localCFrame: CFrame): Part
	local part = addPart(b, name, size, color, localCFrame)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- A box with rounded upright edges and (optionally) a soft pillowy top.
local function roundedBox(b: Builder, name: string, size: Vector3, radius: number, color: Color3, bottom: CFrame, pillow: boolean): { Part }
	local parts: { Part } = {}
	local center = bottom * CFrame.new(0, size.Y / 2, 0)
	table.insert(parts, addPart(b, name, Vector3.new(size.X - radius * 2, size.Y, size.Z), color, center))
	table.insert(parts, addPart(b, name, Vector3.new(size.X, size.Y, size.Z - radius * 2), color, center))
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local corner = addPart(b, name, Vector3.new(size.Y, radius * 2, radius * 2), color,
				center * CFrame.new(sx * (size.X / 2 - radius), 0, sz * (size.Z / 2 - radius)) * UPRIGHT)
			corner.Shape = Enum.PartType.Cylinder
			table.insert(parts, corner)
		end
	end
	if pillow then
		table.insert(parts, ellipsoid(b, name, Vector3.new(size.X * 0.97, math.min(size.Y * 0.4, radius * 1.6), size.Z * 0.97), color, center * CFrame.new(0, size.Y / 2, 0)))
	end
	return parts
end

--[[
	A cute face. `center` is the middle of the face on the squishy's front
	(its -Z side faces out), `scale` sizes it, and `radius` is roughly how
	round the surface is there, so the features hug the curve (nil = flat).
]]
local function kawaiiFace(b: Builder, center: CFrame, scale: number, radius: number?)
	local function place(x: number, y: number, push: number): CFrame
		local sink = 0
		if radius then
			sink = radius - math.sqrt(math.max(radius * radius - (x * x + y * y), 0))
		end
		return center * CFrame.new(x, y, sink - push)
	end
	local s = scale
	for _, side in { -1, 1 } do
		ellipsoid(b, "Eye", Vector3.new(0.2, 0.3, 0.08) * s, INK, place(side * 0.27 * s, 0.05 * s, 0.01)).CastShadow = false
		ellipsoid(b, "EyeShine", Vector3.new(0.08, 0.1, 0.04) * s, WHITE, place((side * 0.27 + 0.04) * s, 0.11 * s, 0.045 * s)).CastShadow = false
		local cheek = ellipsoid(b, "Cheek", Vector3.new(0.24, 0.12, 0.04) * s, CHEEK, place(side * 0.5 * s, -0.1 * s, 0.01))
		cheek.Transparency = 0.35
		cheek.CastShadow = false
	end
	-- A small smile: dots along the bottom of a circle.
	for i = 0, 4 do
		local angle = math.rad(210 + i * 30)
		local x = math.cos(angle) * 0.1 * s
		local y = -0.04 * s + math.sin(angle) * 0.1 * s
		ellipsoid(b, "Smile", Vector3.new(0.055, 0.055, 0.04) * s, INK, place(x, y, 0.02)).CastShadow = false
	end
end

-- A point on the surface of an ellipsoid (`size` = its full size) in direction `dir`.
local function onEllipsoid(center: CFrame, size: Vector3, dir: Vector3): CFrame
	local unit = dir.Unit
	return center * CFrame.new(unit.X * size.X / 2, unit.Y * size.Y / 2, unit.Z * size.Z / 2)
end

-- Each squishy --------------------------------------------------------------
-- `base` is where the squishy's bottom sits (relative to the hitbox middle).

-- A soft bun with swirled pleats gathered up to a blushing peak.
local function dumpling(b: Builder, hat: HatItem, base: number)
	local dough = hat.MainColor
	local pleatColor = dough:Lerp(BLACK, 0.07)
	local blush = dough:Lerp(hat.AccentColor, 0.55)
	ellipsoid(b, "Bun", Vector3.new(2.9, 1.9, 2.8), dough, CFrame.new(0, base + 0.9, 0))
	ellipsoid(b, "BunTop", Vector3.new(2.1, 1.5, 2.0), dough, CFrame.new(0, base + 1.55, 0))
	for i = 0, 7 do
		local spin = CFrame.Angles(0, math.rad(i * 45), 0)
		ellipsoid(b, "Pleat", Vector3.new(0.3, 0.95, 1.05), pleatColor,
			CFrame.new(0, base + 1.95, 0) * spin * CFrame.new(0, 0, 0.5) * CFrame.Angles(math.rad(38), math.rad(18), 0))
	end
	local glow = ellipsoid(b, "Blush", Vector3.new(1.3, 0.6, 1.3), blush, CFrame.new(0, base + 2.2, 0))
	glow.Transparency = 0.45
	ellipsoid(b, "Peak", Vector3.new(0.62, 0.55, 0.62), blush, CFrame.new(0, base + 2.42, 0))
	kawaiiFace(b, CFrame.new(0, base + 0.95, -1.38), 1.25, 1.2)
end

-- A chunky butter block on its paper, with a melting pat and drips.
local function butter(b: Builder, hat: HatItem, base: number)
	local yellow = hat.MainColor
	local size = Vector3.new(2.7, 1.25, 1.7)
	roundedBox(b, "Wrapper", Vector3.new(size.X + 0.08, 0.3, size.Z + 0.08), 0.36, WHITE, CFrame.new(0, base, 0), false)
	roundedBox(b, "WrapperStripe", Vector3.new(size.X + 0.1, 0.07, size.Z + 0.1), 0.37, hat.AccentColor, CFrame.new(0, base + 0.2, 0), false)
	roundedBox(b, "Butter", size, 0.32, yellow, CFrame.new(0, base, 0), true)
	local top = base + size.Y
	local melted = yellow:Lerp(WHITE, 0.35)
	ellipsoid(b, "Melt", Vector3.new(1.5, 0.28, 1.0), melted, CFrame.new(0.15, top + 0.12, 0.05)).Reflectance = 0.12
	ellipsoid(b, "Pat", Vector3.new(0.9, 0.36, 0.62), melted, CFrame.new(0.2, top + 0.25, 0.05)).Reflectance = 0.12
	for _, x in { -0.62, 0.52 } do
		ellipsoid(b, "Drip", Vector3.new(0.28, 0.5, 0.18), melted, CFrame.new(x, top - 0.12, -size.Z / 2 - 0.03))
	end
	kawaiiFace(b, CFrame.new(0, base + 0.62, -size.Z / 2 - 0.02), 1.0, nil)
end

-- A see-through jelly cube with glitter and air bubbles inside.
local function jellyCube(b: Builder, hat: HatItem, base: number)
	local size = 2.0
	for _, part in roundedBox(b, "Jelly", Vector3.one * size, 0.35, hat.MainColor, CFrame.new(0, base, 0), true) do
		part.Material = Enum.Material.Glass
		part.Transparency = 0.3
		part.Reflectance = 0.08
	end
	local middle = base + size / 2
	local core = addPart(b, "JellyCore", Vector3.one * 1.3, hat.MainColor:Lerp(WHITE, 0.15), CFrame.new(0, middle, 0))
	core.Transparency = 0.5
	core.CastShadow = false
	local glitter = { hat.AccentColor, Color3.fromRGB(255, 240, 150), hat.MainColor:Lerp(WHITE, 0.6) }
	for i = 1, 16 do
		local position = Vector3.new(b.random:NextNumber(-0.72, 0.72), middle + b.random:NextNumber(-0.72, 0.72), b.random:NextNumber(-0.72, 0.72))
		local tilt = CFrame.Angles(b.random:NextNumber(0, 6), b.random:NextNumber(0, 6), b.random:NextNumber(0, 6))
		local speck = addPart(b, "Glitter", Vector3.one * 0.09, glitter[(i % #glitter) + 1], CFrame.new(position) * tilt)
		speck.Material = Enum.Material.Neon
		speck.CastShadow = false
	end
	ball(b, "Bubble", 0.3, WHITE, Vector3.new(0.45, middle + 0.45, -0.4)).Transparency = 0.4
	ball(b, "Bubble", 0.18, WHITE, Vector3.new(-0.35, middle - 0.3, -0.5)).Transparency = 0.4
	local shine = ellipsoid(b, "Shine", Vector3.new(0.7, 0.14, 0.3), WHITE, CFrame.new(-0.45, base + size - 0.04, -0.55) * CFrame.Angles(0, math.rad(35), 0))
	shine.Transparency = 0.25
	shine.CastShadow = false
end

-- A frosted ring donut with sprinkles, tipped forward so you see the top.
local function donut(b: Builder, hat: HatItem, base: number)
	local frame = CFrame.new(0, base + 0.45, 0) * CFrame.Angles(math.rad(-14), 0, 0)
	local ring = 0.85
	for i = 0, 11 do
		local spot = frame * CFrame.Angles(0, math.rad(i * 30), 0) * CFrame.new(0, 0, ring)
		ellipsoid(b, "Dough", Vector3.new(0.95, 0.8, 0.95), hat.AccentColor, spot)
		ellipsoid(b, "Frosting", Vector3.new(0.9, 0.42, 0.92), hat.MainColor, spot * CFrame.new(0, 0.28, 0)).Reflectance = 0.06
	end
	for i = 0, 5 do
		local spin = CFrame.Angles(0, math.rad(i * 60 + 15), 0)
		ellipsoid(b, "Drip", Vector3.new(0.3, 0.42, 0.26), hat.MainColor, frame * spin * CFrame.new(0, 0.12, ring + 0.42))
	end
	for i = 1, 16 do
		local spin = CFrame.Angles(0, b.random:NextNumber(0, math.pi * 2), 0)
		local turn = CFrame.Angles(0, b.random:NextNumber(0, math.pi), 0)
		local sprinkle = addPart(b, "Sprinkle", Vector3.new(0.07, 0.07, 0.24), SPRINKLES[(i % #SPRINKLES) + 1],
			frame * spin * CFrame.new(0, 0.5, b.random:NextNumber(0.6, 1.1)) * turn)
		sprinkle.CastShadow = false
	end
	kawaiiFace(b, frame * CFrame.new(0, 0.05, -(ring + 0.46)), 0.75, 0.6)
end

-- A little layer cake: sponge, cream, frosting drips, whipped cream and a cherry.
local function cake(b: Builder, hat: HatItem, base: number)
	local sponge, cream = hat.AccentColor, hat.MainColor
	local diameter = 2.3
	local y = base
	cylinder(b, "Sponge", diameter, 0.55, sponge, CFrame.new(0, y, 0))
	y += 0.55
	cylinder(b, "CreamLayer", diameter + 0.05, 0.16, cream, CFrame.new(0, y, 0))
	y += 0.16
	cylinder(b, "Sponge", diameter, 0.55, sponge, CFrame.new(0, y, 0))
	y += 0.55
	cylinder(b, "Frosting", diameter + 0.12, 0.22, cream, CFrame.new(0, y, 0))
	local top = y + 0.22
	for i = 0, 9 do
		local degrees = i * 36 + 10
		if math.abs(degrees - 180) > 35 then -- keep the front clear for the face
			local length = 0.32 + (i % 3) * 0.12
			ellipsoid(b, "Drip", Vector3.new(0.3, length, 0.22), cream,
				CFrame.Angles(0, math.rad(degrees), 0) * CFrame.new(0, y - length * 0.25, diameter / 2 + 0.04))
		end
	end
	for i = 0, 5 do
		local spot = CFrame.Angles(0, math.rad(i * 60), 0) * CFrame.new(0, top + 0.1, 0.78)
		ball(b, "Whip", 0.4, cream, spot.Position)
	end
	ball(b, "Cherry", 0.55, Color3.fromRGB(220, 40, 60), Vector3.new(0, top + 0.3, 0))
	cylinder(b, "Stem", 0.06, 0.45, Color3.fromRGB(70, 120, 50), CFrame.new(0.05, top + 0.5, 0) * CFrame.Angles(0, 0, math.rad(-20)))
	kawaiiFace(b, CFrame.new(0, base + 0.98, -diameter / 2 - 0.01), 0.85, 1.15)
end

-- A waffle cone with a scoop melting over the rim, choc chips and a cherry.
local function iceCream(b: Builder, hat: HatItem, base: number)
	local frame = CFrame.new(0, base, 0) * CFrame.Angles(0, 0, math.rad(8)) -- a little tilt
	local tiers = 6
	for i = 0, tiers - 1 do
		local color = if i % 2 == 0 then hat.AccentColor else hat.AccentColor:Lerp(BLACK, 0.12)
		cylinder(b, "Cone", 0.3 + i * 0.19, 0.26, color, frame * CFrame.new(0, i * 0.26, 0))
	end
	local rim = tiers * 0.26
	cylinder(b, "ConeRim", 0.3 + tiers * 0.19 + 0.08, 0.14, hat.AccentColor:Lerp(WHITE, 0.15), frame * CFrame.new(0, rim, 0))
	local scoopSize = Vector3.new(1.6, 1.3, 1.6)
	local scoop = frame * CFrame.new(0, rim + 0.62, 0)
	ellipsoid(b, "Scoop", scoopSize, hat.MainColor, scoop)
	for i = 0, 7 do
		ellipsoid(b, "ScoopDrip", Vector3.new(0.42, 0.34, 0.42), hat.MainColor,
			frame * CFrame.Angles(0, math.rad(i * 45), 0) * CFrame.new(0, rim + 0.15, 0.62))
	end
	for _ = 1, 9 do
		local dir = Vector3.new(b.random:NextNumber(-1, 1), b.random:NextNumber(0.15, 1), b.random:NextNumber(-1, 1))
		if not (dir.Unit.Z < -0.5 and dir.Unit.Y < 0.45) then -- not on the face
			local chip = addPart(b, "Chip", Vector3.new(0.13, 0.09, 0.13), Color3.fromRGB(90, 55, 40), onEllipsoid(scoop, scoopSize, dir))
			chip.CastShadow = false
		end
	end
	local cherry = frame * CFrame.new(0, rim + 1.32, 0)
	ball(b, "Cherry", 0.42, Color3.fromRGB(220, 40, 60), cherry.Position)
	cylinder(b, "Stem", 0.05, 0.38, Color3.fromRGB(70, 120, 50), cherry * CFrame.new(0.03, 0.15, 0) * CFrame.Angles(0, 0, math.rad(-20)))
	kawaiiFace(b, scoop * CFrame.new(0, -0.05, -0.79), 0.8, 0.8)
end

-- A red-and-white striped bucket heaped with popcorn.
local function popcorn(b: Builder, hat: HatItem, base: number)
	local stripeColor, bucketColor = hat.MainColor, hat.AccentColor
	local height, bottomD, topD = 1.6, 1.55, 2.05
	for i = 0, 3 do
		local diameter = bottomD + (topD - bottomD) * (i + 0.5) / 4
		cylinder(b, "Bucket", diameter, height / 4, bucketColor, CFrame.new(0, base + i * height / 4, 0))
	end
	local lean = math.atan(((topD - bottomD) / 2) / height) -- the sides lean out
	for i = 0, 5 do
		local spin = CFrame.Angles(0, math.rad(i * 60 + 30), 0)
		addPart(b, "Stripe", Vector3.new(0.34, height, 0.06), stripeColor,
			spin * CFrame.new(0, base + height / 2, (bottomD + topD) / 4 + 0.03) * CFrame.Angles(lean, 0, 0))
	end
	cylinder(b, "Rim", topD + 0.1, 0.1, stripeColor, CFrame.new(0, base + height - 0.05, 0))
	local kernelColors = { Color3.fromRGB(255, 248, 225), Color3.fromRGB(255, 244, 210), Color3.fromRGB(255, 225, 140) }
	for i = 1, 14 do
		local distance = math.sqrt(b.random:NextNumber()) * 0.85
		local angle = b.random:NextNumber(0, math.pi * 2)
		local y = base + height + 0.15 + (1 - distance / 0.85) * 0.55 + b.random:NextNumber(0, 0.15)
		ball(b, "Popcorn", b.random:NextNumber(0.42, 0.58), kernelColors[(i % #kernelColors) + 1],
			Vector3.new(math.cos(angle) * distance, y, math.sin(angle) * distance))
	end
	local faceRadius = (bottomD + (topD - bottomD) * 0.47) / 2
	kawaiiFace(b, CFrame.new(0, base + 0.75, -faceRadius - 0.01), 0.6, 0.9)
end

--[[
	Builds the squishy for `hat`, sitting on top of a slime whose hitbox is
	at `bodyCFrame` with size `bodySize`. Returns nil for "No Squishy".
]]
function HatBuilder.build(hat: HatItem, bodyCFrame: CFrame, bodySize: Vector3): Model?
	if hat.Shape == "None" then
		return nil
	end
	local model = Instance.new("Model")
	model.Name = HatBuilder.MODEL_NAME
	model:SetAttribute(KEEP_VISIBLE_ATTRIBUTE, true)
	model:SetAttribute("HatId", hat.Id)

	local seed = 0
	for i = 1, #hat.Id do
		seed += string.byte(hat.Id, i) * i
	end
	local b: Builder = { origin = bodyCFrame, model = model, random = Random.new(seed) }
	local base = bodySize.Y / 2 - 0.3 -- on top of the slime, sunk in a little (it's jelly)

	if hat.Shape == "Dumpling" then
		dumpling(b, hat, base)
	elseif hat.Shape == "Butter" then
		butter(b, hat, base)
	elseif hat.Shape == "JellyCube" then
		jellyCube(b, hat, base)
	elseif hat.Shape == "Donut" then
		donut(b, hat, base)
	elseif hat.Shape == "CakeSlice" then
		cake(b, hat, base)
	elseif hat.Shape == "IceCream" then
		iceCream(b, hat, base)
	elseif hat.Shape == "Popcorn" then
		popcorn(b, hat, base)
	end
	return model
end

--[[
	A round squishy ball with a cute face (the Daily Squishy room shows a
	big one floating in its glass dome). `cframe` is the ball's middle,
	with the face looking along its LookVector; `diameter` is how wide it
	is. Everything is anchored and never collides. The round body part is
	called "Body", so the lobby can tint it.
]]
function HatBuilder.buildBall(color: Color3, cframe: CFrame, diameter: number): Model
	local model = Instance.new("Model")
	model.Name = "SquishyBall"
	local s = diameter / 4 -- designed 4 studs wide
	local b: Builder = { origin = cframe, model = model, random = Random.new(4) }
	-- Slightly squashed, like a soft toy sitting down.
	local body = ellipsoid(b, "Body", Vector3.new(4, 3.7, 4) * s, color, CFrame.new())
	body.Reflectance = 0.06
	-- A soft shine on top (the slimes have one too).
	local shine = ellipsoid(b, "Shine", Vector3.new(1.3, 0.55, 0.8) * s, WHITE,
		CFrame.new(-0.8 * s, 1.15 * s, -0.95 * s) * CFrame.Angles(math.rad(-35), math.rad(-25), math.rad(18)))
	shine.Transparency = 0.45
	shine.CastShadow = false
	kawaiiFace(b, CFrame.new(0, -0.05 * s, -1.98 * s), 2.1 * s, 2 * s)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	model.WorldPivot = cframe
	return model
end

return HatBuilder
