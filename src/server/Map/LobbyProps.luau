--!strict
--[[
	LobbyProps: the bunker's building blocks (used by LobbyBuilder).
	Glass slime tubes, pipes with glowing segments, hazard stripes, slime
	puddles, the octagon portal frame, queue pads and neon signs.
]]

local MapKit = require(script.Parent.MapKit)

local LobbyProps = {}

LobbyProps.METAL = Color3.fromRGB(78, 80, 88)
LobbyProps.METAL_DARK = Color3.fromRGB(48, 50, 56)
LobbyProps.GREEN = Color3.fromRGB(120, 255, 90)
LobbyProps.PURPLE = Color3.fromRGB(190, 90, 255)
LobbyProps.CYAN = Color3.fromRGB(90, 220, 255)

local function light(parent: Instance, color: Color3, range: number, brightness: number)
	local pointLight = Instance.new("PointLight")
	pointLight.Color = color
	pointLight.Range = range
	pointLight.Brightness = brightness
	pointLight.Parent = parent
end
LobbyProps.light = light

--[[
	A tall glass tube full of glowing slime, with metal caps and a glowing
	ring at each end. The slime is a bright core inside a softer outer
	layer, with a rounded top. On each player's screen the client's
	LobbyAnimator brings it to life: bubbles rise through it, the top
	wobbles and sloshes, and the glow gently breathes.

	The glass is see-through plastic, NOT Roblox's Glass material: Glass
	hides everything see-through behind it, which made the slime vanish.
	Returns the tube's model.
]]
function LobbyProps.slimeTube(parent: Instance, base: Vector3, height: number, diameter: number, slimeColor: Color3): Model
	local model = Instance.new("Model")
	model.Name = "SlimeTube"
	local cap = 1.6
	local inside = height - cap * 2 -- the glass between the two caps
	local level = inside * 0.88 -- how high the slime reaches
	local slimeDiameter = diameter - 0.4
	local bottom = base + Vector3.new(0, cap, 0)
	local glow: MapKit.Options = { material = Enum.Material.Neon, collide = false, shadow = false }

	MapKit.cylinder(model, "TubeBase", base, cap, diameter + 1.4, LobbyProps.METAL_DARK, { material = Enum.Material.DiamondPlate })
	MapKit.cylinder(model, "TubeCap", base + Vector3.new(0, height - cap, 0), cap, diameter + 1.4, LobbyProps.METAL_DARK, { material = Enum.Material.DiamondPlate })
	for _, y in { cap, height - cap - 0.25 } do
		MapKit.cylinder(model, "TubeRing", base + Vector3.new(0, y, 0), 0.25, diameter + 0.5, slimeColor, glow)
	end

	-- The slime: a bright core, a softer outer layer and a rounded top.
	local core = MapKit.cylinder(model, "TubeSlimeCore", bottom, level - 0.3, slimeDiameter * 0.6, slimeColor, glow)
	light(core, slimeColor, 18, 1.5)
	MapKit.cylinder(model, "TubeSlime", bottom, level, slimeDiameter, slimeColor, { material = Enum.Material.Neon, collide = false, shadow = false, transparency = 0.45 })
	local surface = MapKit.part(model, "TubeSurface", Vector3.new(slimeDiameter, math.min(1.4, slimeDiameter * 0.3), slimeDiameter), CFrame.new(bottom + Vector3.new(0, level, 0)),
		slimeColor:Lerp(Color3.new(1, 1, 1), 0.25), { material = Enum.Material.Neon, collide = false, shadow = false, transparency = 0.2 })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere -- a squashed ball
	mesh.Parent = surface

	-- The glass, with two soft shines down its front.
	local glass = MapKit.cylinder(model, "TubeGlass", bottom, inside, diameter, Color3.fromRGB(215, 240, 255), { material = Enum.Material.SmoothPlastic, transparency = 0.86, shadow = false })
	glass.Reflectance = 0.08
	for index, angle in { 100, 116 } do
		local direction = Vector3.new(math.cos(math.rad(angle)), 0, math.sin(math.rad(angle)))
		local spot = bottom + Vector3.new(0, inside / 2, 0) + direction * (diameter / 2 + 0.03)
		MapKit.part(model, "TubeShine", Vector3.new(if index == 1 then 0.32 else 0.14, inside * 0.84, 0.06), CFrame.lookAt(spot, spot + direction), Color3.new(1, 1, 1), { collide = false, shadow = false, transparency = 0.55 })
	end

	-- What the client's LobbyAnimator needs to move the slime.
	model:SetAttribute("SlimeTube", true)
	model:SetAttribute("SlimeColor", slimeColor)
	model:SetAttribute("SlimeBottom", bottom)
	model:SetAttribute("SlimeLevel", level)
	model:SetAttribute("SlimeDiameter", slimeDiameter)
	model.Parent = parent
	return model
end

-- A straight pipe between two points, with a glowing glass section in the middle.
function LobbyProps.pipe(parent: Instance, from: Vector3, to: Vector3, diameter: number, glow: Color3?)
	local length = (to - from).Magnitude
	local middle = (from + to) / 2
	local cf = CFrame.lookAt(middle, to) * CFrame.Angles(0, math.rad(90), 0)
	local pipe = MapKit.part(parent, "Pipe", Vector3.new(length, diameter, diameter), cf, LobbyProps.METAL, { material = Enum.Material.Metal })
	pipe.Shape = Enum.PartType.Cylinder
	if glow then
		local section = MapKit.part(parent, "PipeGlow", Vector3.new(math.min(length * 0.4, 14), diameter * 0.92, diameter * 0.92), cf, glow, { material = Enum.Material.Neon, collide = false, transparency = 0.15 })
		section.Shape = Enum.PartType.Cylinder
		for _, side in { -1, 1 } do
			local ring = MapKit.part(parent, "PipeRing", Vector3.new(0.8, diameter * 1.25, diameter * 1.25), cf * CFrame.new(side * math.min(length * 0.2, 7), 0, 0), LobbyProps.METAL_DARK, { material = Enum.Material.DiamondPlate })
			ring.Shape = Enum.PartType.Cylinder
		end
	end
end

-- Yellow and black hazard stripes along a line on the floor.
function LobbyProps.hazardLine(parent: Instance, from: Vector3, to: Vector3, width: number)
	local direction = to - from
	local count = math.max(1, math.floor(direction.Magnitude / 2))
	local step = direction / count
	for i = 0, count - 1 do
		local center = from + step * (i + 0.5) + Vector3.new(0, 0.06, 0)
		local color = if i % 2 == 0 then Color3.fromRGB(245, 200, 40) else Color3.fromRGB(30, 30, 34)
		MapKit.part(parent, "Hazard", Vector3.new(width, 0.12, step.Magnitude), CFrame.lookAt(center, center + step), color, { collide = false, shadow = false })
	end
end

-- A glowing slime puddle: a few overlapping flat blobs.
function LobbyProps.puddle(parent: Instance, center: Vector3, size: number, color: Color3)
	for i = 1, 3 do
		local d = size * (1 - (i - 1) * 0.25)
		local offset = Vector3.new(MapKit.random(-0.3, 0.3) * size, 0.05 + i * 0.02, MapKit.random(-0.3, 0.3) * size)
		MapKit.cylinder(parent, "Puddle", center + offset, 0.1, d, color, { material = Enum.Material.Neon, collide = false, shadow = false, transparency = 0.15 })
	end
end

-- An octagon door frame in a wall facing +Z, centred at `center`. The bottom
-- piece is left out so you can walk through.
function LobbyProps.octagonFrame(parent: Instance, center: Vector3, radius: number, color: Color3, depth: number, thickness: number, material: Enum.Material)
	local side = 2 * radius * math.tan(math.rad(22.5))
	for i = 0, 7 do
		local angle = math.rad(i * 45)
		if i ~= 6 then -- i = 6 points straight down: that's the floor gap
			local position = center + Vector3.new(math.cos(angle) * radius, math.sin(angle) * radius, 0)
			local cf = CFrame.new(position) * CFrame.Angles(0, 0, angle + math.rad(90))
			MapKit.part(parent, "Portal", Vector3.new(side + thickness * 0.8, thickness, depth), cf, color, { material = material })
		end
	end
end

-- A big neon sign: text on the front of a thin panel, glowing in the dark.
function LobbyProps.neonSign(parent: Instance, name: string, size: Vector3, cframe: CFrame, text: string, color: Color3, panelColor: Color3?)
	local panel = MapKit.part(parent, name, size, cframe, panelColor or LobbyProps.METAL_DARK, { material = Enum.Material.Metal })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0 -- glows even in the dark
	gui.Parent = panel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	label.Parent = gui
	local glow = Instance.new("UIStroke")
	glow.Color = color:Lerp(Color3.new(0, 0, 0), 0.5)
	glow.Thickness = 3
	glow.Parent = label
	return panel
end

--[[
	A queue pad: a glowing ring on the floor with posts, and a counter
	("0/2") floating above it. Stand on it to queue for its mode.
]]
function LobbyProps.queuePad(parent: Instance, center: Vector3, radius: number, color: Color3, title: string): (BasePart, TextLabel)
	local diameter = radius * 2
	MapKit.cylinder(parent, "PadGlow", center, 0.25, diameter + 0.6, color, { material = Enum.Material.Neon, collide = false, shadow = false })
	local pad = MapKit.cylinder(parent, "Pad", center + Vector3.new(0, 0.05, 0), 0.3, diameter - 1, LobbyProps.METAL_DARK, { material = Enum.Material.DiamondPlate, collide = false, shadow = false })
	for i = 0, 5 do
		local angle = math.rad(i * 60 + 30)
		local post = center + Vector3.new(math.cos(angle) * (radius + 0.4), 1.5, math.sin(angle) * (radius + 0.4))
		MapKit.part(parent, "PadPost", Vector3.new(0.5, 3, 0.5), CFrame.new(post), color, { material = Enum.Material.Neon, shadow = false })
	end
	light(pad, color, 14, 1)

	local anchor = MapKit.part(parent, "PadCounter", Vector3.new(1, 1, 1), CFrame.new(center + Vector3.new(0, 8, 0)), color, { collide = false, transparency = 1, shadow = false })
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Counter"
	billboard.Size = UDim2.fromScale(7, 3.5) -- in studs, so it shrinks with distance
	billboard.LightInfluence = 0
	billboard.MaxDistance = 120
	billboard.Parent = anchor
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.fromScale(1, 0.4)
	titleLabel.Font = Enum.Font.LuckiestGuy
	titleLabel.TextScaled = true
	titleLabel.TextColor3 = color
	titleLabel.TextStrokeTransparency = 0.2
	titleLabel.Text = title
	titleLabel.Parent = billboard
	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.BackgroundTransparency = 1
	count.Position = UDim2.fromScale(0, 0.4)
	count.Size = UDim2.fromScale(1, 0.6)
	count.Font = Enum.Font.LuckiestGuy
	count.TextScaled = true
	count.TextColor3 = Color3.new(1, 1, 1)
	count.TextStrokeTransparency = 0.2
	count.Text = "0/0"
	count.Parent = billboard
	return pad, count
end

return LobbyProps
