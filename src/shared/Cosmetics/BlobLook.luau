--!strict
--[[
	BlobLook: a standalone copy of the jelly slime, for pictures (the shop).

	It uses the same pieces, sizes and colour shades as the real character
	(server/Components/BlobCharacter): a wide puddle base, the main dome,
	melty lobes, a drip, dollops on top, a glossy see-through shell and a
	soft shine. If you change the slime's shape there, change it here too.

	The real face is drawn with a SurfaceGui, which Roblox doesn't show
	inside ViewportFrames, so this copy builds the face from tiny parts:
	glossy eyes with sparkles, rosy cheeks and a small smile.

	Everything is anchored and sits on a floor at y = 0, facing -Z.
]]

local BlobLook = {}

type Shade = "Deep" | "Mid" | "Main" | "Light" | "Gloss"

type Piece = {
	name: string,
	size: Vector3,
	center: Vector3, -- above the floor
	shade: Shade,
	transparency: number?,
}

local INK = Color3.fromRGB(45, 32, 58)
local CHEEK = Color3.fromRGB(255, 130, 165)
local DOME_CENTER = Vector3.new(0, 1.95, 0)
local DOME_SIZE = Vector3.new(4.3, 3.5, 4.1)
local SHELL_SIZE = DOME_SIZE * 1.06

-- The same pieces as BlobCharacter.apply (floor at y = 0).
local PIECES: { Piece } = {
	{ name = "Base", size = Vector3.new(5.3, 1.5, 5.1), center = Vector3.new(0, 0.62, 0), shade = "Deep" },
	{ name = "Dome", size = DOME_SIZE, center = DOME_CENTER, shade = "Main" },
	{ name = "LobeLeft", size = Vector3.new(2.0, 1.8, 2.1), center = Vector3.new(-2.0, 0.95, 0.35), shade = "Mid" },
	{ name = "LobeRight", size = Vector3.new(1.8, 1.6, 1.9), center = Vector3.new(2.05, 0.85, -0.3), shade = "Mid" },
	{ name = "LobeBack", size = Vector3.new(2.6, 1.7, 2.0), center = Vector3.new(0.3, 0.9, 1.9), shade = "Mid" },
	{ name = "Drip", size = Vector3.new(1.3, 0.75, 1.3), center = Vector3.new(-1.35, 0.3, -2.05), shade = "Deep" },
	{ name = "Dollop", size = Vector3.new(1.9, 1.4, 1.8), center = Vector3.new(0.6, 3.45, 0.25), shade = "Light" },
	{ name = "DollopSmall", size = Vector3.new(1.2, 0.95, 1.15), center = Vector3.new(-0.75, 3.35, 0.45), shade = "Light" },
	{ name = "Shell", size = SHELL_SIZE, center = DOME_CENTER, shade = "Gloss", transparency = 0.6 },
}

local function shade(color: Color3, saturationScale: number, valueScale: number): Color3
	local h, s, v = color:ToHSV()
	return Color3.fromHSV(h, math.clamp(s * saturationScale, 0, 1), math.clamp(v * valueScale, 0, 1))
end

-- The five shades of one slime colour (same as BlobCharacter.palette).
function BlobLook.palette(color: Color3): { [Shade]: Color3 }
	local deep = shade(color, 1.2, 0.78)
	return {
		Deep = deep,
		Mid = color:Lerp(deep, 0.45),
		Main = color,
		Light = shade(color, 0.75, 1.08),
		Gloss = shade(color, 0.45, 1.1),
	}
end

-- A point on the front (-Z side) of the shell, x/y measured from the dome's centre.
local function onFront(x: number, y: number, pushOut: number): Vector3
	local a, b, c = SHELL_SIZE.X / 2, SHELL_SIZE.Y / 2, SHELL_SIZE.Z / 2
	local inside = 1 - (x / a) ^ 2 - (y / b) ^ 2
	local z = -c * math.sqrt(math.max(inside, 0))
	return DOME_CENTER + Vector3.new(x, y, z - pushOut)
end

local function ellipsoid(parent: Instance, name: string, size: Vector3, position: Vector3, color: Color3, transparency: number?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = transparency or 0
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.CFrame = CFrame.new(position)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	part.Parent = parent
	return part
end

-- The face, made of small parts (the face sits 0.3 studs above the dome's centre).
local function buildFace(parent: Instance)
	local faceY = 0.3
	for _, side in { -1, 1 } do
		local x = side * 0.36
		ellipsoid(parent, "Eye", Vector3.new(0.3, 0.5, 0.14), onFront(x, faceY + 0.13, 0.02), INK)
		-- Sparkles: a big one up and to the side, a tiny one lower down.
		ellipsoid(parent, "Sparkle", Vector3.new(0.13, 0.14, 0.06), onFront(x + 0.04, faceY + 0.22, 0.08), Color3.new(1, 1, 1))
		ellipsoid(parent, "Glint", Vector3.new(0.06, 0.06, 0.05), onFront(x - 0.04, faceY + 0.04, 0.08), Color3.new(1, 1, 1))
		-- Rosy cheeks.
		ellipsoid(parent, "Cheek", Vector3.new(0.36, 0.17, 0.05), onFront(side * 0.74, faceY - 0.19, 0.02), CHEEK, 0.45)
	end
	-- A small, gentle smile: dots along the bottom of a circle.
	for index = 0, 6 do
		local angle = math.rad(200 + index * (140 / 6))
		local x = math.cos(angle) * 0.15
		local y = faceY - 0.12 + math.sin(angle) * 0.15
		ellipsoid(parent, "Smile", Vector3.new(0.075, 0.075, 0.05), onFront(x, y, 0.03), INK)
	end
end

--[[
	Paints the slime in `color` (`material` and `reflectance` from the shop
	item). The glossy shell always stays see-through glass.
]]
function BlobLook.recolor(model: Model, color: Color3, material: Enum.Material?, reflectance: number?)
	local colors = BlobLook.palette(color)
	for _, piece in PIECES do
		local part = model:FindFirstChild(piece.name)
		if part and part:IsA("BasePart") then
			part.Color = colors[piece.shade]
			if piece.shade == "Gloss" then
				part.Material = Enum.Material.Glass
			else
				part.Material = material or Enum.Material.SmoothPlastic
				part.Reflectance = if piece.shade == "Main" then math.max(reflectance or 0, 0.05) else (reflectance or 0)
			end
		end
	end
end

-- Builds the slime (not parented anywhere yet).
function BlobLook.build(color: Color3, material: Enum.Material?, reflectance: number?): Model
	local model = Instance.new("Model")
	model.Name = "BlobLook"
	for _, piece in PIECES do
		ellipsoid(model, piece.name, piece.size, piece.center, color, piece.transparency)
	end
	ellipsoid(model, "Shine", Vector3.new(0.95, 0.55, 0.35), onFront(-1.05, 0.95, -0.05), Color3.new(1, 1, 1), 0.35)
	buildFace(model)
	BlobLook.recolor(model, color, material, reflectance)
	model.PrimaryPart = model:FindFirstChild("Dome") :: BasePart
	return model
end

return BlobLook
