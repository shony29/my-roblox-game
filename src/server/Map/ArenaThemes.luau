--!strict
--[[
	ArenaThemes: the look of each themed arena (Map/ThemedArenaBuilder puts
	these pieces into the same fair layout). Inspired by cosy toy-like
	dioramas, but built big enough to run, jump and slide around in.

	Each theme has:
	  ground(model, half, y)    the floor
	  rim(model, half, y)       dressing around the edge (outside the play area)
	  centre(model, pos)        the big middle piece (blocks the view through the middle)
	  tall(model, pos, yaw)     tall cover (hides you completely)
	  low(model, pos, yaw)      low cover (shoot over it, crouch behind it)
	  platform(model, pos, dir) high ground with a ramp going down toward `dir`
	  decor(model, pos)         small things you can walk through
	  spawnColor                the glowing spawn pads

	Themes: Space, Kitchen, Fireplace, AntFarm, Reef, Ice, Candy, Bounce.
	Every piece is anchored; decorations don't block movement or bullets.
]]

local MapKit = require(script.Parent.MapKit)

export type Theme = {
	ground: (model: Model, half: number, y: number) -> (),
	rim: (model: Model, half: number, y: number) -> (),
	centre: (model: Model, pos: Vector3) -> (),
	tall: (model: Model, pos: Vector3, yaw: number) -> (),
	low: (model: Model, pos: Vector3, yaw: number) -> (),
	platform: (model: Model, pos: Vector3, dir: Vector3) -> (),
	decor: (model: Model, pos: Vector3) -> (),
	spawnColor: Color3,
	-- Optional: natural ground around the arena (Roblox terrain: real water,
	-- soft hills of sand, snow or rock). Called with the arena's final centre.
	terrain: ((centre: Vector3, half: number, y: number) -> ())?,
}

local rgb = Color3.fromRGB
local M = Enum.Material

local ArenaThemes = {}

-- Building blocks ---------------------------------------------------------------

local function yawAt(pos: Vector3, yaw: number): CFrame
	return CFrame.new(pos) * CFrame.Angles(0, math.rad(yaw), 0)
end

local function box(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?, collide: boolean?): Part
	return MapKit.part(model, name, size, cframe, color, { material = material, collide = collide ~= false })
end

-- A cylinder lying along the CFrame's X axis.
local function cyl(model: Model, name: string, cframe: CFrame, length: number, diameter: number, color: Color3, material: Enum.Material?, collide: boolean?): Part
	local part = MapKit.part(model, name, Vector3.new(length, diameter, diameter), cframe, color, { material = material, collide = collide ~= false })
	part.Shape = Enum.PartType.Cylinder
	return part
end

-- A cylinder standing on `base`.
local function column(model: Model, name: string, base: Vector3, height: number, diameter: number, color: Color3, material: Enum.Material?, collide: boolean?): Part
	return cyl(model, name, CFrame.new(base + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), height, diameter, color, material, collide)
end

local function ball(model: Model, name: string, center: Vector3, diameter: number, color: Color3, material: Enum.Material?, collide: boolean?): Part
	local part = MapKit.part(model, name, Vector3.one * diameter, CFrame.new(center), color, { material = material, collide = collide ~= false, shape = Enum.PartType.Ball })
	return part
end

-- A stretched ball for decoration (round look; walk-through).
local function blob(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material?): Part
	local part = MapKit.part(model, name, size, cframe, color, { material = material, collide = false, shadow = false })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

local function glow(part: BasePart, color: Color3, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = false
	light.Parent = part
end

-- Picks one of two looks for a spot (the same every time for that spot).
local function variant(pos: Vector3, count: number): number
	return (math.floor(math.abs(pos.X) / 7) + math.floor(math.abs(pos.Z) / 7)) % count
end

-- A raised platform with a ramp down toward `dir` (the shared shape; themes colour it).
local function platformShape(model: Model, pos: Vector3, dir: Vector3, height: number, topColor: Color3, sideColor: Color3, material: Enum.Material, rampColor: Color3, rampMaterial: Enum.Material)
	local flat = Vector3.new(dir.X, 0, dir.Z).Unit
	box(model, "Platform", Vector3.new(14, height, 14), CFrame.new(pos + Vector3.new(0, height / 2, 0)), sideColor, material)
	box(model, "PlatformTop", Vector3.new(14.6, 0.6, 14.6), CFrame.new(pos + Vector3.new(0, height + 0.3, 0)), topColor, material)
	local rampLength = height * 2.2
	MapKit.ramp(model, "Ramp", pos + flat * (7 + rampLength), -flat, rampLength, height + 0.6, 8, rampColor, rampMaterial)
end

-- A ring of `count` things around the edge of the arena (outside the play area).
local function aroundEdge(half: number, y: number, count: number, margin: number, place: (position: Vector3, outward: Vector3) -> ())
	for i = 0, count - 1 do
		local t = i / count
		local side = math.floor(t * 4)
		local along = (t * 4 - side) * 2 - 1
		local edge = half + margin
		local position, outward
		if side == 0 then
			position, outward = Vector3.new(along * edge, y, -edge), Vector3.new(0, 0, -1)
		elseif side == 1 then
			position, outward = Vector3.new(edge, y, along * edge), Vector3.new(1, 0, 0)
		elseif side == 2 then
			position, outward = Vector3.new(-along * edge, y, edge), Vector3.new(0, 0, 1)
		else
			position, outward = Vector3.new(-edge, y, -along * edge), Vector3.new(-1, 0, 0)
		end
		place(position, outward)
	end
end

-- Soft terrain hills all around the outside of the arena.
local function hillRing(centre: Vector3, half: number, y: number, material: Enum.Material, count: number, minRadius: number, maxRadius: number)
	local terrain = workspace.Terrain
	aroundEdge(half, y, count, 0, function(position: Vector3, outward: Vector3)
		local radius = MapKit.random(minRadius, maxRadius)
		local spot = centre + position + outward * (radius * 0.55 + 8) + Vector3.new(0, -radius * 0.45, 0)
		terrain:FillBall(spot, radius, material)
	end)
end

local function flatGround(model: Model, half: number, y: number, color: Color3, material: Enum.Material)
	MapKit.part(model, "Ground", Vector3.new(half * 2 + 160, 2, half * 2 + 160), CFrame.new(0, y - 1, 0), color, { material = material })
end

-- Tiles on a checkerboard (big tiles, so there aren't many parts).
local function checker(model: Model, half: number, y: number, color: Color3, material: Enum.Material)
	local count = 8
	local tile = half * 2 / count
	for i = 0, count - 1 do
		for j = 0, count - 1 do
			if (i + j) % 2 == 0 then
				local x = -half + (i + 0.5) * tile
				local z = -half + (j + 0.5) * tile
				MapKit.part(model, "Tile", Vector3.new(tile, 0.1, tile), CFrame.new(x, y + 0.05, z), color, { material = material, collide = false, shadow = false })
			end
		end
	end
end

local themes: { [string]: Theme } = {}

-- ASTRO STATION: a space base on an asteroid -------------------------------------

do
	local METAL = rgb(150, 160, 180)
	local DARK = rgb(70, 76, 92)
	local BLUE = rgb(80, 160, 255)
	local RED = rgb(255, 90, 100)
	themes.Space = {
		spawnColor = BLUE,
		ground = function(model: Model, half: number, y: number)
			flatGround(model, half, y, rgb(120, 122, 130), M.Slate)
			MapKit.part(model, "Deck", Vector3.new(half * 1.2, 0.3, half * 0.5), CFrame.new(0, y + 0.15, 0), METAL, { material = M.DiamondPlate })
			for i = 0, 9 do
				local angle = math.rad(i * 36 + 10)
				local r = half * (0.45 + (i % 3) * 0.15)
				local crater = MapKit.part(model, "Crater", Vector3.new(0.2, 9, 9), CFrame.new(math.cos(angle) * r, y + 0.1, math.sin(angle) * r) * CFrame.Angles(0, 0, math.rad(90)), rgb(95, 96, 104), { material = M.Slate, collide = false, shadow = false })
				crater.Shape = Enum.PartType.Cylinder
			end
			-- Glowing walkways from each side to the middle.
			for _, sign in { -1, 1 } do
				MapKit.part(model, "Walkway", Vector3.new(half * 0.7, 0.2, 1), CFrame.new(sign * half * 0.4, y + 0.3, 3), BLUE, { material = M.Neon, collide = false, shadow = false })
				MapKit.part(model, "Walkway", Vector3.new(half * 0.7, 0.2, 1), CFrame.new(sign * half * 0.4, y + 0.3, -3), RED, { material = M.Neon, collide = false, shadow = false })
			end
		end,
		rim = function(model: Model, half: number, y: number)
			aroundEdge(half, y, 28, 10, function(position: Vector3, outward: Vector3)
				MapKit.rock(model, position, MapKit.random(9, 15), false)
			end)
			-- Solar panels and dishes on the asteroid's edge.
			aroundEdge(half, y, 8, 20, function(position: Vector3, outward: Vector3)
				column(model, "PanelPole", position, 9, 0.8, DARK, M.Metal)
				local panel = box(model, "SolarPanel", Vector3.new(12, 0.4, 6), CFrame.lookAt(position + Vector3.new(0, 9.5, 0), position + Vector3.new(0, 9.5, 0) + outward) * CFrame.Angles(math.rad(35), 0, 0), rgb(40, 70, 160), M.Glass)
				panel.Reflectance = 0.2
			end)
		end,
		centre = function(model: Model, pos: Vector3)
			column(model, "DomeBase", pos, 4, 26, DARK, M.DiamondPlate)
			local dome = ball(model, "GlassDome", pos + Vector3.new(0, 4, 0), 22, rgb(170, 220, 255), M.Glass)
			dome.Transparency = 0.45
			column(model, "DomeRing", pos + Vector3.new(0, 4, 0), 0.6, 26.6, BLUE, M.Neon, false)
			column(model, "Antenna", pos + Vector3.new(0, 15, 0), 6, 0.6, METAL, M.Metal, false)
			glow(ball(model, "Beacon", pos + Vector3.new(0, 21.5, 0), 1.6, RED, M.Neon, false), RED, 20, 1)
		end,
		tall = function(model: Model, pos: Vector3, yaw: number)
			if variant(pos, 2) == 0 then
				column(model, "FuelTank", pos, 12, 7, rgb(235, 238, 245), M.SmoothPlastic)
				column(model, "TankStripe", pos + Vector3.new(0, 8, 0), 1.2, 7.2, RED, M.SmoothPlastic, false)
				column(model, "TankCap", pos + Vector3.new(0, 12, 0), 1, 5, DARK, M.Metal)
			else
				local cf = yawAt(pos + Vector3.new(0, 5, 0), yaw)
				box(model, "Container", Vector3.new(10, 10, 6), cf, rgb(90, 110, 150), M.DiamondPlate)
				box(model, "ContainerLight", Vector3.new(10.2, 0.4, 6.2), cf * CFrame.new(0, 4.4, 0), BLUE, M.Neon, false)
			end
		end,
		low = function(model: Model, pos: Vector3, yaw: number)
			local cf = yawAt(pos + Vector3.new(0, 1.75, 0), yaw)
			box(model, "Barrier", Vector3.new(9, 3.5, 2.5), cf, METAL, M.DiamondPlate)
			box(model, "BarrierLight", Vector3.new(9.2, 0.3, 2.7), cf * CFrame.new(0, 1.2, 0), if variant(pos, 2) == 0 then BLUE else RED, M.Neon, false)
		end,
		platform = function(model: Model, pos: Vector3, dir: Vector3)
			platformShape(model, pos, dir, 7, METAL, DARK, M.DiamondPlate, METAL, M.DiamondPlate)
			column(model, "PadRing", pos + Vector3.new(0, 7.6, 0), 0.2, 9, BLUE, M.Neon, false)
		end,
		decor = function(model: Model, pos: Vector3)
			column(model, "Antenna", pos, 4, 0.3, METAL, M.Metal, false)
			ball(model, "AntennaTip", pos + Vector3.new(0, 4.2, 0), 0.6, RED, M.Neon, false)
		end,
		terrain = function(centre: Vector3, half: number, y: number)
			hillRing(centre, half, y, M.Basalt, 24, 14, 26)
		end,
	}
end

-- CHEF'S KITCHEN: tiny players on a giant kitchen floor --------------------------

do
	local CREAM = rgb(245, 238, 222)
	local WOOD = rgb(200, 150, 100)
	local STEEL = rgb(200, 205, 212)
	local DARK = rgb(60, 60, 66)
	themes.Kitchen = {
		spawnColor = rgb(255, 210, 80),
		ground = function(model: Model, half: number, y: number)
			flatGround(model, half, y, CREAM, M.SmoothPlastic)
			checker(model, half, y, rgb(120, 170, 220), M.SmoothPlastic)
		end,
		rim = function(model: Model, half: number, y: number)
			-- Cupboards with a countertop all around.
			aroundEdge(half, y, 24, 7, function(position: Vector3, outward: Vector3)
				local cf = CFrame.lookAt(position + Vector3.new(0, 7, 0), position + Vector3.new(0, 7, 0) + outward)
				box(model, "Cupboard", Vector3.new(half / 3 + 2, 14, 12), cf, WOOD, M.WoodPlanks)
				box(model, "Counter", Vector3.new(half / 3 + 2.4, 1.2, 13), cf * CFrame.new(0, 7.6, 0), STEEL, M.SmoothPlastic)
				box(model, "Handle", Vector3.new(3, 0.6, 0.6), cf * CFrame.new(0, 3, -6.2), DARK, M.Metal, false)
			end)
			-- Giant jars, a toaster and a fridge on the counters.
			aroundEdge(half, y + 15.2, 6, 7, function(position: Vector3, outward: Vector3)
				column(model, "SpiceJar", position, 7, 4.5, rgb(230, 120, 60), M.Glass)
				column(model, "JarLid", position + Vector3.new(0, 7, 0), 1.2, 4.7, DARK, M.SmoothPlastic)
			end)
			local corner = Vector3.new(half + 10, y, half + 10)
			box(model, "Fridge", Vector3.new(16, 34, 14), CFrame.new(corner + Vector3.new(0, 17, 0)), rgb(235, 238, 240), M.SmoothPlastic)
			box(model, "Toaster", Vector3.new(9, 7, 6), CFrame.new(Vector3.new(-half - 8, y + 18.5, half * 0.3)), STEEL, M.Metal)
		end,
		centre = function(model: Model, pos: Vector3)
			-- The kitchen island with a giant mixing bowl on top.
			box(model, "Island", Vector3.new(22, 7, 18), CFrame.new(pos + Vector3.new(0, 3.5, 0)), WOOD, M.WoodPlanks)
			box(model, "IslandTop", Vector3.new(23, 1, 19), CFrame.new(pos + Vector3.new(0, 7.5, 0)), STEEL, M.SmoothPlastic)
			column(model, "Bowl", pos + Vector3.new(0, 8, 0), 6, 14, rgb(240, 120, 140), M.SmoothPlastic)
			column(model, "Batter", pos + Vector3.new(0, 13.6, 0), 0.6, 12.5, rgb(255, 235, 190), M.SmoothPlastic, false)
			cyl(model, "Whisk", CFrame.new(pos + Vector3.new(3, 16, 0)) * CFrame.Angles(0, 0, math.rad(60)), 9, 0.6, STEEL, M.Metal, false)
		end,
		tall = function(model: Model, pos: Vector3, yaw: number)
			if variant(pos, 2) == 0 then
				-- A knife block.
				local cf = yawAt(pos + Vector3.new(0, 5, 0), yaw) * CFrame.Angles(math.rad(-10), 0, 0)
				box(model, "KnifeBlock", Vector3.new(7, 10, 6), cf, rgb(225, 175, 120), M.Wood)
				for i = -1, 1 do
					box(model, "KnifeHandle", Vector3.new(1.2, 4, 1.6), cf * CFrame.new(i * 2, 6.5, 0), DARK, M.SmoothPlastic, false)
				end
			else
				column(model, "Jar", pos, 11, 7, rgb(180, 230, 120), M.Glass)
				column(model, "JarLid", pos + Vector3.new(0, 11, 0), 1.4, 7.4, rgb(220, 60, 60), M.SmoothPlastic)
			end
		end,
		low = function(model: Model, pos: Vector3, yaw: number)
			if variant(pos, 2) == 0 then
				cyl(model, "RollingPin", yawAt(pos + Vector3.new(0, 1.7, 0), yaw), 10, 3.4, rgb(230, 190, 140), M.Wood)
				for _, side in { -1, 1 } do
					cyl(model, "PinHandle", yawAt(pos + Vector3.new(0, 1.7, 0), yaw) * CFrame.new(side * 6.2, 0, 0), 2.4, 1.4, rgb(200, 150, 100), M.Wood, false)
				end
			else
				box(model, "Butter", Vector3.new(8, 3.4, 4), yawAt(pos + Vector3.new(0, 1.7, 0), yaw), rgb(255, 230, 140), M.SmoothPlastic)
				box(model, "ButterWrap", Vector3.new(8.2, 1, 4.2), yawAt(pos + Vector3.new(0, 0.5, 0), yaw), rgb(250, 250, 250), M.SmoothPlastic, false)
			end
		end,
		platform = function(model: Model, pos: Vector3, dir: Vector3)
			-- A stack of cookbooks, with a cutting board as the ramp.
			platformShape(model, pos, dir, 7, rgb(200, 70, 70), rgb(70, 110, 190), M.SmoothPlastic, rgb(225, 180, 120), M.Wood)
			box(model, "BookPages", Vector3.new(13, 1.4, 13), CFrame.new(pos + Vector3.new(0, 3.5, 0)), rgb(250, 245, 230), M.SmoothPlastic, false)
		end,
		decor = function(model: Model, pos: Vector3)
			blob(model, "Crumb", Vector3.new(1.4, 0.8, 1.2), CFrame.new(pos + Vector3.new(0, 0.4, 0)), rgb(220, 170, 100), M.SmoothPlastic)
			blob(model, "Crumb", Vector3.new(0.9, 0.6, 0.9), CFrame.new(pos + Vector3.new(1.5, 0.3, 0.8)), rgb(210, 160, 90), M.SmoothPlastic)
		end,
	}
end

-- COZY FIREPLACE: a giant living room at night ------------------------------------

do
	local STONE = rgb(170, 172, 180)
	local WOOD = rgb(140, 95, 60)
	local FIRE = rgb(255, 150, 50)
	themes.Fireplace = {
		spawnColor = rgb(255, 180, 90),
		ground = function(model: Model, half: number, y: number)
			flatGround(model, half, y, STONE, M.Slate)
			for i = 0, 15 do
				local x = MapKit.random(-0.85, 0.85) * half
				local z = MapKit.random(-0.85, 0.85) * half
				MapKit.part(model, "Flagstone", Vector3.new(MapKit.random(10, 18), 0.12, MapKit.random(8, 14)), CFrame.new(x, y + 0.06, z) * CFrame.Angles(0, math.rad(MapKit.random(0, 90)), 0), MapKit.vary(rgb(150, 152, 160), 0.08), { material = M.Slate, collide = false, shadow = false })
			end
			-- Knitted rugs.
			for _, spot in { Vector3.new(0.45, 0, 0.45), Vector3.new(-0.45, 0, -0.45) } do
				MapKit.part(model, "Rug", Vector3.new(20, 0.2, 14), CFrame.new(spot * half + Vector3.new(0, y + 0.1, 0)), rgb(170, 100, 70), { material = M.Fabric, collide = false, shadow = false })
			end
		end,
		rim = function(model: Model, half: number, y: number)
			-- Wooden walls with tall night windows.
			aroundEdge(half, y, 16, 4, function(position: Vector3, outward: Vector3)
				local cf = CFrame.lookAt(position + Vector3.new(0, 18, 0), position + Vector3.new(0, 18, 0) + outward)
				box(model, "Wall", Vector3.new(half / 2 + 2, 36, 3), cf, WOOD, M.WoodPlanks)
				local pane = box(model, "Window", Vector3.new(half / 4, 16, 0.4), cf * CFrame.new(0, 4, -1.6), rgb(30, 40, 90), M.Glass, false)
				pane.Transparency = 0.2
			end)
			-- The fireplace on the north wall, glowing.
			local base = Vector3.new(0, y, -half - 6)
			box(model, "Hearth", Vector3.new(34, 24, 10), CFrame.new(base + Vector3.new(0, 12, 0)), rgb(190, 175, 165), M.Brick)
			box(model, "Mantel", Vector3.new(38, 2, 12), CFrame.new(base + Vector3.new(0, 24, 0)), WOOD, M.Wood)
			local fire = box(model, "Fire", Vector3.new(16, 9, 2), CFrame.new(base + Vector3.new(0, 5, 5)), FIRE, M.Neon, false)
			glow(fire, FIRE, 60, 2)
		end,
		centre = function(model: Model, pos: Vector3)
			-- A huge log with a lantern.
			cyl(model, "Log", CFrame.new(pos + Vector3.new(0, 4, 0)) * CFrame.Angles(0, math.rad(90), 0), 26, 8, rgb(150, 100, 60), M.Wood)
			cyl(model, "LogEnd", CFrame.new(pos + Vector3.new(0, 4, 13.1)) * CFrame.Angles(0, math.rad(90), 0), 0.3, 7.4, rgb(220, 180, 120), M.Wood, false)
			cyl(model, "Branch", CFrame.new(pos + Vector3.new(4, 6, 6)) * CFrame.Angles(0, math.rad(30), math.rad(25)), 8, 2, rgb(140, 95, 55), M.Wood, false)
			local lantern = box(model, "Lantern", Vector3.new(2.4, 3.4, 2.4), CFrame.new(pos + Vector3.new(0, 9.7, 0)), rgb(255, 210, 120), M.Neon, false)
			glow(lantern, FIRE, 30, 1.5)
		end,
		tall = function(model: Model, pos: Vector3, yaw: number)
			if variant(pos, 2) == 0 then
				-- A stack of books.
				local colors = { rgb(200, 70, 70), rgb(70, 120, 200), rgb(90, 170, 100), rgb(230, 190, 80) }
				for i = 0, 3 do
					box(model, "Book", Vector3.new(10 - i * 0.6, 2.6, 7 - i * 0.3), yawAt(pos + Vector3.new(0, 1.3 + i * 2.6, 0), yaw + i * 9), colors[i + 1], M.SmoothPlastic)
				end
			else
				-- A giant candle.
				column(model, "Candle", pos, 11, 5, rgb(250, 245, 230), M.SmoothPlastic)
				local flame = blob(model, "Flame", Vector3.new(1.6, 2.8, 1.6), CFrame.new(pos + Vector3.new(0, 12.6, 0)), rgb(255, 190, 80), M.Neon)
				glow(flame, FIRE, 24, 1.2)
			end
		end,
		low = function(model: Model, pos: Vector3, yaw: number)
			if variant(pos, 2) == 0 then
				box(model, "Footstool", Vector3.new(9, 3.4, 5), yawAt(pos + Vector3.new(0, 1.7, 0), yaw), rgb(150, 60, 60), M.Fabric)
			else
				ball(model, "YarnBall", pos + Vector3.new(0, 2, 0), 4, rgb(120, 170, 230), M.Fabric)
				ball(model, "YarnBall", pos + Vector3.new(3.2, 1.6, 1), 3.2, rgb(240, 150, 180), M.Fabric)
			end
		end,
		platform = function(model: Model, pos: Vector3, dir: Vector3)
			-- A low wooden side table with a board leaning up to it.
			platformShape(model, pos, dir, 7, rgb(170, 120, 80), WOOD, M.Wood, rgb(185, 140, 95), M.WoodPlanks)
			local cup = column(model, "Mug", pos + Vector3.new(3, 7.6, 3), 3, 2.6, rgb(240, 240, 245), M.SmoothPlastic, false)
			cup.Name = "Mug"
		end,
		decor = function(model: Model, pos: Vector3)
			column(model, "TeaLight", pos, 0.8, 1.6, rgb(240, 240, 245), M.SmoothPlastic, false)
			blob(model, "TinyFlame", Vector3.new(0.4, 0.8, 0.4), CFrame.new(pos + Vector3.new(0, 1.2, 0)), rgb(255, 200, 90), M.Neon)
		end,
	}
end

-- ANT FARM: tunnels of sand behind glass ------------------------------------------

do
	local SAND = rgb(214, 170, 110)
	local DARK_SAND = rgb(176, 130, 80)
	themes.AntFarm = {
		spawnColor = rgb(255, 120, 90),
		ground = function(model: Model, half: number, y: number)
			flatGround(model, half, y, SAND, M.Sand)
			-- Winding darker trenches (just colour on the floor).
			for i = -3, 3 do
				MapKit.part(model, "Trench", Vector3.new(half * 0.35, 0.1, 6), CFrame.new(i * half * 0.25, y + 0.05, math.sin(i) * half * 0.3) * CFrame.Angles(0, math.rad(i * 25), 0), DARK_SAND, { material = M.Sand, collide = false, shadow = false })
			end
		end,
		rim = function(model: Model, half: number, y: number)
			-- Glass walls in a wooden frame.
			aroundEdge(half, y, 4, 3, function(position: Vector3, outward: Vector3)
				local cf = CFrame.lookAt(position + Vector3.new(0, 20, 0), position + Vector3.new(0, 20, 0) + outward)
				local glass = box(model, "GlassWall", Vector3.new(half * 2 + 8, 40, 1), cf, rgb(200, 230, 255), M.Glass)
				glass.Transparency = 0.7
				box(model, "Frame", Vector3.new(half * 2 + 10, 4, 4), cf * CFrame.new(0, -20, 0), rgb(130, 90, 55), M.Wood)
			end)
			-- Sand banked up behind the glass.
			aroundEdge(half, y, 20, 9, function(position: Vector3, outward: Vector3)
				MapKit.rock(model, position, MapKit.random(10, 16), false)
			end)
		end,
		centre = function(model: Model, pos: Vector3)
			-- A sand hill with a little tunnel arch on top.
			box(model, "SandHill", Vector3.new(24, 6, 20), CFrame.new(pos + Vector3.new(0, 3, 0)), SAND, M.Sand)
			box(model, "SandHillTop", Vector3.new(16, 6, 14), CFrame.new(pos + Vector3.new(0, 9, 0)), DARK_SAND, M.Sand)
			box(model, "Arch", Vector3.new(4, 5, 14), CFrame.new(pos + Vector3.new(-6, 14.5, 0)), SAND, M.Sand)
			box(model, "Arch", Vector3.new(4, 5, 14), CFrame.new(pos + Vector3.new(6, 14.5, 0)), SAND, M.Sand)
			box(model, "ArchTop", Vector3.new(16, 3, 14), CFrame.new(pos + Vector3.new(0, 18.5, 0)), DARK_SAND, M.Sand)
		end,
		tall = function(model: Model, pos: Vector3, yaw: number)
			for i = 0, 2 do
				local s = 8 - i * 1.6
				box(model, "SandPillar", Vector3.new(s, 4.5, s), yawAt(pos + Vector3.new(0, 2.25 + i * 4.3, 0), yaw + i * 20), if i % 2 == 0 then SAND else DARK_SAND, M.Sand)
			end
		end,
		low = function(model: Model, pos: Vector3, yaw: number)
			if variant(pos, 2) == 0 then
				MapKit.rock(model, pos, 4.5, false)
			else
				-- A sugar cube the ants carried in.
				box(model, "SugarCube", Vector3.new(4, 3.5, 4), yawAt(pos + Vector3.new(0, 1.75, 0), yaw + 15), rgb(250, 250, 255), M.Sand)
				box(model, "SugarCube", Vector3.new(4, 3.5, 4), yawAt(pos + Vector3.new(4.5, 1.75, 0.5), yaw - 10), rgb(245, 245, 250), M.Sand)
			end
		end,
		platform = function(model: Model, pos: Vector3, dir: Vector3)
			platformShape(model, pos, dir, 7, DARK_SAND, SAND, M.Sand, rgb(160, 110, 70), M.WoodPlanks)
		end,
		terrain = function(centre: Vector3, half: number, y: number)
			hillRing(centre, half, y, M.Sand, 22, 14, 24)
		end,
		decor = function(model: Model, pos: Vector3)
			-- A little ant: three dark beads in a row.
			for i = 0, 2 do
				blob(model, "Ant", Vector3.new(1.1, 0.9, 1.1), CFrame.new(pos + Vector3.new(i * 1.1, 0.5, 0)), rgb(60, 35, 30), M.SmoothPlastic)
			end
		end,
	}
end

-- CORAL REEF: under the sea ----------------------------------------------------------

do
	local SAND = rgb(230, 215, 170)
	local CORALS = { rgb(255, 120, 110), rgb(255, 170, 70), rgb(190, 110, 230), rgb(90, 200, 220), rgb(255, 120, 190) }
	local KELP = rgb(70, 150, 90)
	themes.Reef = {
		spawnColor = rgb(90, 220, 255),
		ground = function(model: Model, half: number, y: number)
			flatGround(model, half, y, SAND, M.Sand)
			for i = 0, 7 do
				local angle = math.rad(i * 45 + 20)
				MapKit.part(model, "SeaGrass", Vector3.new(14, 0.1, 10), CFrame.new(math.cos(angle) * half * 0.6, y + 0.05, math.sin(angle) * half * 0.6) * CFrame.Angles(0, angle, 0), rgb(120, 190, 140), { material = M.Grass, collide = false, shadow = false })
			end
		end,
		rim = function(model: Model, half: number, y: number)
			aroundEdge(half, y, 26, 9, function(position: Vector3, outward: Vector3)
				MapKit.rock(model, position, MapKit.random(10, 16), true)
			end)
			-- A kelp forest around the reef.
			aroundEdge(half, y, 32, 2, function(position: Vector3, outward: Vector3)
				local height = MapKit.random(14, 26)
				local kelp = box(model, "Kelp", Vector3.new(1.4, height, 0.6), CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, math.rad(MapKit.random(0, 180)), math.rad(MapKit.random(-8, 8))), KELP, M.SmoothPlastic, false)
				kelp.Name = "Kelp"
			end)
		end,
		centre = function(model: Model, pos: Vector3)
			-- A coral reef ring: brain coral in the middle, branching corals around.
			ball(model, "BrainCoral", pos + Vector3.new(0, 4, 0), 14, rgb(255, 150, 160), M.Slate)
			for i = 0, 5 do
				local angle = math.rad(i * 60)
				local base = pos + Vector3.new(math.cos(angle) * 10, 0, math.sin(angle) * 10)
				local color = CORALS[(i % #CORALS) + 1]
				column(model, "Coral", base, 9 + (i % 3) * 2, 2.4, color, M.SmoothPlastic)
				cyl(model, "CoralBranch", CFrame.new(base + Vector3.new(0, 7, 0)) * CFrame.Angles(0, math.rad(i * 60), math.rad(45)), 5, 1.4, color, M.SmoothPlastic, false)
			end
			-- Bubbles rising.
			for i = 0, 4 do
				local bubble = ball(model, "Bubble", pos + Vector3.new(MapKit.random(-3, 3), 14 + i * 3, MapKit.random(-3, 3)), 1 + i * 0.3, rgb(220, 245, 255), M.Glass, false)
				bubble.Transparency = 0.5
			end
		end,
		tall = function(model: Model, pos: Vector3, yaw: number)
			if variant(pos, 2) == 0 then
				for i = 0, 3 do
					column(model, "CoralTower", pos + Vector3.new(0, i * 3, 0), 3, 7 - i, CORALS[(i % #CORALS) + 1], M.SmoothPlastic)
				end
			else
				-- An old diving helmet.
				ball(model, "Helmet", pos + Vector3.new(0, 5, 0), 10, rgb(205, 150, 70), M.Metal)
				local window = column(model, "HelmetWindow", pos + Vector3.new(0, 5, 0), 0.4, 4.6, rgb(120, 200, 230), M.Glass, false)
				window.CFrame = yawAt(pos + Vector3.new(0, 5.5, 0), yaw) * CFrame.new(0, 0, -4.9) * CFrame.Angles(0, math.rad(90), 0)
			end
		end,
		low = function(model: Model, pos: Vector3, yaw: number)
			if variant(pos, 2) == 0 then
				-- A treasure chest.
				local cf = yawAt(pos + Vector3.new(0, 1.7, 0), yaw)
				box(model, "Chest", Vector3.new(7, 3.4, 4), cf, rgb(140, 90, 50), M.WoodPlanks)
				box(model, "ChestBand", Vector3.new(7.2, 0.6, 4.2), cf * CFrame.new(0, 1, 0), rgb(240, 200, 80), M.Metal, false)
			else
				MapKit.rock(model, pos, 4.5, true)
				ball(model, "Starfish", pos + Vector3.new(1.5, 3.8, 0), 1.4, rgb(255, 140, 90), M.SmoothPlastic, false)
			end
		end,
		platform = function(model: Model, pos: Vector3, dir: Vector3)
			-- A sunken ship's deck.
			platformShape(model, pos, dir, 7, rgb(150, 110, 70), rgb(110, 80, 55), M.WoodPlanks, rgb(140, 100, 65), M.WoodPlanks)
			column(model, "Mast", pos + Vector3.new(-4, 7.6, -4), 10, 1, rgb(120, 85, 55), M.Wood, false)
		end,
		terrain = function(centre: Vector3, half: number, y: number)
			hillRing(centre, half, y, M.Sand, 20, 14, 22)
			hillRing(centre, half + 14, y, M.Rock, 14, 16, 28)
		end,
		decor = function(model: Model, pos: Vector3)
			column(model, "SmallCoral", pos, 2.4, 1, CORALS[variant(pos, #CORALS) + 1], M.SmoothPlastic, false)
			local bubble = ball(model, "Bubble", pos + Vector3.new(0, 4, 0), 0.8, rgb(220, 245, 255), M.Glass, false)
			bubble.Transparency = 0.5
		end,
	}
end

-- ICY WONDERLAND: an ice castle in the snow -------------------------------------------

do
	local SNOW = rgb(240, 245, 255)
	local ICE = rgb(150, 210, 255)
	themes.Ice = {
		spawnColor = rgb(120, 220, 255),
		ground = function(model: Model, half: number, y: number)
			flatGround(model, half, y, SNOW, M.Snow)
			-- Frozen ponds.
			for _, spot in { Vector3.new(0.5, 0, 0.3), Vector3.new(-0.5, 0, -0.3) } do
				local pond = MapKit.part(model, "FrozenPond", Vector3.new(0.3, 22, 22), CFrame.new(spot * half + Vector3.new(0, y + 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), ICE, { material = M.Ice, collide = false, shadow = false })
				pond.Shape = Enum.PartType.Cylinder
			end
		end,
		rim = function(model: Model, half: number, y: number)
			aroundEdge(half, y, 28, 10, function(position: Vector3, outward: Vector3)
				local rock = MapKit.part(model, "SnowCliff", Vector3.new(16, MapKit.random(12, 24), 14), CFrame.new(position + Vector3.new(0, 6, 0)) * CFrame.Angles(0, math.rad(MapKit.random(0, 90)), 0), rgb(225, 232, 245), { material = M.Snow })
				rock.Name = "SnowCliff"
			end)
			aroundEdge(half, y, 18, 0, function(position: Vector3, outward: Vector3)
				MapKit.pine(model, position, MapKit.random(1, 1.4))
				ball(model, "SnowCap", position + Vector3.new(0, 15, 0), 5, SNOW, M.Snow, false)
			end)
		end,
		centre = function(model: Model, pos: Vector3)
			-- A little ice castle: a keep with four towers.
			local castle = box(model, "IceKeep", Vector3.new(18, 12, 16), CFrame.new(pos + Vector3.new(0, 6, 0)), ICE, M.Ice)
			castle.Transparency = 0.15
			box(model, "IceKeepTop", Vector3.new(12, 6, 10), CFrame.new(pos + Vector3.new(0, 15, 0)), rgb(190, 230, 255), M.Ice)
			for _, x in { -9, 9 } do
				for _, z in { -8, 8 } do
					column(model, "IceTower", pos + Vector3.new(x, 0, z), 16, 5, rgb(170, 220, 255), M.Ice)
					local spire = MapKit.part(model, "Spire", Vector3.new(3, 5, 3), CFrame.new(pos + Vector3.new(x, 18.5, z)) * CFrame.Angles(0, math.rad(45), 0), rgb(120, 190, 255), { material = M.Neon, collide = false })
					spire.Name = "Spire"
				end
			end
		end,
		tall = function(model: Model, pos: Vector3, yaw: number)
			if variant(pos, 2) == 0 then
				local pillar = box(model, "IcePillar", Vector3.new(6, 12, 6), yawAt(pos + Vector3.new(0, 6, 0), yaw + 20), ICE, M.Ice)
				pillar.Transparency = 0.1
				box(model, "IceShard", Vector3.new(3, 6, 3), yawAt(pos + Vector3.new(2, 3, 2), yaw + 50) * CFrame.Angles(0, 0, math.rad(20)), rgb(190, 235, 255), M.Ice)
			else
				MapKit.pine(model, pos, 1)
				ball(model, "SnowCap", pos + Vector3.new(0, 13, 0), 5, SNOW, M.Snow, false)
			end
		end,
		low = function(model: Model, pos: Vector3, yaw: number)
			if variant(pos, 2) == 0 then
				box(model, "SnowWall", Vector3.new(9, 3.5, 3), yawAt(pos + Vector3.new(0, 1.75, 0), yaw), SNOW, M.Snow)
			else
				-- A snowman.
				ball(model, "SnowmanBottom", pos + Vector3.new(0, 2, 0), 4.4, SNOW, M.Snow)
				ball(model, "SnowmanTop", pos + Vector3.new(0, 5, 0), 3, SNOW, M.Snow)
				box(model, "Carrot", Vector3.new(0.5, 0.5, 1.6), yawAt(pos + Vector3.new(0, 5.1, 0), yaw) * CFrame.new(0, 0, -1.9), rgb(255, 140, 40), M.SmoothPlastic, false)
			end
		end,
		platform = function(model: Model, pos: Vector3, dir: Vector3)
			-- An ice block with a slide down to the middle.
			platformShape(model, pos, dir, 7, rgb(230, 245, 255), ICE, M.Ice, rgb(180, 225, 255), M.Ice)
		end,
		terrain = function(centre: Vector3, half: number, y: number)
			hillRing(centre, half, y, M.Snow, 24, 14, 26)
			hillRing(centre, half + 16, y, M.Glacier, 12, 12, 20)
		end,
		decor = function(model: Model, pos: Vector3)
			ball(model, "Snowball", pos + Vector3.new(0, 0.8, 0), 1.6, SNOW, M.Snow, false)
			ball(model, "Snowball", pos + Vector3.new(1.3, 0.6, 0.6), 1.2, SNOW, M.Snow, false)
		end,
	}
end

-- CANDY LAND: gingerbread, gummies and lollipops -----------------------------------------

do
	local PINK = rgb(255, 200, 225)
	local CHOCOLATE = rgb(110, 65, 40)
	local GINGER = rgb(190, 120, 65)
	local GUMMIES = { rgb(255, 80, 90), rgb(255, 210, 60), rgb(90, 200, 110), rgb(90, 160, 255), rgb(200, 110, 255) }
	themes.Candy = {
		spawnColor = rgb(255, 120, 200),
		ground = function(model: Model, half: number, y: number)
			flatGround(model, half, y, PINK, M.SmoothPlastic)
			-- A minty path from side to side.
			MapKit.part(model, "MintPath", Vector3.new(half * 2, 0.1, 10), CFrame.new(0, y + 0.05, 0), rgb(170, 240, 210), { material = M.SmoothPlastic, collide = false, shadow = false })
			-- Jelly bean puddles.
			for i = 0, 20 do
				local x = MapKit.random(-0.9, 0.9) * half
				local z = MapKit.random(-0.9, 0.9) * half
				blob(model, "JellyBean", Vector3.new(1.6, 0.8, 1), CFrame.new(x, y + 0.4, z) * CFrame.Angles(0, math.rad(MapKit.random(0, 180)), 0), GUMMIES[(i % #GUMMIES) + 1], M.SmoothPlastic)
			end
		end,
		rim = function(model: Model, half: number, y: number)
			-- Wafer and cookie cliffs.
			aroundEdge(half, y, 24, 9, function(position: Vector3, outward: Vector3)
				local height = MapKit.random(10, 20)
				box(model, "Wafer", Vector3.new(14, height, 12), CFrame.new(position + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, math.rad(MapKit.random(-15, 15)), 0), if MapKit.random(0, 1) > 0.5 then rgb(235, 195, 140) else rgb(250, 235, 230), M.SmoothPlastic)
			end)
			-- Lollipop trees.
			aroundEdge(half, y, 14, 1, function(position: Vector3, outward: Vector3)
				column(model, "LollipopStick", position, 12, 0.8, rgb(250, 250, 250), M.SmoothPlastic, false)
				local candy = cyl(model, "Lollipop", CFrame.lookAt(position + Vector3.new(0, 14, 0), position + Vector3.new(0, 14, 0) + outward) * CFrame.Angles(0, math.rad(90), 0), 1, 7, GUMMIES[math.floor(MapKit.random(1, #GUMMIES + 0.99))], M.SmoothPlastic, false)
				candy.Name = "Lollipop"
			end)
		end,
		centre = function(model: Model, pos: Vector3)
			-- A gingerbread house with icing and gumdrops.
			box(model, "Gingerbread", Vector3.new(20, 11, 16), CFrame.new(pos + Vector3.new(0, 5.5, 0)), GINGER, M.SmoothPlastic)
			box(model, "Icing", Vector3.new(20.6, 0.8, 16.6), CFrame.new(pos + Vector3.new(0, 11.2, 0)), rgb(255, 255, 255), M.SmoothPlastic)
			MapKit.ramp(model, "Roof", pos + Vector3.new(0, 11.6, -8.5), Vector3.new(0, 0, 1), 8.5, 6, 21, rgb(200, 90, 110), M.SmoothPlastic)
			MapKit.ramp(model, "Roof", pos + Vector3.new(0, 11.6, 8.5), Vector3.new(0, 0, -1), 8.5, 6, 21, rgb(220, 100, 120), M.SmoothPlastic)
			for i = 0, 4 do
				ball(model, "Gumdrop", pos + Vector3.new(-8 + i * 4, 1.4, -8.6), 2.6, GUMMIES[i + 1], M.SmoothPlastic, false)
			end
			box(model, "Door", Vector3.new(4, 6, 0.4), CFrame.new(pos + Vector3.new(0, 3, -8.2)), CHOCOLATE, M.SmoothPlastic, false)
		end,
		tall = function(model: Model, pos: Vector3, yaw: number)
			if variant(pos, 2) == 0 then
				-- A gummy bear.
				local color = GUMMIES[variant(pos, #GUMMIES) + 1]
				local body = ball(model, "GummyBody", pos + Vector3.new(0, 4, 0), 8, color, M.Glass)
				body.Transparency = 0.15
				local head = ball(model, "GummyHead", pos + Vector3.new(0, 10, 0), 6, color, M.Glass)
				head.Transparency = 0.15
				for _, side in { -1, 1 } do
					ball(model, "GummyEar", pos + Vector3.new(side * 2.2, 13, 0), 2, color, M.Glass, false)
				end
			else
				-- A candy cane standing up.
				column(model, "CandyCane", pos, 12, 2.4, rgb(250, 250, 250), M.SmoothPlastic)
				for i = 0, 3 do
					column(model, "CaneStripe", pos + Vector3.new(0, 1.5 + i * 3, 0), 1, 2.5, rgb(230, 40, 60), M.SmoothPlastic, false)
				end
				cyl(model, "CaneHook", CFrame.new(pos + Vector3.new(1.6, 12.5, 0)) * CFrame.Angles(0, math.rad(yaw), math.rad(0)), 4, 2.4, rgb(230, 40, 60), M.SmoothPlastic, false)
			end
		end,
		low = function(model: Model, pos: Vector3, yaw: number)
			if variant(pos, 2) == 0 then
				local cf = yawAt(pos + Vector3.new(0, 1.7, 0), yaw)
				box(model, "ChocolateBar", Vector3.new(9, 3.4, 4), cf, CHOCOLATE, M.SmoothPlastic)
				for i = -1, 1 do
					box(model, "ChocolateSquare", Vector3.new(2.6, 0.4, 3.4), cf * CFrame.new(i * 2.9, 1.8, 0), rgb(130, 80, 50), M.SmoothPlastic, false)
				end
			else
				ball(model, "Gumdrop", pos + Vector3.new(0, 1.6, 0), 3.6, GUMMIES[variant(pos, #GUMMIES) + 1], M.SmoothPlastic)
				ball(model, "Gumdrop", pos + Vector3.new(3, 1.4, 1), 3, GUMMIES[(variant(pos, #GUMMIES) + 2) % #GUMMIES + 1], M.SmoothPlastic)
			end
		end,
		platform = function(model: Model, pos: Vector3, dir: Vector3)
			-- A layer cake with a wafer ramp.
			platformShape(model, pos, dir, 7, rgb(255, 250, 245), rgb(255, 170, 200), M.SmoothPlastic, rgb(235, 195, 140), M.SmoothPlastic)
			box(model, "CakeLayer", Vector3.new(14.2, 1.2, 14.2), CFrame.new(pos + Vector3.new(0, 3.5, 0)), rgb(255, 245, 230), M.SmoothPlastic, false)
			ball(model, "Cherry", pos + Vector3.new(0, 8.6, 0), 2, rgb(220, 30, 50), M.SmoothPlastic, false)
		end,
		decor = function(model: Model, pos: Vector3)
			for i = 0, 3 do
				local sprinkle = box(model, "Sprinkle", Vector3.new(0.3, 0.3, 1.2), CFrame.new(pos + Vector3.new(i * 0.8, 0.2, (i % 2) * 0.6)) * CFrame.Angles(0, math.rad(i * 47), 0), GUMMIES[(i % #GUMMIES) + 1], M.SmoothPlastic, false)
				sprinkle.Name = "Sprinkle"
			end
		end,
	}
end

-- BOUNCE HOUSE: a bright inflatable playground by the water -------------------------------

do
	local COLORS = { rgb(70, 200, 90), rgb(255, 210, 50), rgb(240, 70, 70), rgb(70, 140, 255) }
	themes.Bounce = {
		spawnColor = rgb(255, 230, 90),
		ground = function(model: Model, half: number, y: number)
			-- (The water around it is real terrain water, see `terrain` below.)
			MapKit.part(model, "InflatableFloor", Vector3.new(half * 2 + 6, 2, half * 2 + 6), CFrame.new(0, y - 1, 0), COLORS[1], { material = M.SmoothPlastic })
			-- Big coloured stripes on the floor.
			for i = -3, 3 do
				MapKit.part(model, "FloorStripe", Vector3.new(half / 4, 0.1, half * 2 + 6), CFrame.new(i * half / 3.5, y + 0.05, 0), COLORS[(i % 2) + 2], { material = M.SmoothPlastic, collide = false, shadow = false })
			end
		end,
		rim = function(model: Model, half: number, y: number)
			-- Puffy tube walls all round, alternating colours.
			aroundEdge(half, y, 16, 3, function(position: Vector3, outward: Vector3)
				local along = Vector3.new(outward.Z, 0, -outward.X)
				local tube = cyl(model, "PuffyWall", CFrame.lookAt(position + Vector3.new(0, 4, 0), position + Vector3.new(0, 4, 0) + along), half / 2 + 2, 8, COLORS[math.floor(MapKit.random(1, #COLORS + 0.99))], M.SmoothPlastic)
				tube.CFrame = CFrame.lookAt(position + Vector3.new(0, 4, 0), position + Vector3.new(0, 4, 0) + along) * CFrame.Angles(0, math.rad(90), 0)
			end)
			-- Turrets with flags in the corners.
			for _, x in { -1, 1 } do
				for _, z in { -1, 1 } do
					local base = Vector3.new(x * (half + 6), y, z * (half + 6))
					column(model, "Turret", base, 16, 9, COLORS[4], M.SmoothPlastic)
					column(model, "TurretTop", base + Vector3.new(0, 16, 0), 2, 11, COLORS[3], M.SmoothPlastic)
					column(model, "FlagPole", base + Vector3.new(0, 18, 0), 6, 0.4, rgb(250, 250, 250), M.SmoothPlastic, false)
					box(model, "Flag", Vector3.new(3, 2, 0.2), CFrame.new(base + Vector3.new(1.5, 23, 0)), COLORS[3], M.SmoothPlastic, false)
				end
			end
			-- Palm trees on the shore.
			aroundEdge(half, y, 10, 18, function(position: Vector3, outward: Vector3)
				for i = 0, 3 do
					ball(model, "PalmTrunk", position + Vector3.new(i * 0.4, 1.5 + i * 3, 0), 2.6, rgb(170, 120, 70), M.Wood, false)
				end
				for i = 0, 4 do
					local angle = math.rad(i * 72)
					blob(model, "PalmLeaf", Vector3.new(2, 0.6, 9), CFrame.new(position + Vector3.new(1.6 + math.cos(angle) * 3.5, 13, math.sin(angle) * 3.5)) * CFrame.Angles(0, -angle + math.rad(90), math.rad(-20)), rgb(60, 180, 80), M.SmoothPlastic)
				end
			end)
		end,
		centre = function(model: Model, pos: Vector3)
			-- A bouncy castle: a puffy keep with turrets.
			box(model, "BouncyKeep", Vector3.new(20, 10, 16), CFrame.new(pos + Vector3.new(0, 5, 0)), COLORS[2], M.SmoothPlastic)
			for _, x in { -10, 10 } do
				for _, z in { -8, 8 } do
					column(model, "BouncyTower", pos + Vector3.new(x, 0, z), 14, 5, COLORS[3], M.SmoothPlastic)
					ball(model, "BouncyTop", pos + Vector3.new(x, 14.5, z), 5, COLORS[4], M.SmoothPlastic)
				end
			end
			cyl(model, "Arch", CFrame.new(pos + Vector3.new(0, 10, 0)), 20, 6, COLORS[1], M.SmoothPlastic)
		end,
		tall = function(model: Model, pos: Vector3, yaw: number)
			local color = COLORS[variant(pos, #COLORS) + 1]
			column(model, "PuffyPillar", pos, 11, 6, color, M.SmoothPlastic)
			ball(model, "PuffyTop", pos + Vector3.new(0, 11, 0), 6.4, COLORS[(variant(pos, #COLORS) + 1) % #COLORS + 1], M.SmoothPlastic)
		end,
		low = function(model: Model, pos: Vector3, yaw: number)
			cyl(model, "PuffyTube", yawAt(pos + Vector3.new(0, 1.8, 0), yaw), 9, 3.6, COLORS[variant(pos, #COLORS) + 1], M.SmoothPlastic)
			for _, side in { -1, 1 } do
				ball(model, "TubeEnd", (yawAt(pos + Vector3.new(0, 1.8, 0), yaw) * CFrame.new(side * 4.5, 0, 0)).Position, 3.6, COLORS[variant(pos, #COLORS) + 1], M.SmoothPlastic)
			end
		end,
		platform = function(model: Model, pos: Vector3, dir: Vector3)
			-- A puffy platform with a slide.
			platformShape(model, pos, dir, 7, COLORS[2], COLORS[4], M.SmoothPlastic, COLORS[3], M.SmoothPlastic)
			for _, x in { -7, 7 } do
				for _, z in { -7, 7 } do
					ball(model, "PuffyCorner", pos + Vector3.new(x, 7.6, z), 2.4, COLORS[3], M.SmoothPlastic, false)
				end
			end
		end,
		terrain = function(centre: Vector3, half: number, y: number)
			local terrain = workspace.Terrain
			terrain:FillBlock(CFrame.new(centre + Vector3.new(0, y - 4, 0)), Vector3.new(half * 2 + 240, 6, half * 2 + 240), M.Water)
			-- Little sandy islands under the palm trees.
			aroundEdge(half, y, 10, 18, function(position: Vector3, outward: Vector3)
				terrain:FillBall(centre + position + Vector3.new(0, y - 7, 0), 9, M.Sand)
			end)
		end,
		decor = function(model: Model, pos: Vector3)
			local beachBall = ball(model, "BeachBall", pos + Vector3.new(0, 1.2, 0), 2.4, rgb(255, 255, 255), M.SmoothPlastic, false)
			beachBall.Name = "BeachBall"
			blob(model, "BallStripe", Vector3.new(0.6, 2.5, 2.5), CFrame.new(pos + Vector3.new(0, 1.2, 0)), COLORS[3], M.SmoothPlastic)
		end,
	}
end

-- The theme called `name` (the kitchen if there's no such theme).
function ArenaThemes.get(name: string): Theme
	return themes[name] or themes.Kitchen
end

return ArenaThemes
