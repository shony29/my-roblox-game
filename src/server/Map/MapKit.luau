--!strict
--[[
	MapKit: small building helpers shared by map builders.
	Everything is anchored. Decorations that shouldn't block movement or
	bullets turn off collision and queries.
	All positions are on the floor (y = the floor height under the object).
]]

local MapKit = {}

export type Options = {
	material: Enum.Material?,
	collide: boolean?, -- default true
	shadow: boolean?, -- default true
	transparency: number?,
	shape: Enum.PartType?,
}

local random = Random.new(1234) -- fixed seed: the map looks the same every time

-- Slightly varies a colour so big groups of objects don't look flat.
function MapKit.vary(color: Color3, amount: number?): Color3
	local h, s, v = color:ToHSV()
	local a = amount or 0.06
	return Color3.fromHSV(h, s, math.clamp(v + random:NextNumber(-a, a), 0, 1))
end

function MapKit.random(min: number, max: number): number
	return random:NextNumber(min, max)
end

function MapKit.part(parent: Instance, name: string, size: Vector3, cframe: CFrame, color: Color3, options: Options?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = (options and options.shape) or Enum.PartType.Block
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = (options and options.material) or Enum.Material.SmoothPlastic
	p.Transparency = (options and options.transparency) or 0
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local collide = not (options and options.collide == false)
	p.CanCollide = collide
	p.CanQuery = collide
	p.CanTouch = false
	p.CastShadow = not (options and options.shadow == false)
	p.Parent = parent
	return p
end

-- An upright cylinder standing on `base`.
function MapKit.cylinder(parent: Instance, name: string, base: Vector3, height: number, diameter: number, color: Color3, options: Options?): Part
	local o: Options = options or {}
	local p = MapKit.part(parent, name, Vector3.new(height, diameter, diameter), CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, o)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- A ramp: `lowEnd` is where it meets the floor, `direction` is uphill (flat).
function MapKit.ramp(parent: Instance, name: string, lowEnd: Vector3, direction: Vector3, length: number, rise: number, width: number, color: Color3, material: Enum.Material?): WedgePart
	local wedge = Instance.new("WedgePart")
	wedge.Name = name
	wedge.Size = Vector3.new(width, rise, length)
	local center = lowEnd + Vector3.new(0, rise / 2, 0) + direction.Unit * (length / 2)
	-- A wedge is tallest at its back (+Z), so its front (-Z) faces downhill.
	wedge.CFrame = CFrame.lookAt(center, center - direction.Unit)
	wedge.Color = color
	wedge.Material = material or Enum.Material.WoodPlanks
	wedge.Anchored = true
	wedge.TopSurface = Enum.SurfaceType.Smooth
	wedge.BottomSurface = Enum.SurfaceType.Smooth
	wedge.Parent = parent
	return wedge
end

-- A stylised pine: trunk plus stacked, shrinking discs of needles.
function MapKit.pine(parent: Instance, base: Vector3, scale: number)
	local trunkHeight = 5 * scale
	MapKit.cylinder(parent, "PineTrunk", base, trunkHeight + 6 * scale, 1.4 * scale, MapKit.vary(Color3.fromRGB(110, 75, 50)), { material = Enum.Material.Wood })
	local green = MapKit.vary(Color3.fromRGB(58, 140, 78), 0.08)
	for tier = 0, 3 do
		local diameter = (9 - tier * 1.9) * scale
		local y = trunkHeight + tier * 2.6 * scale
		MapKit.cylinder(parent, "PineNeedles", base + Vector3.new(0, y, 0), 1.6 * scale, diameter, if tier % 2 == 0 then green else MapKit.vary(green, 0.05), { material = Enum.Material.Grass, collide = tier == 0 })
	end
end

-- A low-poly boulder: a few rotated blocks clumped together.
function MapKit.rock(parent: Instance, base: Vector3, size: number, mossy: boolean?)
	for i = 1, 3 do
		local s = size * (1 - (i - 1) * 0.22)
		local offset = Vector3.new(MapKit.random(-0.3, 0.3) * size, s * 0.35, MapKit.random(-0.3, 0.3) * size)
		local angles = CFrame.Angles(math.rad(MapKit.random(-25, 25)), math.rad(MapKit.random(0, 90)), math.rad(MapKit.random(-25, 25)))
		local color = if mossy and i == 1 then Color3.fromRGB(110, 140, 90) else Color3.fromRGB(150, 150, 155)
		MapKit.part(parent, "Rock", Vector3.new(s, s * 0.8, s), CFrame.new(base + offset) * angles, MapKit.vary(color), { material = Enum.Material.Slate })
	end
end

-- A fallen log lying along `yaw` degrees.
function MapKit.log(parent: Instance, base: Vector3, length: number, yaw: number)
	local p = MapKit.part(parent, "Log", Vector3.new(length, 2.4, 2.4), CFrame.new(base + Vector3.new(0, 1.1, 0)) * CFrame.Angles(0, math.rad(yaw), 0), MapKit.vary(Color3.fromRGB(120, 85, 55)), { material = Enum.Material.Wood })
	p.Shape = Enum.PartType.Cylinder
end

-- A wooden crate (with a lighter lid band so it reads as a crate).
function MapKit.crate(parent: Instance, base: Vector3, size: number, yaw: number)
	local cf = CFrame.new(base + Vector3.new(0, size / 2, 0)) * CFrame.Angles(0, math.rad(yaw), 0)
	MapKit.part(parent, "Crate", Vector3.one * size, cf, MapKit.vary(Color3.fromRGB(190, 135, 80)), { material = Enum.Material.WoodPlanks })
	MapKit.part(parent, "CrateBand", Vector3.new(size + 0.1, size * 0.15, size + 0.1), cf, Color3.fromRGB(120, 80, 50), { material = Enum.Material.Wood, collide = false })
end

-- A giant cartoon mushroom (stem + flattened cap with spots).
function MapKit.mushroom(parent: Instance, base: Vector3, scale: number)
	MapKit.cylinder(parent, "MushroomStem", base, 6 * scale, 2.4 * scale, Color3.fromRGB(245, 235, 215))
	local cap = MapKit.part(parent, "MushroomCap", Vector3.new(9, 4, 9) * scale, CFrame.new(base + Vector3.new(0, 6.5 * scale, 0)), Color3.fromRGB(220, 70, 80))
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = cap
	for i = 0, 4 do
		local angle = math.rad(i * 72)
		local spot = base + Vector3.new(math.cos(angle) * 2.6 * scale, 7.9 * scale, math.sin(angle) * 2.6 * scale)
		MapKit.part(parent, "MushroomSpot", Vector3.one * 1.1 * scale, CFrame.new(spot), Color3.new(1, 1, 1), { shape = Enum.PartType.Ball, collide = false, shadow = false })
	end
end

return MapKit
