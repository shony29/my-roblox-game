--!strict
--[[
	CharmBuilder
	============
	Builds the little 3D charms of the "Charms" toppings (charm packets),
	like the cute flat-backed resin charms you put in slime: a strawberry,
	a cupcake, a pumpkin with a face...

	Every charm is made from plain parts (balls, boxes, discs and
	triangles), so there are no images or emoji that could fail to show.
	A charm is about 1 stud tall, faces -Z (its flat back towards +Z) and
	is glossy like resin.

		CharmBuilder.build("Strawberry")                            -- for pictures
		CharmBuilder.build("Strawberry", { scale = 0.8, welded = true }) -- to throw around

	Every charm has an invisible "Root" part in its middle (the PrimaryPart).
	`welded` = true leaves only the root anchored and welds the rest to it,
	so moving the root (its CFrame) moves the whole charm.
	Unknown names build a star. CharmBuilder.NAMES lists every charm.
]]

export type Options = { scale: number?, welded: boolean? }

type Kit = {
	frame: CFrame, -- applied to every part made after it is set (to tilt a whole charm)
	ball: (color: Color3, size: Vector3, position: Vector3, rotation: number?) -> BasePart,
	box: (color: Color3, size: Vector3, position: Vector3, rotation: number?) -> BasePart,
	disc: (color: Color3, diameter: number, thickness: number, position: Vector3) -> BasePart,
	rod: (color: Color3, length: number, diameter: number, position: Vector3, rotation: number?) -> BasePart,
	bar: (color: Color3, length: number, diameter: number, position: Vector3, rotation: number?) -> BasePart,
	tri: (color: Color3, width: number, height: number, thickness: number, position: Vector3, rotation: number?) -> { BasePart },
	star: (color: Color3, points: number, outer: number, inner: number, thickness: number, position: Vector3, rotation: number?) -> { BasePart },
	glow: (part: BasePart) -> (),
}

local rgb = Color3.fromRGB
local V = Vector3.new

local RED = rgb(235, 55, 70)
local DARK_RED = rgb(170, 30, 50)
local PINK = rgb(255, 140, 190)
local LIGHT_PINK = rgb(255, 195, 220)
local YELLOW = rgb(255, 215, 70)
local LIGHT_YELLOW = rgb(255, 238, 150)
local ORANGE = rgb(255, 145, 45)
local GREEN = rgb(90, 200, 90)
local LEAF = rgb(60, 165, 75)
local BROWN = rgb(150, 95, 55)
local DARK_BROWN = rgb(95, 58, 35)
local TAN = rgb(225, 170, 105)
local CREAM = rgb(255, 242, 215)
local WHITE = rgb(250, 250, 252)
local BLUE = rgb(80, 165, 255)
local SKY = rgb(150, 215, 255)
local PURPLE = rgb(165, 105, 240)
local BLACK = rgb(38, 36, 46)
local GOLD = rgb(255, 200, 55)
local MINT = rgb(150, 235, 200)
local SEED = rgb(255, 238, 150)

local CharmBuilder = {}

local function newKit(model: Model, scale: number): Kit
	local kit: Kit = nil :: any

	local function finish(part: BasePart, color: Color3, localCFrame: CFrame)
		part.Color = color
		part.Material = Enum.Material.SmoothPlastic
		part.Reflectance = 0.08 -- a little resin shine
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.Massless = true
		local position = localCFrame.Position * scale
		part.CFrame = kit.frame * (CFrame.new(position) * localCFrame.Rotation)
		part.Parent = model
	end

	local function spin(rotation: number?): CFrame
		return CFrame.Angles(0, 0, math.rad(rotation or 0))
	end

	local function ball(color: Color3, size: Vector3, position: Vector3, rotation: number?): BasePart
		local part = Instance.new("Part")
		part.Name = "Ball"
		part.Size = size * scale
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere -- stretches with the part: ellipsoids too
		mesh.Parent = part
		finish(part, color, CFrame.new(position) * spin(rotation))
		return part
	end

	local function box(color: Color3, size: Vector3, position: Vector3, rotation: number?): BasePart
		local part = Instance.new("Part")
		part.Name = "Box"
		part.Size = size * scale
		finish(part, color, CFrame.new(position) * spin(rotation))
		return part
	end

	-- A coin shape facing the front.
	local function disc(color: Color3, diameter: number, thickness: number, position: Vector3): BasePart
		local part = Instance.new("Part")
		part.Name = "Disc"
		part.Shape = Enum.PartType.Cylinder
		part.Size = V(thickness, diameter, diameter) * scale
		finish(part, color, CFrame.new(position) * CFrame.Angles(0, math.rad(90), 0))
		return part
	end

	-- A cylinder standing up (tilted by `rotation` degrees).
	local function rod(color: Color3, length: number, diameter: number, position: Vector3, rotation: number?): BasePart
		local part = Instance.new("Part")
		part.Name = "Rod"
		part.Shape = Enum.PartType.Cylinder
		part.Size = V(length, diameter, diameter) * scale
		finish(part, color, CFrame.new(position) * spin(rotation) * CFrame.Angles(0, 0, math.rad(90)))
		return part
	end

	-- A cylinder lying sideways (tilted by `rotation` degrees).
	local function bar(color: Color3, length: number, diameter: number, position: Vector3, rotation: number?): BasePart
		local part = Instance.new("Part")
		part.Name = "Bar"
		part.Shape = Enum.PartType.Cylinder
		part.Size = V(length, diameter, diameter) * scale
		finish(part, color, CFrame.new(position) * spin(rotation))
		return part
	end

	-- A flat triangle pointing up (turned by `rotation` degrees), made of two wedges.
	local function tri(color: Color3, width: number, height: number, thickness: number, position: Vector3, rotation: number?): { BasePart }
		local center = CFrame.new(position) * spin(rotation)
		local parts: { BasePart } = {}
		for _, side in { -1, 1 } do
			local part = Instance.new("WedgePart")
			part.Name = "Triangle"
			part.Size = V(thickness, height, width / 2) * scale
			finish(part, color, center * CFrame.new(side * width / 4, 0, 0) * CFrame.Angles(0, math.rad(-90 * side), 0))
			table.insert(parts, part)
		end
		return parts
	end

	-- A star: a disc in the middle and a triangle for every point.
	local function star(color: Color3, points: number, outer: number, inner: number, thickness: number, position: Vector3, rotation: number?): { BasePart }
		local parts: { BasePart } = { disc(color, inner * 2, thickness, position) }
		local half = math.pi / points
		local width = 2 * inner * math.sin(half)
		local height = outer - inner * math.cos(half)
		for i = 0, points - 1 do
			local angle = math.rad(90 + (rotation or 0)) + i * 2 * half
			local direction = V(math.cos(angle), math.sin(angle), 0)
			for _, part in tri(color, width * 1.05, height, thickness, position + direction * (inner * math.cos(half) + height / 2), math.deg(angle) - 90) do
				table.insert(parts, part)
			end
		end
		return parts
	end

	local function glow(part: BasePart)
		part.Material = Enum.Material.Neon
		part.Reflectance = 0
	end

	kit = {
		frame = CFrame.new(),
		ball = ball,
		box = box,
		disc = disc,
		rod = rod,
		bar = bar,
		tri = tri,
		star = star,
		glow = glow,
	}
	return kit
end

-- Two shiny black eyes and pink cheeks: the kawaii face.
local function face(k: Kit, y: number, z: number, spread: number)
	for _, side in { -1, 1 } do
		k.ball(BLACK, V(0.09, 0.11, 0.05), V(side * spread, y, z))
		k.ball(WHITE, V(0.03, 0.03, 0.02), V(side * spread + 0.02, y + 0.025, z - 0.025))
		k.ball(LIGHT_PINK, V(0.1, 0.06, 0.03), V(side * (spread + 0.08), y - 0.08, z + 0.005))
	end
end

local function flower(k: Kit, petals: number, petalColor: Color3, centerColor: Color3, size: number)
	for i = 0, petals - 1 do
		local angle = i * (2 * math.pi / petals) + math.pi / 2
		local direction = V(math.cos(angle), math.sin(angle), 0)
		k.ball(petalColor, V(0.3, 0.44, 0.18) * size, direction * 0.26 * size, math.deg(angle) - 90)
	end
	k.ball(centerColor, V(0.3, 0.3, 0.24) * size, V(0, 0, -0.04))
end

local DESIGNS: { [string]: (Kit) -> () } = {}

-- Fruit and food ---------------------------------------------------------------

DESIGNS.Strawberry = function(k: Kit)
	k.ball(RED, V(0.8, 0.92, 0.42), V(0, -0.06, 0))
	for i, x in { -0.16, 0, 0.16 } do
		k.ball(LEAF, V(0.2, 0.34, 0.16), V(x, 0.38, -0.02), (i - 2) * -40)
	end
	for _, p in { V(-0.18, 0.12, -0.17), V(0.17, 0.1, -0.17), V(0, -0.06, -0.2), V(-0.2, -0.24, -0.14), V(0.19, -0.26, -0.14), V(0, -0.36, -0.12) } do
		k.ball(SEED, V(0.07, 0.1, 0.05), p)
	end
end

DESIGNS.Lemon = function(k: Kit)
	k.ball(YELLOW, V(0.9, 0.66, 0.42), V(0, 0, 0), 15)
	k.ball(YELLOW, V(0.2, 0.16, 0.18), V(0.46, 0.12, 0), 15)
	k.ball(YELLOW, V(0.2, 0.16, 0.18), V(-0.46, -0.12, 0), 15)
	k.ball(LEAF, V(0.22, 0.42, 0.1), V(0.12, 0.38, -0.05), -55)
	k.ball(WHITE, V(0.16, 0.08, 0.04), V(-0.12, 0.14, -0.2), 15)
end

DESIGNS.Apple = function(k: Kit)
	k.ball(RED, V(0.82, 0.76, 0.44), V(0, -0.04, 0))
	k.box(DARK_BROWN, V(0.06, 0.22, 0.06), V(0, 0.38, 0), -10)
	k.ball(LEAF, V(0.2, 0.36, 0.08), V(0.15, 0.4, -0.04), -60)
	k.ball(WHITE, V(0.14, 0.09, 0.04), V(-0.18, 0.12, -0.2), 20)
end

DESIGNS.Coconut = function(k: Kit)
	k.ball(BROWN, V(0.78, 0.74, 0.5), V(0, 0, 0))
	for _, p in { V(-0.12, 0.08), V(0.12, 0.08), V(0, -0.1) } do
		k.ball(DARK_BROWN, V(0.1, 0.1, 0.05), V(p.X, p.Y, -0.24))
	end
	k.ball(LEAF, V(0.18, 0.4, 0.08), V(0.25, 0.38, -0.02), -50)
end

DESIGNS.Pineapple = function(k: Kit)
	k.ball(rgb(255, 190, 60), V(0.58, 0.72, 0.4), V(0, -0.14, 0))
	for _, rotation in { 45, -45 } do
		for _, offset in { -0.12, 0.12 } do
			k.box(rgb(205, 135, 40), V(0.03, 0.62, 0.03), V(offset, -0.14, -0.19), rotation)
		end
	end
	for i, rotation in { 30, 10, -10, -30 } do
		k.tri(GREEN, 0.14, 0.4, 0.08, V(-0.12 + (i - 1) * 0.08, 0.38, 0), rotation)
	end
end

DESIGNS.Watermelon = function(k: Kit)
	k.tri(RED, 0.9, 0.8, 0.18, V(0, -0.05, 0), 180)
	k.box(rgb(220, 255, 210), V(0.9, 0.06, 0.18), V(0, 0.36, 0))
	k.bar(rgb(50, 160, 70), 0.94, 0.14, V(0, 0.42, 0))
	for _, p in { V(-0.18, 0.18), V(0.18, 0.18), V(0, 0.02), V(-0.06, 0.22), V(0.08, -0.16) } do
		k.ball(BLACK, V(0.05, 0.08, 0.04), V(p.X, p.Y, -0.1))
	end
end

DESIGNS.Pizza = function(k: Kit)
	k.tri(rgb(255, 205, 90), 0.84, 0.86, 0.14, V(0, -0.04, 0), 180)
	k.bar(rgb(225, 150, 70), 0.9, 0.18, V(0, 0.4, 0))
	for _, p in { V(-0.16, 0.18), V(0.14, 0.2), V(0, -0.06) } do
		k.disc(rgb(215, 60, 55), 0.17, 0.04, V(p.X, p.Y, -0.08))
	end
end

DESIGNS.Burger = function(k: Kit)
	k.ball(TAN, V(0.86, 0.24, 0.5), V(0, -0.32, 0))
	k.ball(DARK_BROWN, V(0.92, 0.2, 0.52), V(0, -0.15, 0))
	k.box(YELLOW, V(0.86, 0.06, 0.5), V(0, -0.04, -0.01), 4)
	k.ball(GREEN, V(0.96, 0.1, 0.52), V(0, 0.03, 0))
	k.ball(TAN, V(0.88, 0.46, 0.5), V(0, 0.17, 0)) -- its lower half hides behind the filling
	for _, p in { V(-0.18, 0.3), V(0.06, 0.36), V(0.22, 0.26), V(-0.04, 0.24) } do
		k.ball(CREAM, V(0.07, 0.04, 0.03), V(p.X, p.Y, -0.24))
	end
end

DESIGNS.Fries = function(k: Kit)
	for i, x in { -0.2, -0.1, 0, 0.1, 0.2 } do
		k.box(YELLOW, V(0.09, 0.56, 0.09), V(x, 0.2 + (i % 2) * 0.06, 0.04), (i - 3) * 6)
	end
	k.box(RED, V(0.62, 0.5, 0.36), V(0, -0.2, -0.02))
	k.box(WHITE, V(0.62, 0.08, 0.37), V(0, -0.06, -0.02))
end

DESIGNS.Toast = function(k: Kit)
	k.box(rgb(205, 140, 70), V(0.82, 0.62, 0.16), V(0, -0.12, 0.02))
	for _, x in { -0.21, 0.21 } do
		k.ball(rgb(205, 140, 70), V(0.46, 0.46, 0.16), V(x, 0.18, 0.02))
	end
	k.box(rgb(250, 220, 160), V(0.7, 0.52, 0.16), V(0, -0.12, -0.01))
	for _, x in { -0.18, 0.18 } do
		k.ball(rgb(250, 220, 160), V(0.36, 0.36, 0.16), V(x, 0.16, -0.01))
	end
	face(k, -0.04, -0.09, 0.12)
end

DESIGNS.Egg = function(k: Kit)
	for _, p in { V(-0.12, 0.05, 0.6), V(0.14, -0.04, 0.58), V(0, -0.12, 0.66) } do
		k.disc(WHITE, p.Z, 0.08, V(p.X, p.Y, 0))
	end
	k.ball(rgb(255, 190, 40), V(0.34, 0.34, 0.2), V(0.02, 0.02, -0.06))
	k.ball(WHITE, V(0.08, 0.05, 0.03), V(-0.04, 0.08, -0.16))
end

DESIGNS.Cheese = function(k: Kit)
	k.tri(rgb(255, 210, 70), 0.96, 0.78, 0.26, V(0, 0, 0), 0)
	for _, p in { V(-0.18, -0.2, 0.14), V(0.12, -0.12, 0.1), V(0, 0.1, 0.08) } do
		k.disc(rgb(230, 175, 45), p.Z, 0.04, V(p.X, p.Y, -0.14))
	end
end

DESIGNS.Cookie = function(k: Kit)
	k.disc(rgb(215, 160, 90), 0.88, 0.14, V(0, 0, 0))
	for _, p in { V(-0.2, 0.16), V(0.16, 0.2), V(0.02, -0.02), V(-0.16, -0.2), V(0.22, -0.14) } do
		k.ball(DARK_BROWN, V(0.11, 0.09, 0.06), V(p.X, p.Y, -0.08))
	end
end

DESIGNS.Corn = function(k: Kit)
	k.ball(YELLOW, V(0.42, 0.86, 0.36), V(0, 0.06, 0))
	for _, y in { -0.12, 0.06, 0.24 } do
		k.box(rgb(235, 180, 40), V(0.34, 0.03, 0.03), V(0, y, -0.17))
	end
	k.box(rgb(235, 180, 40), V(0.03, 0.6, 0.03), V(0, 0.06, -0.18))
	k.ball(GREEN, V(0.2, 0.62, 0.12), V(-0.2, -0.16, -0.06), 25)
	k.ball(GREEN, V(0.2, 0.62, 0.12), V(0.2, -0.16, -0.06), -25)
end

DESIGNS.Chocolate = function(k: Kit)
	k.box(rgb(120, 70, 40), V(0.66, 0.9, 0.14), V(0, 0, 0))
	for row = 0, 1 do
		for column = 0, 1 do
			k.box(rgb(140, 85, 50), V(0.26, 0.2, 0.06), V(-0.14 + column * 0.28, 0.32 - row * 0.24, -0.08))
		end
	end
	k.box(RED, V(0.7, 0.4, 0.17), V(0, -0.26, 0))
	k.box(GOLD, V(0.7, 0.05, 0.18), V(0, -0.08, 0))
end

DESIGNS.Pie = function(k: Kit)
	k.tri(rgb(220, 130, 60), 0.86, 0.8, 0.2, V(0, -0.04, 0), 180)
	k.bar(rgb(240, 185, 100), 0.92, 0.2, V(0, 0.38, 0))
	k.ball(WHITE, V(0.24, 0.2, 0.18), V(0, 0.18, -0.08))
	k.ball(WHITE, V(0.12, 0.12, 0.1), V(0, 0.29, -0.08))
end

-- Sweets and party ---------------------------------------------------------------

DESIGNS.Cake = function(k: Kit)
	k.rod(PINK, 0.48, 0.84, V(0, -0.18, 0))
	k.rod(WHITE, 0.12, 0.9, V(0, 0.1, 0))
	for _, x in { -0.26, 0, 0.26 } do
		k.ball(WHITE, V(0.16, 0.22, 0.1), V(x, 0.0, -0.4))
	end
	k.rod(rgb(120, 180, 255), 0.3, 0.07, V(0, 0.3, -0.05))
	k.glow(k.ball(rgb(255, 200, 60), V(0.1, 0.16, 0.1), V(0, 0.5, -0.05)))
	k.ball(RED, V(0.14, 0.14, 0.14), V(0.22, 0.2, -0.2))
end

DESIGNS.Cupcake = function(k: Kit)
	k.tri(LIGHT_PINK, 0.6, 0.42, 0.42, V(0, -0.26, 0), 180)
	k.box(LIGHT_PINK, V(0.42, 0.42, 0.42), V(0, -0.26, 0))
	for _, x in { -0.12, 0, 0.12 } do
		k.box(PINK, V(0.04, 0.4, 0.04), V(x, -0.26, -0.22))
	end
	k.ball(WHITE, V(0.78, 0.36, 0.5), V(0, 0.04, 0))
	k.ball(WHITE, V(0.54, 0.3, 0.42), V(0, 0.2, 0))
	k.ball(WHITE, V(0.26, 0.22, 0.26), V(0, 0.33, 0))
	k.ball(RED, V(0.16, 0.16, 0.16), V(0, 0.47, 0))
	for i, p in { V(-0.2, 0.06), V(0.16, 0.12), V(-0.04, 0.2), V(0.24, 0.0), V(-0.12, -0.02) } do
		k.box(({ BLUE, YELLOW, PINK, GREEN, PURPLE })[i], V(0.08, 0.025, 0.02), V(p.X, p.Y, -0.24), i * 37)
	end
end

DESIGNS.Balloon = function(k: Kit)
	k.ball(RED, V(0.66, 0.8, 0.6), V(0, 0.14, 0))
	k.tri(RED, 0.14, 0.1, 0.1, V(0, -0.29, 0), 0)
	k.box(WHITE, V(0.025, 0.42, 0.025), V(0.03, -0.52, 0), 8)
	k.ball(WHITE, V(0.12, 0.2, 0.04), V(-0.14, 0.28, -0.28), 25)
end

DESIGNS.Candy = function(k: Kit)
	k.ball(PURPLE, V(0.48, 0.4, 0.38), V(0, 0, 0))
	k.tri(rgb(200, 160, 255), 0.36, 0.3, 0.12, V(-0.38, 0, 0), 90)
	k.tri(rgb(200, 160, 255), 0.36, 0.3, 0.12, V(0.38, 0, 0), -90)
	for _, x in { -0.08, 0.08 } do
		k.box(WHITE, V(0.04, 0.38, 0.04), V(x, 0, -0.17), 20)
	end
end

DESIGNS.Lollipop = function(k: Kit)
	k.box(WHITE, V(0.06, 0.6, 0.06), V(0, -0.36, 0.02))
	k.disc(PINK, 0.72, 0.14, V(0, 0.16, 0))
	k.disc(WHITE, 0.52, 0.03, V(0, 0.16, -0.08))
	k.disc(PINK, 0.34, 0.03, V(0, 0.16, -0.1))
	k.disc(WHITE, 0.14, 0.03, V(0, 0.16, -0.12))
end

DESIGNS.CandyCane = function(k: Kit)
	k.rod(WHITE, 0.72, 0.16, V(0.14, -0.14, 0))
	for _, y in { -0.4, -0.22, -0.04 } do
		k.rod(RED, 0.07, 0.17, V(0.14, y, 0))
	end
	for i = 0, 5 do
		local angle = math.rad(i * 36)
		k.ball(if i % 2 == 0 then RED else WHITE, V(0.17, 0.17, 0.17), V(-0.04 + math.cos(angle) * 0.18, 0.24 + math.sin(angle) * 0.18, 0))
	end
end

DESIGNS.IceCream = function(k: Kit)
	k.tri(TAN, 0.5, 0.62, 0.3, V(0, -0.24, 0), 180)
	for _, rotation in { 40, -40 } do
		k.box(rgb(195, 135, 70), V(0.03, 0.4, 0.03), V(0, -0.18, -0.16), rotation)
	end
	k.ball(MINT, V(0.56, 0.44, 0.46), V(0, 0.12, 0))
	k.ball(PINK, V(0.46, 0.4, 0.42), V(0, 0.38, 0))
	k.ball(RED, V(0.13, 0.13, 0.13), V(0, 0.6, 0))
end

DESIGNS.Gift = function(k: Kit)
	k.box(rgb(90, 170, 255), V(0.74, 0.62, 0.42), V(0, -0.12, 0))
	k.box(rgb(255, 225, 90), V(0.14, 0.64, 0.44), V(0, -0.12, 0))
	k.box(rgb(255, 225, 90), V(0.76, 0.12, 0.44), V(0, -0.02, 0))
	k.ball(rgb(255, 225, 90), V(0.3, 0.2, 0.14), V(-0.15, 0.27, 0), 25)
	k.ball(rgb(255, 225, 90), V(0.3, 0.2, 0.14), V(0.15, 0.27, 0), -25)
	k.ball(rgb(255, 200, 60), V(0.12, 0.12, 0.14), V(0, 0.25, 0))
end

DESIGNS.Bear = function(k: Kit)
	for _, side in { -1, 1 } do
		k.ball(BROWN, V(0.28, 0.28, 0.2), V(side * 0.28, 0.3, 0.02))
		k.ball(LIGHT_PINK, V(0.14, 0.14, 0.1), V(side * 0.28, 0.3, -0.06))
	end
	k.ball(BROWN, V(0.8, 0.72, 0.42), V(0, 0, 0))
	k.ball(CREAM, V(0.34, 0.24, 0.12), V(0, -0.12, -0.17))
	k.ball(BLACK, V(0.1, 0.07, 0.05), V(0, -0.07, -0.23))
	face(k, 0.06, -0.19, 0.17)
end

DESIGNS.Gem = function(k: Kit)
	local gem = k.box(rgb(90, 220, 255), V(0.56, 0.56, 0.3), V(0, 0, 0), 45)
	gem.Reflectance = 0.35
	k.box(rgb(190, 245, 255), V(0.3, 0.3, 0.06), V(0, 0, -0.16), 45)
	k.ball(WHITE, V(0.08, 0.08, 0.03), V(-0.08, 0.12, -0.2))
end

DESIGNS.Coin = function(k: Kit)
	local coin = k.disc(GOLD, 0.86, 0.12, V(0, 0, 0))
	coin.Reflectance = 0.3
	k.disc(rgb(255, 225, 110), 0.66, 0.03, V(0, 0, -0.07))
	k.star(rgb(235, 170, 40), 5, 0.22, 0.09, 0.03, V(0, 0, -0.09))
end

DESIGNS.Heart = function(k: Kit)
	for _, x in { -0.17, 0.17 } do
		k.ball(rgb(255, 90, 140), V(0.5, 0.5, 0.36), V(x, 0.1, 0))
	end
	k.tri(rgb(255, 90, 140), 0.84, 0.56, 0.3, V(0, -0.2, 0), 180)
	k.ball(WHITE, V(0.12, 0.08, 0.04), V(-0.2, 0.2, -0.18), 30)
end

DESIGNS.Letter = function(k: Kit)
	k.box(WHITE, V(0.9, 0.6, 0.1), V(0, 0, 0))
	k.tri(LIGHT_PINK, 0.9, 0.36, 0.04, V(0, 0.12, -0.06), 180)
	for _, x in { -0.045, 0.045 } do
		k.ball(RED, V(0.11, 0.11, 0.05), V(x, 0.0, -0.09))
	end
	k.tri(RED, 0.18, 0.1, 0.05, V(0, -0.06, -0.09), 180)
end

-- Nature --------------------------------------------------------------------------

DESIGNS.Flower = function(k: Kit)
	flower(k, 5, PINK, YELLOW, 1)
end

DESIGNS.Daisy = function(k: Kit)
	flower(k, 8, WHITE, YELLOW, 1)
end

DESIGNS.Hibiscus = function(k: Kit)
	flower(k, 5, rgb(255, 80, 90), rgb(255, 220, 90), 1.15)
	k.box(YELLOW, V(0.04, 0.3, 0.04), V(0.06, 0.14, -0.14), -25)
	k.ball(rgb(255, 160, 40), V(0.08, 0.08, 0.08), V(0.13, 0.28, -0.14))
end

DESIGNS.Rose = function(k: Kit)
	k.box(LEAF, V(0.05, 0.42, 0.05), V(0, -0.34, 0.04))
	k.ball(LEAF, V(0.16, 0.34, 0.08), V(-0.14, -0.3, 0), 50)
	k.ball(LEAF, V(0.16, 0.34, 0.08), V(0.14, -0.36, 0), -50)
	k.ball(DARK_RED, V(0.66, 0.6, 0.36), V(0, 0.12, 0))
	k.ball(RED, V(0.44, 0.4, 0.2), V(0, 0.12, -0.12))
	k.ball(rgb(255, 110, 120), V(0.2, 0.18, 0.1), V(0, 0.14, -0.2))
end

DESIGNS.Tulip = function(k: Kit)
	k.box(LEAF, V(0.05, 0.5, 0.05), V(0, -0.3, 0.02))
	k.ball(GREEN, V(0.16, 0.42, 0.08), V(-0.15, -0.3, 0), 30)
	k.ball(GREEN, V(0.16, 0.42, 0.08), V(0.15, -0.3, 0), -30)
	k.ball(PINK, V(0.5, 0.52, 0.36), V(0, 0.12, 0))
	for _, p in { V(-0.15, 0.36, 15), V(0, 0.4, 0), V(0.15, 0.36, -15) } do
		k.tri(PINK, 0.18, 0.24, 0.2, V(p.X, p.Y, 0), p.Z)
	end
end

DESIGNS.Clover = function(k: Kit)
	k.box(LEAF, V(0.05, 0.4, 0.05), V(0.05, -0.3, 0.02), -15)
	for i = 0, 3 do
		local angle = math.rad(45 + i * 90)
		k.ball(GREEN, V(0.38, 0.4, 0.16), V(math.cos(angle) * 0.18, 0.06 + math.sin(angle) * 0.18, 0), 45 + i * 90)
	end
	k.ball(rgb(140, 225, 140), V(0.1, 0.1, 0.06), V(0, 0.06, -0.08))
end

DESIGNS.Leaf = function(k: Kit)
	k.ball(ORANGE, V(0.52, 0.88, 0.12), V(0, 0.04, 0), -30)
	k.box(rgb(210, 110, 30), V(0.03, 0.76, 0.03), V(0, 0.04, -0.06), -30)
	k.box(DARK_BROWN, V(0.05, 0.22, 0.05), V(0.25, -0.42, 0), -30)
end

DESIGNS.MapleLeaf = function(k: Kit)
	k.star(rgb(225, 75, 45), 5, 0.5, 0.2, 0.1, V(0, 0.06, 0))
	k.box(DARK_BROWN, V(0.05, 0.3, 0.05), V(0, -0.36, 0))
end

DESIGNS.Acorn = function(k: Kit)
	k.ball(rgb(205, 145, 80), V(0.5, 0.62, 0.4), V(0, -0.1, 0))
	k.ball(DARK_BROWN, V(0.62, 0.34, 0.44), V(0, 0.14, 0))
	k.box(DARK_BROWN, V(0.06, 0.16, 0.06), V(0, 0.34, 0))
end

DESIGNS.Pumpkin = function(k: Kit)
	k.ball(ORANGE, V(0.46, 0.62, 0.42), V(-0.2, 0, 0.02))
	k.ball(ORANGE, V(0.46, 0.62, 0.42), V(0.2, 0, 0.02))
	k.ball(rgb(255, 160, 60), V(0.52, 0.66, 0.44), V(0, 0, 0))
	k.box(LEAF, V(0.08, 0.18, 0.08), V(0, 0.36, 0), -10)
	for _, x in { -0.12, 0.12 } do
		k.tri(BLACK, 0.12, 0.1, 0.04, V(x, 0.07, -0.22), 0)
	end
	k.box(BLACK, V(0.26, 0.05, 0.04), V(0, -0.12, -0.22))
end

DESIGNS.Palm = function(k: Kit)
	for i = 0, 2 do
		k.ball(BROWN, V(0.16, 0.3, 0.14), V(-0.06 + i * 0.03, -0.36 + i * 0.24, 0), -8)
	end
	for i, rotation in { 70, 30, -10, -50, -90 } do
		local angle = math.rad(rotation + 90)
		k.ball(GREEN, V(0.16, 0.5, 0.08), V(math.cos(angle) * 0.22, 0.32 + math.sin(angle) * 0.14 - (if i == 1 or i == 5 then 0.06 else 0), -0.02), rotation)
	end
	k.ball(DARK_BROWN, V(0.12, 0.12, 0.12), V(-0.06, 0.22, -0.06))
	k.ball(DARK_BROWN, V(0.12, 0.12, 0.12), V(0.07, 0.21, -0.06))
end

DESIGNS.Shell = function(k: Kit)
	for i = 0, 4 do
		local rotation = -48 + i * 24
		local angle = math.rad(rotation + 90)
		k.ball(rgb(255, 175, 160), V(0.2, 0.62, 0.16), V(math.cos(angle) * 0.22, -0.2 + math.sin(angle) * 0.24, -0.01 * (i % 2)), rotation)
	end
	k.tri(rgb(255, 150, 140), 0.26, 0.16, 0.14, V(0, -0.36, 0), 180)
end

DESIGNS.Starfish = function(k: Kit)
	k.star(ORANGE, 5, 0.5, 0.2, 0.14, V(0, 0, 0))
	for i = 0, 4 do
		local angle = math.rad(90 + i * 72)
		k.ball(rgb(255, 205, 140), V(0.06, 0.06, 0.04), V(math.cos(angle) * 0.22, math.sin(angle) * 0.22, -0.08))
	end
end

DESIGNS.Bee = function(k: Kit)
	k.ball(Color3.new(1, 1, 1), V(0.3, 0.4, 0.06), V(-0.12, 0.3, 0.06), 25).Transparency = 0.3
	k.ball(Color3.new(1, 1, 1), V(0.3, 0.4, 0.06), V(0.12, 0.3, 0.06), -25).Transparency = 0.3
	k.ball(YELLOW, V(0.72, 0.52, 0.44), V(0, 0, 0))
	for _, x in { -0.1, 0.12 } do
		k.ball(BLACK, V(0.1, 0.5, 0.46), V(x, 0, 0))
	end
	k.tri(BLACK, 0.1, 0.12, 0.08, V(0.4, -0.02, 0), -90)
	k.ball(BLACK, V(0.07, 0.09, 0.05), V(-0.24, 0.05, -0.19))
end

DESIGNS.Butterfly = function(k: Kit)
	for _, side in { -1, 1 } do
		k.ball(rgb(150, 120, 255), V(0.4, 0.46, 0.08), V(side * 0.24, 0.12, 0), side * -25)
		k.ball(rgb(255, 150, 210), V(0.3, 0.32, 0.08), V(side * 0.2, -0.2, 0), side * 20)
		k.ball(WHITE, V(0.1, 0.1, 0.04), V(side * 0.27, 0.16, -0.05))
		k.box(BLACK, V(0.025, 0.24, 0.025), V(side * 0.07, 0.42, 0), side * -25)
	end
	k.ball(BLACK, V(0.12, 0.62, 0.12), V(0, 0, -0.04))
end

DESIGNS.Chick = function(k: Kit)
	k.ball(YELLOW, V(0.76, 0.74, 0.5), V(0, 0, 0))
	k.ball(YELLOW, V(0.1, 0.22, 0.08), V(-0.03, 0.4, 0), 20)
	k.ball(YELLOW, V(0.1, 0.18, 0.08), V(0.05, 0.38, 0), -25)
	k.ball(rgb(255, 230, 120), V(0.24, 0.16, 0.08), V(0.3, -0.06, -0.12), -30)
	k.tri(ORANGE, 0.12, 0.1, 0.08, V(0, -0.04, -0.25), 180)
	face(k, 0.06, -0.23, 0.13)
end

DESIGNS.Bat = function(k: Kit)
	local wing = rgb(80, 60, 110)
	k.tri(wing, 0.5, 0.42, 0.06, V(-0.36, 0.04, 0.02), 90)
	k.tri(wing, 0.5, 0.42, 0.06, V(0.36, 0.04, 0.02), -90)
	for _, side in { -1, 1 } do
		k.tri(wing, 0.1, 0.14, 0.08, V(side * 0.1, 0.27, 0), 0)
	end
	k.ball(wing, V(0.36, 0.42, 0.3), V(0, 0, 0))
	for _, side in { -1, 1 } do
		k.ball(rgb(255, 230, 120), V(0.07, 0.08, 0.04), V(side * 0.07, 0.05, -0.14))
	end
end

DESIGNS.Ghost = function(k: Kit)
	k.ball(WHITE, V(0.66, 0.78, 0.42), V(0, 0.08, 0))
	for _, x in { -0.2, 0, 0.2 } do
		k.ball(WHITE, V(0.26, 0.26, 0.4), V(x, -0.28, 0))
	end
	k.box(WHITE, V(0.66, 0.24, 0.42), V(0, -0.14, 0))
	face(k, 0.12, -0.2, 0.12)
	k.ball(BLACK, V(0.08, 0.1, 0.04), V(0, -0.02, -0.21))
end

DESIGNS.Moon = function(k: Kit)
	for i = 0, 6 do
		local angle = math.rad(-80 + i * (160 / 6))
		local size = 0.16 + 0.2 * math.sin(math.rad(i * 30))
		k.ball(LIGHT_YELLOW, V(size, size, 0.24), V(-0.1 + math.cos(angle) * 0.3, math.sin(angle) * 0.36, 0))
	end
	k.star(YELLOW, 4, 0.14, 0.04, 0.05, V(0.16, 0.22, 0))
end

DESIGNS.Snowflake = function(k: Kit)
	for i = 0, 2 do
		local spoke = k.box(SKY, V(0.08, 0.92, 0.06), V(0, 0, 0), i * 60)
		spoke.Reflectance = 0.2
	end
	for i = 0, 5 do
		local angle = math.rad(90 + i * 60)
		k.ball(WHITE, V(0.12, 0.12, 0.08), V(math.cos(angle) * 0.44, math.sin(angle) * 0.44, 0))
		for _, turn in { -45, 45 } do
			k.box(SKY, V(0.05, 0.16, 0.05), V(math.cos(angle) * 0.27, math.sin(angle) * 0.27, 0), i * 60 + turn)
		end
	end
	k.disc(WHITE, 0.2, 0.08, V(0, 0, -0.01))
end

DESIGNS.Snowman = function(k: Kit)
	k.ball(WHITE, V(0.6, 0.56, 0.5), V(0, -0.24, 0))
	k.ball(WHITE, V(0.44, 0.42, 0.4), V(0, 0.14, 0))
	k.box(RED, V(0.42, 0.08, 0.4), V(0, -0.04, 0), -5)
	k.rod(BLACK, 0.06, 0.48, V(0, 0.33, 0))
	k.rod(BLACK, 0.2, 0.3, V(0, 0.44, 0))
	k.tri(ORANGE, 0.06, 0.14, 0.06, V(0.06, 0.12, -0.2), -90)
	for _, x in { -0.08, 0.08 } do
		k.ball(BLACK, V(0.05, 0.06, 0.04), V(x, 0.2, -0.19))
	end
end

DESIGNS.Tree = function(k: Kit)
	k.box(BROWN, V(0.14, 0.16, 0.14), V(0, -0.44, 0))
	for i, width in { 0.9, 0.7, 0.5 } do
		k.tri(rgb(40, 150, 70), width, 0.4, 0.2, V(0, -0.2 + (i - 1) * 0.22, 0), 0)
	end
	k.star(YELLOW, 5, 0.12, 0.05, 0.08, V(0, 0.46, 0))
	for i, p in { V(-0.16, -0.24), V(0.14, -0.14), V(-0.04, 0.06), V(0.08, 0.2) } do
		k.ball(({ RED, BLUE, YELLOW, PINK })[i], V(0.09, 0.09, 0.09), V(p.X, p.Y, -0.11))
	end
end

DESIGNS.Bell = function(k: Kit)
	local dome = k.ball(GOLD, V(0.56, 0.62, 0.46), V(0, 0.06, 0))
	dome.Reflectance = 0.25
	k.rod(GOLD, 0.14, 0.74, V(0, -0.22, 0)).Reflectance = 0.25
	k.ball(rgb(230, 170, 40), V(0.14, 0.14, 0.14), V(0, -0.34, -0.04))
	k.ball(RED, V(0.24, 0.14, 0.1), V(-0.1, 0.4, -0.02), 20)
	k.ball(RED, V(0.24, 0.14, 0.1), V(0.1, 0.4, -0.02), -20)
	k.ball(DARK_RED, V(0.09, 0.09, 0.1), V(0, 0.4, -0.04))
end

DESIGNS.Mug = function(k: Kit)
	k.box(RED, V(0.1, 0.36, 0.14), V(0.36, -0.04, 0))
	k.box(RED, V(0.14, 0.08, 0.14), V(0.31, 0.11, 0))
	k.box(RED, V(0.14, 0.08, 0.14), V(0.31, -0.19, 0))
	k.rod(RED, 0.66, 0.6, V(0, -0.04, 0))
	k.box(WHITE, V(0.58, 0.06, 0.04), V(0, -0.04, -0.3))
	k.rod(rgb(150, 95, 60), 0.04, 0.54, V(0, 0.28, 0))
	k.box(WHITE, V(0.12, 0.1, 0.1), V(-0.1, 0.32, -0.08), 15)
	k.box(WHITE, V(0.12, 0.1, 0.1), V(0.08, 0.33, 0.04), -10)
end

DESIGNS.Mitten = function(k: Kit)
	k.ball(RED, V(0.24, 0.42, 0.3), V(-0.28, 0.0, 0), 35)
	k.ball(RED, V(0.6, 0.8, 0.36), V(0, 0.08, 0))
	k.box(WHITE, V(0.6, 0.22, 0.38), V(0, -0.36, 0))
	k.star(WHITE, 6, 0.12, 0.04, 0.04, V(0.04, 0.14, -0.18))
end

DESIGNS.Basket = function(k: Kit)
	for i = 0, 4 do
		local angle = math.rad(i * 45)
		k.box(BROWN, V(0.08, 0.16, 0.08), V(math.cos(angle) * 0.3, -0.02 + math.sin(angle) * 0.34, 0.06), math.deg(angle))
	end
	k.tri(RED, 0.4, 0.2, 0.06, V(0.1, 0.0, -0.02), 10)
	k.box(TAN, V(0.82, 0.46, 0.4), V(0, -0.24, 0))
	for _, y in { -0.14, -0.32 } do
		k.box(rgb(190, 130, 70), V(0.84, 0.04, 0.42), V(0, y, 0))
	end
end

DESIGNS.Sunglasses = function(k: Kit)
	for _, x in { -0.24, 0.24 } do
		k.disc(PINK, 0.42, 0.08, V(x, 0, 0))
		local lens = k.disc(rgb(60, 40, 110), 0.34, 0.06, V(x, 0, -0.03))
		lens.Reflectance = 0.3
	end
	k.box(PINK, V(0.12, 0.05, 0.06), V(0, 0.06, 0))
	k.box(PINK, V(0.08, 0.05, 0.3), V(-0.44, 0.08, 0.14))
	k.box(PINK, V(0.08, 0.05, 0.3), V(0.44, 0.08, 0.14))
end

DESIGNS.BeachBall = function(k: Kit)
	k.ball(WHITE, V(0.82, 0.82, 0.82), V(0, 0, 0))
	for i, color in { RED, BLUE, YELLOW } do
		k.ball(color, V(0.26, 0.8, 0.1), V(0, 0, -0.37), (i - 1) * 60)
	end
	k.ball(WHITE, V(0.12, 0.12, 0.06), V(0, 0, -0.42))
end

DESIGNS.Book = function(k: Kit)
	k.box(WHITE, V(0.6, 0.8, 0.16), V(0.04, 0, 0.02))
	k.box(rgb(90, 130, 230), V(0.62, 0.84, 0.06), V(0, 0, -0.08))
	k.box(rgb(60, 95, 190), V(0.08, 0.84, 0.18), V(-0.3, 0, 0))
	k.box(rgb(255, 225, 120), V(0.36, 0.14, 0.02), V(0.04, 0.18, -0.12))
	k.box(RED, V(0.06, 0.26, 0.02), V(0.16, -0.46, -0.1))
end

DESIGNS.Pencil = function(k: Kit)
	k.frame = CFrame.Angles(0, 0, math.rad(-35))
	k.rod(YELLOW, 0.66, 0.18, V(0, 0.02, 0))
	k.rod(rgb(200, 200, 210), 0.08, 0.19, V(0, 0.39, 0))
	k.rod(PINK, 0.12, 0.18, V(0, 0.49, 0))
	k.tri(rgb(240, 200, 150), 0.18, 0.18, 0.17, V(0, -0.4, 0), 180)
	k.tri(BLACK, 0.06, 0.06, 0.06, V(0, -0.47, -0.02), 180)
end

DESIGNS.Ruler = function(k: Kit)
	k.frame = CFrame.Angles(0, 0, math.rad(30))
	k.box(rgb(255, 220, 90), V(0.24, 0.96, 0.06), V(0, 0, 0))
	for i = 0, 6 do
		k.box(BLACK, V(if i % 2 == 0 then 0.1 else 0.06, 0.025, 0.02), V(-0.07 + (if i % 2 == 0 then 0 else -0.02), -0.39 + i * 0.13, -0.04))
	end
end

DESIGNS.Backpack = function(k: Kit)
	k.box(rgb(70, 140, 240), V(0.12, 0.08, 0.1), V(0, 0.44, 0))
	k.ball(rgb(90, 160, 255), V(0.66, 0.4, 0.36), V(0, 0.22, 0))
	k.box(rgb(90, 160, 255), V(0.66, 0.6, 0.36), V(0, -0.1, 0))
	k.box(rgb(60, 120, 220), V(0.48, 0.28, 0.08), V(0, -0.2, -0.19))
	k.box(YELLOW, V(0.4, 0.03, 0.02), V(0, -0.1, -0.24))
end

DESIGNS.TopHat = function(k: Kit)
	k.rod(rgb(40, 140, 70), 0.08, 0.86, V(0, -0.28, 0))
	k.rod(rgb(50, 170, 80), 0.56, 0.54, V(0, 0.04, 0))
	k.rod(GOLD, 0.12, 0.56, V(0, -0.16, 0))
	k.box(rgb(255, 235, 140), V(0.14, 0.1, 0.04), V(0, -0.16, -0.28))
end

-- Sparkles -------------------------------------------------------------------------

DESIGNS.Star = function(k: Kit)
	k.star(YELLOW, 5, 0.5, 0.22, 0.2, V(0, 0, 0))
	k.ball(WHITE, V(0.1, 0.06, 0.04), V(-0.08, 0.12, -0.11), 25)
end

DESIGNS.Sparkle = function(k: Kit)
	for _, part in k.star(rgb(255, 245, 200), 4, 0.5, 0.1, 0.08, V(0, 0, 0)) do
		k.glow(part)
	end
	for _, part in k.star(rgb(255, 225, 120), 4, 0.22, 0.05, 0.08, V(0.32, 0.3, 0)) do
		k.glow(part)
	end
end

DESIGNS.Firework = function(k: Kit)
	local colors = { RED, YELLOW, BLUE, PINK, GREEN, PURPLE }
	for i = 0, 9 do
		local angle = i * 36
		local direction = V(math.cos(math.rad(angle + 90)), math.sin(math.rad(angle + 90)), 0)
		local color = colors[(i % #colors) + 1]
		k.glow(k.box(color, V(0.05, 0.28, 0.05), direction * 0.24, angle))
		k.glow(k.ball(color, V(0.1, 0.1, 0.1), direction * 0.44))
	end
	k.glow(k.ball(WHITE, V(0.16, 0.16, 0.16), V(0, 0, 0)))
end

local NAMES: { string } = {}
for name in DESIGNS do
	table.insert(NAMES, name)
end
table.sort(NAMES)
CharmBuilder.NAMES = NAMES

function CharmBuilder.has(name: string): boolean
	return DESIGNS[name] ~= nil
end

function CharmBuilder.build(name: string, options: Options?): Model
	local settings = options or {}
	local model = Instance.new("Model")
	model.Name = "Charm_" .. name

	-- An invisible root in the middle of the charm: the model's pivot, and
	-- (when welded) the one part to move to move the whole charm.
	local root = Instance.new("Part")
	root.Name = "Root"
	root.Size = Vector3.one * 0.05
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.CanQuery = false
	root.CanTouch = false
	root.CastShadow = false
	root.CFrame = CFrame.new()
	root.Parent = model
	model.PrimaryPart = root

	local kit = newKit(model, settings.scale or 1)
	local design = DESIGNS[name] or DESIGNS.Star
	design(kit)

	if settings.welded then
		for _, child in model:GetChildren() do
			if child:IsA("BasePart") and child ~= root then
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = root
				weld.Part1 = child
				weld.Parent = child
				child.Anchored = false
			end
		end
	end
	return model
end

return CharmBuilder
