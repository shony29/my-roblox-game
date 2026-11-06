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

-- A part for the effect pictures.
local function burstPart(parent: Instance, size: Vector3, color: Color3, cframe: CFrame, shape: Enum.PartType?, material: Enum.Material?): Part
	local part = Instance.new("Part")
	part.Size = size
	part.Shape = shape or Enum.PartType.Block
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CFrame = cframe
	part.Parent = parent
	return part
end

--[[
	Toppings (kill effects): a frozen moment of the burst over a soft glow
	in the topping's colours. Sprinkles, foam, glitter and slime pieces fly
	out in 3D with motion streaks; charm packets burst out as a ring of charms.
]]
function ItemPreview.topping(parent: GuiObject, topping: ShopConfig.ToppingItem)
	local colors = topping.Colors
	local random = Random.new(#topping.Id * 13 + 7)
	-- Soft glow behind the burst (two layers, brightest in the middle).
	for index, size in { 1.0, 0.62 } do
		local glow = Instance.new("Frame")
		glow.Name = "Glow"
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = UDim2.fromScale(0.5, 0.55)
		glow.Size = UDim2.fromScale(size * 0.62, size)
		glow.BackgroundColor3 = colors[1]
		glow.BackgroundTransparency = if index == 1 then 0.84 else 0.68
		glow.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = glow
		glow.Parent = parent
	end

	if topping.Style == "Charms" then
		local charms = topping.Charms or { "⭐" }
		local pop = Instance.new("TextLabel")
		pop.BackgroundTransparency = 1
		pop.AnchorPoint = Vector2.new(0.5, 0.5)
		pop.Position = UDim2.fromScale(0.5, 0.55)
		pop.Size = UDim2.fromScale(0.3, 0.38)
		pop.TextScaled = true
		pop.TextColor3 = Color3.new(1, 1, 1)
		pop.Text = "✦"
		pop.Parent = parent
		for i = 1, 8 do
			local angle = (i / 8) * math.pi * 2 + 0.35
			local radius = if i % 2 == 0 then 0.38 else 0.28
			local charm = Instance.new("TextLabel")
			charm.BackgroundTransparency = 1
			charm.AnchorPoint = Vector2.new(0.5, 0.5)
			charm.Position = UDim2.fromScale(0.5 + math.cos(angle) * radius * 0.77, 0.55 + math.sin(angle) * radius)
			charm.Size = UDim2.fromScale(0.24, 0.3)
			charm.TextScaled = true
			charm.Rotation = random:NextNumber(-25, 25)
			charm.Text = charms[(i % #charms) + 1]
			charm.Parent = parent
		end
		return
	end

	local viewport = makeViewport(parent, CFrame.lookAt(Vector3.new(0, 0.5, -8.5), Vector3.new(0, 0.2, 0)), 38)
	viewport.Ambient = Color3.fromRGB(215, 215, 225)
	local burst = Instance.new("Model")
	burst.Name = "Burst"
	-- The popped slime in the middle: a squashed jelly splat.
	local splatColor = if topping.Style == "Slime" then colors[1] else Color3.fromRGB(120, 230, 160)
	local splat = burstPart(burst, Vector3.new(2.3, 0.9, 2.3), splatColor, CFrame.new(0, -0.55, 0))
	local splatMesh = Instance.new("SpecialMesh")
	splatMesh.MeshType = Enum.MeshType.Sphere
	splatMesh.Parent = splat
	splat.Reflectance = 0.1

	for i = 1, 26 do
		-- Mostly sideways and up, spread across the picture.
		local theta = random:NextNumber(0, math.pi * 2)
		local dir = Vector3.new(math.cos(theta), random:NextNumber(-0.3, 0.95), math.sin(theta) * 0.45).Unit
		local position = dir * random:NextNumber(1.3, 3.4)
		local along = CFrame.lookAt(position, position + dir) -- -Z points the way it flies
		local color = colors[(i % #colors) + 1]
		if topping.Style == "Sprinkles" then
			burstPart(burst, Vector3.new(0.6, 0.15, 0.15), color, along * CFrame.Angles(0, math.rad(90), 0), Enum.PartType.Cylinder)
		elseif topping.Style == "Foam" then
			local d = random:NextNumber(0.32, 0.6)
			burstPart(burst, Vector3.one * d, color, CFrame.new(position), Enum.PartType.Ball)
		elseif topping.Style == "Glitter" then
			local spin = CFrame.Angles(random:NextNumber(0, 6), random:NextNumber(0, 6), random:NextNumber(0, 6))
			burstPart(burst, Vector3.new(0.3, 0.3, 0.05), color, CFrame.new(position) * spin, nil, Enum.Material.Neon)
			if i % 5 == 0 then
				-- A little four-point twinkle.
				burstPart(burst, Vector3.new(0.09, 0.7, 0.05), Color3.new(1, 1, 1), CFrame.new(position), nil, Enum.Material.Neon)
				burstPart(burst, Vector3.new(0.7, 0.09, 0.05), Color3.new(1, 1, 1), CFrame.new(position), nil, Enum.Material.Neon)
			end
		else -- Slime: jelly droplets stretched the way they fly
			local drop = burstPart(burst, Vector3.new(0.38, 0.38, 0.75), color, along)
			local mesh = Instance.new("SpecialMesh")
			mesh.MeshType = Enum.MeshType.Sphere
			mesh.Parent = drop
			drop.Reflectance = 0.12
		end
		-- Motion streaks behind some pieces.
		if i % 3 == 0 then
			local streak = burstPart(burst, Vector3.new(1.0, 0.06, 0.06), Color3.new(1, 1, 1),
				along * CFrame.new(0, 0, 0.75) * CFrame.Angles(0, math.rad(90), 0), Enum.PartType.Cylinder)
			streak.Transparency = 0.55
		end
	end
	burst.Parent = viewport
end

return ItemPreview
