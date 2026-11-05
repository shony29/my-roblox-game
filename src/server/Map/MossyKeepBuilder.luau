--!strict
--[[
	MossyKeepBuilder: "Mossy Keep", a forest clearing around a ruined castle.

	Bird's-eye view (Blue spawns west, Red spawns east; mirrored left/right,
	so neither team has an advantage):

	   trees  trees  rocks  trees  trees
	   CAMP   pines  [T]==gap==[T]  pines  CAMP
	   (Blue)  logs  arch  well  arch  logs  (Red)
	   CAMP   pines  [T]==gap==[T]  pines  CAMP
	   trees  mushrooms  ruins  mushrooms  trees

	  * The keep: stone walls with broken gaps, gate arches on the west and
	    east, four corner towers (the two northern ones have ramps up to a
	    sniper perch), a well and broken pillars inside.
	  * Forest between the keep and each camp: pines, mossy boulders, logs.
	  * Each camp: tents, a campfire, crates and four spawn pads.
]]

local Workspace = game:GetService("Workspace")

local MapKit = require(script.Parent.MapKit)

local FLOOR_Y = 1
local HALF = 90 -- playable area is -HALF..HALF on X and Z
local WALL_HEIGHT = 9
local KEEP = 26 -- keep walls sit at +-KEEP

local STONE = Color3.fromRGB(176, 172, 160)
local STONE_DARK = Color3.fromRGB(140, 136, 128)
local WOOD = Color3.fromRGB(150, 105, 65)

local Builder = {}

local function floor(x: number, z: number): Vector3
	return Vector3.new(x, FLOOR_Y, z)
end

-- Runs `place` for a point and for its mirror image across the middle (x -> -x).
local function mirrored(place: (sign: number) -> ())
	place(1)
	place(-1)
end

-- A wall segment from (x1, z1) to (x2, z2), with a darker cap and optional battlements.
local function wall(model: Model, x1: number, z1: number, x2: number, z2: number, height: number, battlements: boolean)
	local from, to = floor(x1, z1), floor(x2, z2)
	local length = (to - from).Magnitude
	local middle = (from + to) / 2
	local cf = CFrame.lookAt(middle, to) * CFrame.Angles(0, math.rad(90), 0)
	MapKit.part(model, "KeepWall", Vector3.new(length, height, 3), cf + Vector3.new(0, height / 2, 0), MapKit.vary(STONE), { material = Enum.Material.Cobblestone })
	MapKit.part(model, "WallCap", Vector3.new(length + 0.4, 0.8, 3.6), cf + Vector3.new(0, height + 0.4, 0), STONE_DARK, { material = Enum.Material.Slate })
	if battlements then
		local count = math.floor(length / 4)
		for i = 0, count - 1 do
			local t = (i + 0.5) / count
			local position = from:Lerp(to, t) + Vector3.new(0, height + 1.8, 0)
			MapKit.part(model, "Merlon", Vector3.new(2, 2, 3), CFrame.lookAt(position, position + (to - from)), STONE, { material = Enum.Material.Cobblestone })
		end
	end
end

local function tower(model: Model, x: number, z: number, height: number)
	local base = floor(x, z)
	MapKit.cylinder(model, "Tower", base, height, 11, MapKit.vary(STONE), { material = Enum.Material.Cobblestone })
	MapKit.cylinder(model, "TowerTop", base + Vector3.new(0, height, 0), 0.6, 12, STONE_DARK, { material = Enum.Material.Slate })
	for i = 0, 7 do
		local angle = math.rad(i * 45)
		local position = base + Vector3.new(math.cos(angle) * 5.3, height + 1.5, math.sin(angle) * 5.3)
		MapKit.part(model, "TowerMerlon", Vector3.new(2, 2.4, 2), CFrame.new(position), STONE, { material = Enum.Material.Cobblestone })
	end
end

local function buildKeep(model: Model)
	-- North and south walls with a broken gap in the middle.
	for _, z in { -KEEP, KEEP } do
		wall(model, -KEEP, z, -5, z, WALL_HEIGHT, true)
		wall(model, 5, z, KEEP, z, WALL_HEIGHT, true)
		MapKit.rock(model, floor(0, z), 3.5, true) -- rubble in the gap
	end
	-- West and east walls with a gate arch you can walk through.
	mirrored(function(sign: number)
		local x = sign * KEEP
		wall(model, x, -KEEP, x, -6, WALL_HEIGHT, true)
		wall(model, x, 6, x, KEEP, WALL_HEIGHT, true)
		MapKit.part(model, "GateLintel", Vector3.new(3.4, 2.2, 12.6), CFrame.new(floor(x, 0) + Vector3.new(0, WALL_HEIGHT - 1.1, 0)), STONE_DARK, { material = Enum.Material.Slate })
		-- Corner towers; the northern ones get a wooden ramp up to the top.
		tower(model, x, -KEEP, 14)
		tower(model, x, KEEP, 11)
		MapKit.ramp(model, "TowerRamp", floor(sign * 8, -KEEP + 6), Vector3.new(sign, 0, 0), 14, 14, 5, WOOD)
	end)
	-- Inside: a well, broken pillars and a few crates.
	MapKit.cylinder(model, "Well", floor(0, 0), 2.6, 7, STONE, { material = Enum.Material.Cobblestone })
	MapKit.cylinder(model, "WellWater", floor(0, 0) + Vector3.new(0, 2.2, 0), 0.3, 5.6, Color3.fromRGB(80, 150, 200), { material = Enum.Material.Glass, collide = false })
	mirrored(function(sign: number)
		MapKit.cylinder(model, "Pillar", floor(sign * 12, -12), 6, 2.6, STONE, { material = Enum.Material.Cobblestone })
		MapKit.cylinder(model, "BrokenPillar", floor(sign * 12, 12), 3, 2.6, STONE, { material = Enum.Material.Cobblestone })
		MapKit.crate(model, floor(sign * 16, 4), 4, 15)
		MapKit.crate(model, floor(sign * 17, 8), 3, 40)
	end)
end

-- Each team's camp: tents, a campfire, crates and spawn pads.
local function buildCamps(model: Model, spawnFolder: Folder): { BasePart }
	local spawnPoints: { BasePart } = {}
	mirrored(function(sign: number)
		local campX = sign * 74
		for _, z in { -24, 24 } do
			local base = floor(campX + sign * 6, z)
			MapKit.part(model, "TentFloor", Vector3.new(8, 0.4, 9), CFrame.new(base + Vector3.new(0, 0.2, 0)), Color3.fromRGB(140, 110, 80), { material = Enum.Material.Fabric })
			-- Two roof halves rising from the sides to meet at a ridge in the middle.
			MapKit.ramp(model, "TentRoof", base + Vector3.new(-4, 0, 0), Vector3.new(1, 0, 0), 4, 6, 9, Color3.fromRGB(230, 220, 190), Enum.Material.Fabric)
			MapKit.ramp(model, "TentRoof", base + Vector3.new(4, 0, 0), Vector3.new(-1, 0, 0), 4, 6, 9, Color3.fromRGB(215, 205, 175), Enum.Material.Fabric)
		end
		-- Campfire: a ring of stones and a warm light.
		local fire = floor(campX, 0)
		for i = 0, 5 do
			local angle = math.rad(i * 60)
			MapKit.part(model, "FireStone", Vector3.new(1.2, 0.8, 1.2), CFrame.new(fire + Vector3.new(math.cos(angle) * 1.8, 0.4, math.sin(angle) * 1.8)), STONE_DARK, { material = Enum.Material.Slate })
		end
		local embers = MapKit.part(model, "Embers", Vector3.new(1.6, 0.6, 1.6), CFrame.new(fire + Vector3.new(0, 0.3, 0)), Color3.fromRGB(255, 140, 60), { material = Enum.Material.Neon, collide = false })
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 170, 90)
		light.Range = 16
		light.Brightness = 1.5
		light.Parent = embers
		MapKit.crate(model, floor(campX - sign * 8, 10), 4, 0)
		MapKit.crate(model, floor(campX - sign * 8, -10), 4, 25)
		-- Four spawn pads facing the keep.
		for _, z in { -36, -12, 12, 36 } do
			local position = floor(sign * 82, z) + Vector3.new(0, 0.2, 0)
			local pad = MapKit.part(spawnFolder, "Spawn", Vector3.new(6, 0.4, 6), CFrame.lookAt(position, Vector3.new(0, position.Y, z)), Color3.fromRGB(255, 240, 150), { material = Enum.Material.Neon, collide = false, shadow = false, transparency = 0.5 })
			table.insert(spawnPoints, pad)
		end
	end)
	return spawnPoints
end

-- Forest cover between the camps and the keep, plus the north/south lanes.
local function buildForest(model: Model)
	local pines = { { 40, -40 }, { 48, -14 }, { 44, 18 }, { 52, 44 }, { 36, 60 }, { 60, -60 }, { 30, -62 }, { 62, 64 } }
	local rocks = { { 38, -8, 4 }, { 54, 28, 5 }, { 46, -50, 6 }, { 20, -48, 5 }, { 20, 50, 4 } }
	local logs = { { 38, 36, 12, 20 }, { 56, -34, 12, 70 } }
	mirrored(function(sign: number)
		for _, p in pines do
			MapKit.pine(model, floor(sign * p[1], p[2]), MapKit.random(0.9, 1.2))
		end
		for _, r in rocks do
			MapKit.rock(model, floor(sign * r[1], r[2]), r[3], true)
		end
		for _, l in logs do
			MapKit.log(model, floor(sign * l[1], l[2]), l[3], sign * l[4])
		end
		MapKit.mushroom(model, floor(sign * 30, 74), 1.1)
		MapKit.mushroom(model, floor(sign * 14, 66), 0.8)
	end)
	-- Ruined wall fragments on the south lane, rocks on the north lane (centred, so symmetric).
	wall(model, -10, 60, 10, 60, 5, false)
	MapKit.rock(model, floor(0, -60), 6, true)
end

-- Dense trees around the edge, invisible walls to keep everyone inside.
local function buildBoundary(model: Model)
	for i = 0, 47 do
		local angle = math.rad(i * 7.5)
		local radius = MapKit.random(104, 128)
		MapKit.pine(model, floor(math.cos(angle) * radius, math.sin(angle) * radius), MapKit.random(1.1, 1.6))
	end
	for _, side in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local alongX = side.X == 0
		local size = if alongX then Vector3.new(HALF * 2 + 8, 60, 2) else Vector3.new(2, 60, HALF * 2 + 8)
		MapKit.part(model, "Boundary", size, CFrame.new(side * (HALF + 3) + Vector3.new(0, 30, 0)), Color3.new(1, 1, 1), { transparency = 1, shadow = false })
	end
end

function Builder.build(): { model: Model, spawnPoints: { BasePart } }
	local old = Workspace:FindFirstChild("MossyKeep")
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "MossyKeep"

	MapKit.part(model, "Ground", Vector3.new(700, 2, 700), CFrame.new(0, FLOOR_Y - 1, 0), Color3.fromRGB(104, 170, 80), { material = Enum.Material.Grass })
	-- A worn dirt path from camp to camp through the gates.
	MapKit.part(model, "Path", Vector3.new(170, 0.1, 9), CFrame.new(0, FLOOR_Y + 0.05, 0), Color3.fromRGB(170, 140, 100), { material = Enum.Material.Ground, collide = false, shadow = false })

	local spawnFolder = Instance.new("Folder")
	spawnFolder.Name = "SpawnPoints"
	spawnFolder.Parent = model

	buildKeep(model)
	local spawnPoints = buildCamps(model, spawnFolder)
	buildForest(model)
	buildBoundary(model)

	model.Parent = Workspace
	return { model = model, spawnPoints = spawnPoints }
end

return Builder
