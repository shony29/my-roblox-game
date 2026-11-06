--!strict
--[[
	WeaponSkins
	===========
	Paints a gun with a skin from ShopConfig (the shop's "Skins" tab).

	Guns are built by Cosmetics/GunBuilder from pieces with a role (Body,
	Trim, Accent, Metal) and remember their own colours. A skin:
	  * repaints Body pieces (main colour, material, shine, see-through),
	  * repaints Trim pieces (grips, magazines, caps) and Accent pieces,
	  * leaves the dark Metal pieces alone,
	  * and adds a pattern on the gun's main block ("Body"):
	      Stripes  bands around it (marbled clay)
	      Spots    little foam beads
	      Line     a glowing line along each side
	      Bubbles  see-through bubbles (activator)
	      Drips    glue drips hanging underneath
	The Classic skin puts every piece back to the gun's own colours.
	The server uses this on real guns; the shop uses it on its pictures.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ShopConfig = require(Shared:WaitForChild("Config"):WaitForChild("ShopConfig"))
local GunBuilder = require(Shared:WaitForChild("Cosmetics"):WaitForChild("GunBuilder"))

type SkinItem = ShopConfig.SkinItem

local KEEP_VISIBLE_ATTRIBUTE = "IsBlobPart" -- see server/Components/BlobCharacter
local DECORATION_ATTRIBUTE = "SkinDecoration"

local WeaponSkins = {}

WeaponSkins.SKIN_ATTRIBUTE = "SkinId"

-- A pattern piece stuck to the gun's main block.
local function decoration(body: BasePart, name: string, size: Vector3, color: Color3, material: Enum.Material, offset: CFrame, ball: boolean): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = body.Anchored
	part.CanCollide = false
	part.CanQuery = false -- bullets ignore it
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.CFrame = body.CFrame * offset
	part:SetAttribute(KEEP_VISIBLE_ATTRIBUTE, true)
	part:SetAttribute(DECORATION_ATTRIBUTE, true)
	if ball then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end
	if not body.Anchored then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = body
		weld.Part1 = part
		weld.Parent = part
	end
	return part
end

local function addPattern(gun: Model, body: BasePart, skin: SkinItem)
	local colors = skin.PatternColors
	if skin.Pattern == "None" or #colors == 0 then
		return
	end
	local size = body.Size
	local unit = size.X / 0.42 -- pattern pieces grow with the gun
	local random = Random.new(#skin.Id * 7 + math.floor(size.Z * 100))
	local function colorAt(i: number): Color3
		return colors[(i % #colors) + 1]
	end
	local pieces: { Part } = {}

	if skin.Pattern == "Stripes" then
		local count = math.max(2, math.floor(size.Z / (0.3 * unit)))
		for i = 1, count do
			local z = -size.Z / 2 + size.Z * (i - 0.5) / count
			table.insert(pieces, decoration(body, "Stripe", Vector3.new(size.X + 0.02, size.Y + 0.02, 0.07 * unit), colorAt(i), skin.PatternMaterial, CFrame.new(0, 0, z), false))
		end
	elseif skin.Pattern == "Spots" then
		for i = 1, 14 do
			local side = if i % 2 == 0 then 1 else -1
			local onTop = i % 5 == 0
			local d = random:NextNumber(0.07, 0.12) * unit
			local z = random:NextNumber(-0.42, 0.42) * size.Z
			local offset = if onTop
				then CFrame.new(random:NextNumber(-0.3, 0.3) * size.X, size.Y / 2, z)
				else CFrame.new(side * size.X / 2, random:NextNumber(-0.35, 0.35) * size.Y, z)
			table.insert(pieces, decoration(body, "Bead", Vector3.one * d, colorAt(i), skin.PatternMaterial, offset, true))
		end
	elseif skin.Pattern == "Line" then
		for _, side in { -1, 1 } do
			table.insert(pieces, decoration(body, "Line", Vector3.new(0.03 * unit, size.Y * 0.16, size.Z * 0.9), colorAt(1), skin.PatternMaterial, CFrame.new(side * (size.X / 2 + 0.012), size.Y * 0.12, 0), false))
		end
	elseif skin.Pattern == "Bubbles" then
		for i = 1, 9 do
			local side = if i % 2 == 0 then 1 else -1
			local d = random:NextNumber(0.06, 0.14) * unit
			local bubble = decoration(body, "Bubble", Vector3.one * d, colorAt(i), skin.PatternMaterial,
				CFrame.new(side * size.X / 2, random:NextNumber(-0.35, 0.35) * size.Y, random:NextNumber(-0.42, 0.42) * size.Z), true)
			bubble.Transparency = 0.35
			table.insert(pieces, bubble)
		end
	elseif skin.Pattern == "Drips" then
		for i = 1, 5 do
			local length = (0.16 + (i % 3) * 0.08) * unit
			local z = -size.Z / 2 + size.Z * (i - 0.5) / 5 + random:NextNumber(-0.05, 0.05) * size.Z
			local drip = decoration(body, "Drip", Vector3.new(0.1 * unit, length, 0.1 * unit), colorAt(i), skin.PatternMaterial, CFrame.new(random:NextNumber(-0.25, 0.25) * size.X, -size.Y / 2 - length * 0.3, z), true)
			drip.Reflectance = 0.15
			table.insert(pieces, drip)
		end
	end
	for _, piece in pieces do
		piece.Parent = gun
	end
end

function WeaponSkins.apply(gun: Model, skin: SkinItem)
	-- Take off the old skin's pattern.
	for _, child in gun:GetDescendants() do
		if child:GetAttribute(DECORATION_ATTRIBUTE) then
			child:Destroy()
		end
	end
	for _, part in gun:GetDescendants() do
		if part:IsA("BasePart") then
			local role = part:GetAttribute(GunBuilder.ROLE_ATTRIBUTE)
			local default = part:GetAttribute(GunBuilder.DEFAULT_COLOR_ATTRIBUTE)
			local own = if typeof(default) == "Color3" then default else part.Color
			if role == "Body" then
				part.Color = skin.BodyColor or own
				part.Material = skin.BodyMaterial
				part.Reflectance = skin.Reflectance
				part.Transparency = skin.BodyTransparency or 0
			elseif role == "Trim" then
				part.Color = skin.TrimColor or own
				part.Material = skin.TrimMaterial
			elseif role == "Accent" then
				part.Color = skin.AccentColor or own
				part.Material = skin.TrimMaterial
			end
		end
	end
	local body = gun:FindFirstChild("Body")
	if body and body:IsA("BasePart") then
		addPattern(gun, body, skin)
	end
	gun:SetAttribute(WeaponSkins.SKIN_ATTRIBUTE, skin.Id)
end

return WeaponSkins
