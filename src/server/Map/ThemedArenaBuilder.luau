--!strict
--[[
	ThemedArenaBuilder: builds the themed arenas (Astro Station, Chef's
	Kitchen, Cozy Fireplace, Ant Farm, Coral Reef, Ice Castle, Candy Land
	and Bounce House). Every theme uses the same fair layout; the look comes
	from Map/ArenaThemes.

	Bird's-eye view (Blue spawns west, Red spawns east; mirrored left/right,
	so neither team has an advantage):

	     flank cover ......... flank cover ......... flank cover
	  S   platform   cover          cover   platform   S
	  S   tall    low    tall  CENTREPIECE  tall   low   tall   S
	  S   platform   cover          cover   platform   S
	     flank cover ......... flank cover ......... flank cover

	  * Three lanes (north, middle, south) with cover all along them.
	  * Two raised platforms per side with ramps (high ground).
	  * A big centrepiece in the middle so nobody can see spawn to spawn.

	SIZE: the arena grows with the number of players (Config/MapConfig.scaleFor):
	a 1v1 is the smallest, 2v2 bigger, 4v4 bigger again, and free for all the
	biggest. `scale` stretches the layout; props stay the same size, so a
	bigger arena simply has more room between them. Free for all also gets
	extra spawn points spread all around the arena.
]]

local Workspace = game:GetService("Workspace")

local MapKit = require(script.Parent.MapKit)
local ArenaThemes = require(script.Parent.ArenaThemes)

local FLOOR_Y = 1
local BASE_HALF = 64 -- half the width of a 1v1 arena (studs); bigger matches multiply it

local Builder = {}

type Built = { model: Model, spawnPoints: { BasePart }, ammoSpots: { Vector3 } }

-- Places `fn` for a point on the east side and its mirror on the west.
local function mirrored(fn: (sign: number) -> ())
	fn(1)
	fn(-1)
end

function Builder.build(scale: number?, themeName: string?, freeForAll: boolean?): Built
	local theme = ArenaThemes.get(themeName or "Kitchen")
	local size = math.clamp(scale or 1, 0.8, 2.2)
	local half = BASE_HALF * size

	local old = Workspace:FindFirstChild("ThemedArena")
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "ThemedArena"

	-- A point on the floor, from fractions of the arena (-1..1).
	local function at(u: number, v: number): Vector3
		return Vector3.new(u * half, FLOOR_Y, v * half)
	end

	-- Floor, edge dressing and invisible walls.
	theme.ground(model, half, FLOOR_Y)
	theme.rim(model, half, FLOOR_Y)
	for _, side in { Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) } do
		local alongX = side.X == 0
		local wallSize = if alongX then Vector3.new(half * 2 + 8, 80, 2) else Vector3.new(2, 80, half * 2 + 8)
		MapKit.part(model, "Boundary", wallSize, CFrame.new(side * (half + 1) + Vector3.new(0, 40 + FLOOR_Y, 0)), Color3.new(1, 1, 1), { transparency = 1, shadow = false })
	end

	-- The middle.
	theme.centre(model, at(0, 0))
	theme.low(model, at(0, 0.5), 90)
	theme.low(model, at(0, -0.5), 90)

	-- Each side (mirrored).
	mirrored(function(sign: number)
		local faceCentre = if sign > 0 then 180 else 0 -- yaw that looks back toward the middle
		-- Middle lane.
		theme.tall(model, at(sign * 0.56, 0), faceCentre)
		theme.low(model, at(sign * 0.38, 0.15), faceCentre)
		theme.low(model, at(sign * 0.38, -0.15), faceCentre)
		theme.tall(model, at(sign * 0.2, 0.28), faceCentre + 20 * sign)
		theme.tall(model, at(sign * 0.2, -0.28), faceCentre - 20 * sign)
		-- High ground: a platform on each outer lane, its ramp coming down
		-- toward the middle lane.
		theme.platform(model, at(sign * 0.32, 0.56), Vector3.new(0, 0, -1))
		theme.platform(model, at(sign * 0.32, -0.56), Vector3.new(0, 0, 1))
		-- Flanks.
		theme.low(model, at(sign * 0.62, 0.38), faceCentre)
		theme.low(model, at(sign * 0.62, -0.38), faceCentre)
		theme.tall(model, at(sign * 0.5, 0.82), faceCentre)
		theme.tall(model, at(sign * 0.5, -0.82), faceCentre)
		theme.low(model, at(sign * 0.16, 0.8), 90)
		theme.low(model, at(sign * 0.16, -0.8), 90)
		-- Little touches that don't block anything.
		for _, spot in { { 0.72, 0.18 }, { 0.72, -0.18 }, { 0.44, 0.7 }, { 0.44, -0.7 }, { 0.1, 0.4 }, { 0.1, -0.4 } } do
			theme.decor(model, at(sign * spot[1], spot[2]))
		end
	end)

	-- Spawn pads: four on each team's side, facing the middle.
	local spawnFolder = Instance.new("Folder")
	spawnFolder.Name = "SpawnPoints"
	spawnFolder.Parent = model
	local spawnPoints: { BasePart } = {}
	local function spawnPad(position: Vector3)
		local pad = MapKit.part(spawnFolder, "Spawn", Vector3.new(6, 0.4, 6), CFrame.lookAt(position + Vector3.new(0, 0.2, 0), Vector3.new(0, position.Y + 0.2, position.Z * 0.5)), theme.spawnColor, { material = Enum.Material.Neon, collide = false, shadow = false, transparency = 0.5 })
		table.insert(spawnPoints, pad)
	end
	mirrored(function(sign: number)
		for _, v in { -0.45, -0.15, 0.15, 0.45 } do
			spawnPad(at(sign * 0.86, v))
		end
	end)
	-- Free for all: more pads all around, so a big crowd can spread out.
	if freeForAll then
		for i = 0, 11 do
			local angle = math.rad(15 + i * 30)
			spawnPad(at(math.cos(angle) * 0.7, math.sin(angle) * 0.7))
		end
	end

	-- Slime ammo balls in the lanes (mirrored) and one in each flank.
	local ammoSpots = {
		at(0.3, 0) + Vector3.new(0, 1, 0),
		at(-0.3, 0) + Vector3.new(0, 1, 0),
		at(0.62, 0.62) + Vector3.new(0, 1, 0),
		at(-0.62, 0.62) + Vector3.new(0, 1, 0),
		at(0.62, -0.62) + Vector3.new(0, 1, 0),
		at(-0.62, -0.62) + Vector3.new(0, 1, 0),
	}

	model.Parent = Workspace
	return { model = model, spawnPoints = spawnPoints, ammoSpots = ammoSpots }
end

return Builder
