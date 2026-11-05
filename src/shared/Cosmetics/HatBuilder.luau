--!strict
--[[
	HatBuilder: builds the SQUISHY a slime wears on top (the shop's
	"Squishies" tab). Used by the server (on real characters) and by the
	shop's previews.

	Squishies: Dumpling, Butter, Jelly Cube, Donut, Cake Slice, Ice Cream,
	Popcorn. Each is a few simple parts; most get a cute face with blush.
	They never collide and bullets fly straight through them, so a squishy
	can never change your hitbox.

	(Internally the category is still called "Hat", so older saves and the
	EquippedHat attribute keep working.)
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ShopConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ShopConfig"))

type HatItem = ShopConfig.HatItem

-- The blob hides every part added to a character unless it has this
-- attribute (see server/Components/BlobCharacter), so squishies carry it.
local KEEP_VISIBLE_ATTRIBUTE = "IsBlobPart"
local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- stands a cylinder up
local INK = Color3.fromRGB(45, 32, 58)

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

-- A squashed ball (a block with a sphere mesh), soft like a real squishy.
local function ellipsoid(b: Builder, name: string, size: Vector3, color: Color3, localCFrame: CFrame): Part
	local part = addPart(b, name, size, color, localCFrame)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

local function dot(parent: Instance, size: UDim2, position: UDim2, color: Color3, transparency: number?): Frame
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Size = size
	frame.Position = position
	frame.BackgroundColor3 = color
	frame.BackgroundTransparency = transparency or 0
	frame.BorderSizePixel = 0
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame
	frame.Parent = parent
	return frame
end

-- A cute face (eyes with sparkles, a little smile, blush) on a thin invisible
-- card facing forward (-Z), centred at `localCFrame`.
local function face(b: Builder, localCFrame: CFrame, width: number, height: number)
	local card = addPart(b, "SquishyFace", Vector3.new(width, height, 0.04), Color3.new(1, 1, 1), localCFrame)
	card.Transparency = 1
	card.CastShadow = false
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100
	gui.LightInfluence = 0.6
	gui.Parent = card
	for _, x in { 0.32, 0.68 } do
		local eye = dot(gui, UDim2.fromScale(0.13, 0.3), UDim2.fromScale(x, 0.42), INK)
		dot(eye, UDim2.fromScale(0.45, 0.32), UDim2.fromScale(0.62, 0.3), Color3.new(1, 1, 1))
	end
	for _, x in { 0.17, 0.83 } do
		dot(gui, UDim2.fromScale(0.16, 0.12), UDim2.fromScale(x, 0.64), Color3.fromRGB(255, 120, 150), 0.35)
	end
	-- Smile: the bottom of a ring seen through a small window.
	local window = Instance.new("Frame")
	window.AnchorPoint = Vector2.new(0.5, 0)
	window.Position = UDim2.fromScale(0.5, 0.56)
	window.Size = UDim2.fromScale(0.16, 0.18)
	window.BackgroundTransparency = 1
	window.ClipsDescendants = true
	window.Parent = gui
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 1)
	ring.Position = UDim2.new(0.5, 0, 1, -3)
	ring.Size = UDim2.fromScale(0.8, 1.6)
	ring.BackgroundTransparency = 1
	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ring
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 3
	stroke.Parent = ring
	ring.Parent = window
end

-- Each squishy ------------------------------------------------------------

-- A soft bun with pleats gathered at the top (like the dumpling squishies).
local function dumpling(b: Builder, hat: HatItem, top: number)
	local body = Vector3.new(2.3, 1.55, 2.2)
	ellipsoid(b, "Bun", body, hat.MainColor, CFrame.new(0, top + 0.62, 0))
	for i = 0, 5 do
		local angle = math.rad(i * 60)
		ellipsoid(b, "Pleat", Vector3.new(0.22, 0.42, 0.9), hat.MainColor:Lerp(Color3.new(0, 0, 0), 0.08),
			CFrame.new(0, top + 1.3, 0) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0, 0.28) * CFrame.Angles(math.rad(-30), 0, 0))
	end
	ellipsoid(b, "Knot", Vector3.new(0.55, 0.32, 0.55), hat.MainColor, CFrame.new(0, top + 1.42, 0))
	face(b, CFrame.new(0, top + 0.58, -body.Z / 2 + 0.02), 1.3, 0.7)
end

-- A stick of butter with "BUTTER" on the side.
local function butter(b: Builder, hat: HatItem, top: number)
	local stick = addPart(b, "Butter", Vector3.new(2.6, 0.95, 1.15), hat.MainColor, CFrame.new(0, top + 0.47, 0))
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 80
	gui.LightInfluence = 0.6
	gui.Parent = stick
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.LuckiestGuy
	text.TextScaled = true
	text.TextColor3 = hat.AccentColor
	text.Text = "BUTTER"
	text.Parent = gui
end

-- A see-through jelly cube with a little air bubble inside.
local function jellyCube(b: Builder, hat: HatItem, top: number)
	local outer = addPart(b, "Cube", Vector3.new(1.8, 1.8, 1.8), hat.MainColor, CFrame.new(0, top + 0.9, 0))
	outer.Material = Enum.Material.Glass
	outer.Transparency = 0.35
	local inner = addPart(b, "CubeCore", Vector3.new(1.35, 1.35, 1.35), hat.MainColor, CFrame.new(0, top + 0.9, 0))
	inner.Transparency = 0.45
	ball(b, "Bubble", 0.35, Color3.new(1, 1, 1), Vector3.new(0.45, top + 1.4, -0.45)).Transparency = 0.35
	face(b, CFrame.new(0, top + 0.85, -0.92), 1.2, 0.65)
end

-- A frosted donut with sprinkles.
local function donut(b: Builder, hat: HatItem, top: number)
	local base = CFrame.new(0, top, 0)
	cylinder(b, "Dough", 2.3, 0.7, hat.AccentColor, base)
	cylinder(b, "Frosting", 2.05, 0.22, hat.MainColor, base * CFrame.new(0, 0.62, 0))
	cylinder(b, "Hole", 0.75, 0.06, hat.AccentColor:Lerp(Color3.new(0, 0, 0), 0.35), base * CFrame.new(0, 0.84, 0))
	local sprinkleColors = { Color3.fromRGB(255, 240, 90), Color3.fromRGB(110, 200, 255), Color3.fromRGB(255, 255, 255), Color3.fromRGB(120, 230, 120) }
	for i = 0, 7 do
		local angle = math.rad(i * 45 + 10)
		addPart(b, "Sprinkle", Vector3.new(0.09, 0.07, 0.32), sprinkleColors[(i % #sprinkleColors) + 1],
			base * CFrame.new(math.cos(angle) * 0.7, 0.86, math.sin(angle) * 0.7) * CFrame.Angles(0, angle * 2, 0))
	end
end

-- A slice of layer cake with a strawberry on top.
local function cakeSlice(b: Builder, hat: HatItem, top: number)
	local size = Vector2.new(1.9, 1.3)
	local layers = { { 0.35, hat.AccentColor }, { 0.14, Color3.fromRGB(220, 50, 70) }, { 0.35, hat.AccentColor }, { 0.22, hat.MainColor } }
	local y = top
	for index, layer in layers do
		local height = layer[1] :: number
		addPart(b, "Layer" .. index, Vector3.new(size.X, height, size.Y), layer[2] :: Color3, CFrame.new(0, y + height / 2, 0))
		y += height
	end
	ball(b, "Strawberry", 0.6, Color3.fromRGB(230, 40, 60), Vector3.new(0.2, y + 0.25, 0))
	face(b, CFrame.new(0, top + 0.5, -size.Y / 2 - 0.03), 1.2, 0.6)
end

-- An ice cream cone (wide at the top) with a scoop and a few drips.
local function iceCream(b: Builder, hat: HatItem, top: number)
	local cone = hat.AccentColor
	local diameters = { 0.45, 0.75, 1.05 }
	for i, diameter in diameters do
		cylinder(b, "Cone" .. i, diameter, 0.42, cone, CFrame.new(0, top + (i - 1) * 0.42, 0))
	end
	local scoopY = top + #diameters * 0.42 + 0.45
	ball(b, "Scoop", 1.55, hat.MainColor, Vector3.new(0, scoopY, 0))
	for i = 0, 3 do
		local angle = math.rad(i * 90 + 30)
		ball(b, "Drip", 0.35, hat.MainColor, Vector3.new(math.cos(angle) * 0.62, scoopY - 0.55, math.sin(angle) * 0.62))
	end
	face(b, CFrame.new(0, scoopY - 0.05, -0.77), 0.9, 0.5)
end

-- A striped popcorn bucket heaped with popcorn.
local function popcorn(b: Builder, hat: HatItem, top: number)
	for i = 0, 2 do
		cylinder(b, "Bucket" .. i, 1.55 + i * 0.06, 0.42, if i % 2 == 0 then hat.MainColor else hat.AccentColor, CFrame.new(0, top + i * 0.42, 0))
	end
	local heapY = top + 1.3
	local kernel = Color3.fromRGB(255, 236, 160)
	for i = 0, 6 do
		local angle = math.rad(i * 51)
		local r = if i == 0 then 0 else 0.45
		ball(b, "Kernel", 0.55, kernel, Vector3.new(math.cos(angle) * r, heapY + (if i == 0 then 0.25 else 0), math.sin(angle) * r))
	end
	face(b, CFrame.new(0, top + 0.6, -0.82), 0.95, 0.5)
end

--[[
	Builds the squishy for `hat`, sitting on a blob body at `bodyCFrame` whose
	size is `bodySize`. Returns nil for "No Squishy". The parts are not glued
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

	if hat.Shape == "Dumpling" then
		dumpling(b, hat, top)
	elseif hat.Shape == "Butter" then
		butter(b, hat, top)
	elseif hat.Shape == "JellyCube" then
		jellyCube(b, hat, top)
	elseif hat.Shape == "Donut" then
		donut(b, hat, top)
	elseif hat.Shape == "CakeSlice" then
		cakeSlice(b, hat, top)
	elseif hat.Shape == "IceCream" then
		iceCream(b, hat, top)
	elseif hat.Shape == "Popcorn" then
		popcorn(b, hat, top)
	end
	return model
end

return HatBuilder
