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
	  * and adds a pattern on every main-colour piece, following its shape
	    (round pieces get rings that wrap around them, and so on):
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

-- A pattern piece stuck to one piece of the gun (`host`).
local function decoration(host: BasePart, name: string, size: Vector3, color: Color3, material: Enum.Material, offset: CFrame, ball: boolean): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = material
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Anchored = host.Anchored
	part.CanCollide = false
	part.CanQuery = false -- bullets ignore it
	part.CanTouch = false
	part.Massless = true
	part.CastShadow = false
	part.CFrame = host.CFrame * offset
	part:SetAttribute(KEEP_VISIBLE_ATTRIBUTE, true)
	part:SetAttribute(DECORATION_ATTRIBUTE, true)
	if ball then
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
	end
	if not host.Anchored then
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = host
		weld.Part1 = part
		weld.Parent = part
	end
	return part
end

--[[
	Draws the skin's pattern on one main-colour piece, following its shape:
	  * round pieces (cylinders): stripes wrap around as rings, beads and
	    bubbles sit on the curved surface, the line runs along each side;
	  * balls: beads and bubbles all over;
	  * boxes: bands around, beads on the sides and top, a line on each side.
	Glue drips hang underneath. Bigger pieces get more pattern.
]]
local function patternOn(host: BasePart, skin: SkinItem, random: Random, pieces: { Part })
	local colors = skin.PatternColors
	local pattern = skin.Pattern
	local function colorAt(i: number): Color3
		return colors[(i % #colors) + 1]
	end
	local size = host.Size
	local isBubbles = pattern == "Bubbles"

	if host.Shape == Enum.PartType.Cylinder then
		-- A cylinder's length runs along its X; its round sides face Y and Z.
		local length, radius = size.X, size.Y / 2
		local unit = size.Y / 0.42
		if pattern == "Stripes" then
			local count = math.max(2, math.floor(length / (0.3 * unit)))
			for i = 1, count do
				local x = -length / 2 + length * (i - 0.5) / count
				local ring = decoration(host, "Stripe", Vector3.new(0.07 * unit, radius * 2 + 0.03, radius * 2 + 0.03), colorAt(i), skin.PatternMaterial, CFrame.new(x, 0, 0), false)
				ring.Shape = Enum.PartType.Cylinder
				table.insert(pieces, ring)
			end
		elseif pattern == "Spots" or isBubbles then
			for i = 1, math.max(3, math.floor(length / (0.12 * unit))) do
				local angle = random:NextNumber(0, math.pi * 2)
				local x = random:NextNumber(-0.45, 0.45) * length
				local d = random:NextNumber(0.06, if isBubbles then 0.14 else 0.11) * unit
				local bead = decoration(host, if isBubbles then "Bubble" else "Bead", Vector3.one * d, colorAt(i), skin.PatternMaterial,
					CFrame.new(x, math.cos(angle) * radius, math.sin(angle) * radius), true)
				if isBubbles then
					bead.Transparency = 0.35
				end
				table.insert(pieces, bead)
			end
		elseif pattern == "Line" then
			for _, side in { -1, 1 } do
				table.insert(pieces, decoration(host, "Line", Vector3.new(length * 0.9, radius * 0.3, 0.03 * unit), colorAt(1), skin.PatternMaterial,
					CFrame.new(0, radius * 0.25, side * (radius + 0.01)), false))
			end
		elseif pattern == "Drips" then
			local count = math.max(2, math.floor(length / (0.35 * unit)))
			for i = 1, count do
				local dripLength = (0.16 + (i % 3) * 0.08) * unit
				local x = -length / 2 + length * (i - 0.5) / count
				local drip = decoration(host, "Drip", Vector3.new(0.1 * unit, dripLength, 0.1 * unit), colorAt(i), skin.PatternMaterial,
					CFrame.new(x, -radius - dripLength * 0.3, 0), true)
				drip.Reflectance = 0.15
				table.insert(pieces, drip)
			end
		end
		return
	end

	if host.Shape == Enum.PartType.Ball then
		if pattern == "Spots" or isBubbles then
			local radius = size.X / 2
			for i = 1, 6 do
				local dir = Vector3.new(random:NextNumber(-1, 1), random:NextNumber(-1, 1), random:NextNumber(-1, 1)).Unit
				local bead = decoration(host, if isBubbles then "Bubble" else "Bead", Vector3.one * radius * 0.3, colorAt(i), skin.PatternMaterial, CFrame.new(dir * radius), true)
				if isBubbles then
					bead.Transparency = 0.35
				end
				table.insert(pieces, bead)
			end
		end
		return
	end

	-- A box: its length runs along Z.
	local unit = size.X / 0.42
	if pattern == "Stripes" then
		local count = math.max(2, math.floor(size.Z / (0.3 * unit)))
		for i = 1, count do
			local z = -size.Z / 2 + size.Z * (i - 0.5) / count
			table.insert(pieces, decoration(host, "Stripe", Vector3.new(size.X + 0.02, size.Y + 0.02, 0.07 * unit), colorAt(i), skin.PatternMaterial, CFrame.new(0, 0, z), false))
		end
	elseif pattern == "Spots" or isBubbles then
		for i = 1, math.max(3, math.floor(size.Z / (0.1 * unit))) do
			local side = if i % 2 == 0 then 1 else -1
			local onTop = not isBubbles and i % 5 == 0
			local d = random:NextNumber(0.06, if isBubbles then 0.14 else 0.12) * unit
			local z = random:NextNumber(-0.42, 0.42) * size.Z
			local offset = if onTop
				then CFrame.new(random:NextNumber(-0.3, 0.3) * size.X, size.Y / 2, z)
				else CFrame.new(side * size.X / 2, random:NextNumber(-0.35, 0.35) * size.Y, z)
			local bead = decoration(host, if isBubbles then "Bubble" else "Bead", Vector3.one * d, colorAt(i), skin.PatternMaterial, offset, true)
			if isBubbles then
				bead.Transparency = 0.35
			end
			table.insert(pieces, bead)
		end
	elseif pattern == "Line" then
		for _, side in { -1, 1 } do
			table.insert(pieces, decoration(host, "Line", Vector3.new(0.03 * unit, size.Y * 0.16, size.Z * 0.9), colorAt(1), skin.PatternMaterial, CFrame.new(side * (size.X / 2 + 0.012), size.Y * 0.12, 0), false))
		end
	elseif pattern == "Drips" then
		local count = math.max(2, math.floor(size.Z / (0.3 * unit)))
		for i = 1, count do
			local dripLength = (0.16 + (i % 3) * 0.08) * unit
			local z = -size.Z / 2 + size.Z * (i - 0.5) / count + random:NextNumber(-0.05, 0.05) * size.Z
			local drip = decoration(host, "Drip", Vector3.new(0.1 * unit, dripLength, 0.1 * unit), colorAt(i), skin.PatternMaterial,
				CFrame.new(random:NextNumber(-0.25, 0.25) * size.X, -size.Y / 2 - dripLength * 0.3, z), true)
			drip.Reflectance = 0.15
			table.insert(pieces, drip)
		end
	end
end

-- The pattern goes on every main-colour piece (receiver, handguard, stock, shroud...).
local function addPattern(gun: Model, skin: SkinItem)
	if skin.Pattern == "None" or #skin.PatternColors == 0 then
		return
	end
	local random = Random.new(#skin.Id * 7 + #gun.Name)
	local pieces: { Part } = {}
	for _, part in gun:GetDescendants() do
		if part:IsA("Part") and part:GetAttribute(GunBuilder.ROLE_ATTRIBUTE) == "Body" then
			patternOn(part, skin, random, pieces)
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
	addPattern(gun, skin)
	gun:SetAttribute(WeaponSkins.SKIN_ATTRIBUTE, skin.Id)
end

return WeaponSkins
