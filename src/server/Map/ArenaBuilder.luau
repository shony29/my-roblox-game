--!strict
-- ArenaBuilder: builds a small, colorful low-poly arena out of plain blocks.
--
-- Bird's-eye layout (about 180 x 180 studs):
--
--   S . . . . . S . . . . . S        S  = spawn pad (8 total)
--   . [T]===     ledge    ===[T] .   T  = corner tower with a ramp
--   .    \                  /   .    \  = floating stepping stones
--   .   c   \     ^      /   c  .    c  = cover (crates and low walls)
--   S ledge < [ CENTER ] > ledge S   ^< = ramps up to the center platform
--   .   c   /     v      \   c  .
--   .    /                  \   .
--   . [T]===     ledge    ===[T] .
--   S . . . . . S . . . . . S
--
-- Everything is mirrored into all four quarters, so no side has an advantage.

local Workspace = game:GetService("Workspace")

export type Arena = {
	model: Model,
	spawnPoints: { BasePart },
}

local ArenaBuilder = {}

-- Top of the arena floor. Raised one stud so it never flickers against
-- a default Baseplate if the place still has one.
local FLOOR_Y = 1

local Colors = {
	floor = Color3.fromRGB(134, 220, 132), -- soft green
	wall = Color3.fromRGB(255, 205, 105), -- warm yellow
	center = Color3.fromRGB(110, 180, 255), -- sky blue
	ramp = Color3.fromRGB(255, 128, 118), -- coral
	tower = Color3.fromRGB(178, 142, 255), -- lavender
	ledge = Color3.fromRGB(90, 214, 200), -- teal
	stone = Color3.fromRGB(255, 160, 210), -- pink
	crate = Color3.fromRGB(255, 166, 77), -- orange
	cover = Color3.fromRGB(250, 250, 245), -- off-white
	spawn = Color3.fromRGB(255, 240, 120), -- bright yellow
}

-- The four quarters of the map, used for mirroring.
local QUARTERS: { Vector2 } = {
	Vector2.new(1, 1),
	Vector2.new(1, -1),
	Vector2.new(-1, 1),
	Vector2.new(-1, -1),
}

-- The four straight directions (north, south, east, west).
local SIDES: { Vector3 } = {
	Vector3.new(0, 0, 1),
	Vector3.new(0, 0, -1),
	Vector3.new(1, 0, 0),
	Vector3.new(-1, 0, 0),
}

local function style(part: BasePart, name: string, color: Color3, parent: Instance)
	part.Name = name
	part.Anchored = true
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
end

-- Makes a box. (x, z) is its center on the map, and `bottom` is how high
-- its underside sits above the floor. `yaw` turns it (in degrees).
local function block(
	parent: Instance,
	name: string,
	size: Vector3,
	x: number,
	bottom: number,
	z: number,
	color: Color3,
	yaw: number?
): Part
	local part = Instance.new("Part")
	part.Size = size
	local center = Vector3.new(x, FLOOR_Y + bottom + size.Y / 2, z)
	part.CFrame = CFrame.new(center) * CFrame.Angles(0, math.rad(yaw or 0), 0)
	style(part, name, color, parent)
	return part
end

-- Makes a ramp. `lowEnd` is where the ramp touches the ground (x, z), and
-- `direction` is the flat direction you walk to go up it.
local function ramp(
	parent: Instance,
	name: string,
	lowEnd: Vector3,
	direction: Vector3,
	length: number,
	rise: number,
	width: number,
	color: Color3
): WedgePart
	local wedge = Instance.new("WedgePart")
	wedge.Size = Vector3.new(width, rise, length)
	local center = Vector3.new(lowEnd.X, FLOOR_Y + rise / 2, lowEnd.Z) + direction * (length / 2)
	-- A wedge is tallest at its back (+Z), so we aim its front (-Z) downhill.
	wedge.CFrame = CFrame.lookAt(center, center - direction)
	style(wedge, name, color, parent)
	return wedge
end

local function buildFloorAndWalls(model: Model)
	block(model, "Floor", Vector3.new(180, 2, 180), 0, -2, 0, Colors.floor)

	local wallHeight = 20
	for _, side in SIDES do
		local alongX = side.X == 0
		local size = if alongX then Vector3.new(188, wallHeight, 4) else Vector3.new(4, wallHeight, 188)
		block(model, "Wall", size, side.X * 92, -2, side.Z * 92, Colors.wall)
	end
end

-- The big platform in the middle, with a ramp on each side and cover on top.
local function buildCenter(model: Model)
	local height = 8
	block(model, "CenterPlatform", Vector3.new(30, height, 30), 0, 0, 0, Colors.center)
	block(model, "CenterCover", Vector3.new(8, 3, 8), 0, height, 0, Colors.cover)

	for _, side in SIDES do
		-- Starts 39 studs out and climbs 24 studs inward to the platform's edge.
		ramp(model, "CenterRamp", -side * 39, side, 24, height, 10, Colors.ramp)
	end
end

-- A tall tower in each corner, reached by a ramp or by the stepping stones.
local function buildTowers(model: Model)
	local height = 14
	for _, q in QUARTERS do
		local x, z = q.X * 62, q.Y * 62
		block(model, "Tower", Vector3.new(16, height, 16), x, 0, z, Colors.tower)

		-- Low walls along the two outer edges of the tower top, to duck behind.
		block(model, "TowerCover", Vector3.new(2, 3, 16), x + q.X * 7, height, z, Colors.cover)
		block(model, "TowerCover", Vector3.new(16, 3, 2), x, height, z + q.Y * 7, Colors.cover)

		-- Ramp running along the tower's inner side, climbing toward the tower.
		local climb = Vector3.new(0, 0, q.Y)
		ramp(model, "TowerRamp", Vector3.new(x, 0, q.Y * 26), climb, 28, height, 8, Colors.ramp)
	end
end

-- Floating stones on each diagonal: hop from the center platform up to a tower.
local function buildSteppingStones(model: Model)
	local stones = {
		{ distance = 24, bottom = 8.5 },
		{ distance = 34, bottom = 10 },
		{ distance = 45, bottom = 11.5 },
	}
	for _, q in QUARTERS do
		for _, stone in stones do
			block(
				model,
				"SteppingStone",
				Vector3.new(6, 1, 6),
				q.X * stone.distance,
				stone.bottom,
				q.Y * stone.distance,
				Colors.stone
			)
		end
	end
end

-- A low ledge in the middle of each side, with a step to jump up from.
local function buildLedges(model: Model)
	for _, side in SIDES do
		local alongX = side.Z ~= 0
		local size = if alongX then Vector3.new(24, 5, 10) else Vector3.new(10, 5, 24)
		block(model, "Ledge", size, side.X * 62, 0, side.Z * 62, Colors.ledge)
		block(model, "LedgeStep", Vector3.new(6, 2.5, 6), side.X * 54, 0, side.Z * 54, Colors.ledge)
		-- A short wall on the ledge, facing the center.
		local wallSize = if alongX then Vector3.new(10, 3, 1) else Vector3.new(1, 3, 10)
		block(model, "LedgeCover", wallSize, side.X * 58, 5, side.Z * 58, Colors.cover)
	end
end

-- A ring of crates and low walls around the middle, for ground fights.
local function buildCover(model: Model)
	local radius = 44
	for i = 0, 7 do
		local angle = math.rad(22.5 + i * 45)
		local x, z = math.cos(angle) * radius, math.sin(angle) * radius
		if i % 2 == 0 then
			block(model, "Crate", Vector3.new(5, 5, 5), x, 0, z, Colors.crate, 15)
		else
			-- Turned so the wall faces the center of the map.
			local yaw = -math.deg(angle) + 90
			block(model, "LowWall", Vector3.new(10, 4, 2), x, 0, z, Colors.cover, yaw)
		end
	end

	-- Small crates near the outer edge, between the spawns.
	for _, q in QUARTERS do
		block(model, "SmallCrate", Vector3.new(4, 4, 4), q.X * 80, 0, q.Y * 40, Colors.crate)
		block(model, "SmallCrate", Vector3.new(4, 4, 4), q.X * 40, 0, q.Y * 80, Colors.crate)
	end
end

-- Eight spawn pads spread around the outside, each facing the center.
local function buildSpawns(model: Model): { BasePart }
	local folder = Instance.new("Folder")
	folder.Name = "SpawnPoints"
	folder.Parent = model

	local spots: { Vector2 } = {
		Vector2.new(80, 80),
		Vector2.new(-80, 80),
		Vector2.new(80, -80),
		Vector2.new(-80, -80),
		Vector2.new(0, 80),
		Vector2.new(0, -80),
		Vector2.new(80, 0),
		Vector2.new(-80, 0),
	}

	local spawnPoints: { BasePart } = {}
	for index, spot in spots do
		local pad = Instance.new("Part")
		pad.Size = Vector3.new(6, 0.4, 6)
		local position = Vector3.new(spot.X, FLOOR_Y + 0.2, spot.Y)
		pad.CFrame = CFrame.lookAt(position, Vector3.new(0, position.Y, 0))
		pad.CanCollide = false
		pad.CanQuery = false
		style(pad, "Spawn" .. index, Colors.spawn, folder)
		pad.Material = Enum.Material.Neon
		pad.Transparency = 0.3
		table.insert(spawnPoints, pad)
	end
	return spawnPoints
end

-- Builds the whole arena into Workspace and returns its spawn points.
function ArenaBuilder.build(): Arena
	local old = Workspace:FindFirstChild("Arena")
	if old then
		old:Destroy()
	end

	local model = Instance.new("Model")
	model.Name = "Arena"

	buildFloorAndWalls(model)
	buildCenter(model)
	buildTowers(model)
	buildSteppingStones(model)
	buildLedges(model)
	buildCover(model)
	local spawnPoints = buildSpawns(model)

	model.Parent = Workspace
	return {
		model = model,
		spawnPoints = spawnPoints,
	}
end

return ArenaBuilder
