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

-- A tall glass tube full of glowing slime, with metal caps.
function LobbyProps.slimeTube(parent: Instance, base: Vector3, height: number, diameter: number, slimeColor: Color3)
	local cap = 1.6
	MapKit.cylinder(parent, "TubeBase", base, cap, diameter + 1.4, LobbyProps.METAL_DARK, { material = Enum.Material.DiamondPlate })
	local slime = MapKit.cylinder(parent, "TubeSlime", base + Vector3.new(0, cap, 0), (height - cap * 2) * 0.85, diameter - 0.5, slimeColor, { material = Enum.Material.Neon, collide = false, transparency = 0.1 })
	light(slime, slimeColor, 16, 1.4)
	MapKit.cylinder(parent, "TubeGlass", base + Vector3.new(0, cap, 0), height - cap * 2, diameter, Color3.fromRGB(210, 235, 255), { material = Enum.Material.Glass, transparency = 0.65 })
	MapKit.cylinder(parent, "TubeCap", base + Vector3.new(0, height - cap, 0), cap, diameter + 1.4, LobbyProps.METAL_DARK, { material = Enum.Material.DiamondPlate })
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
	billboard.Size = UDim2.fromOffset(220, 110)
	billboard.LightInfluence = 0
	billboard.MaxDistance = 140
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
