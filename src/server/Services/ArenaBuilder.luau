--!strict
--[[
	ArenaBuilder
	Builds a simple, colorful low-poly arena from code so the game is
	playable the moment you press Play: a floor, walls, cover blocks,
	a central tower with ramps, bouncy launch pads and spawn points.

	Want to build your own map in Studio instead? Make a Model or Folder
	called "Arena" in Workspace with some SpawnLocations inside, and this
	script will leave it alone.
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local ARENA_NAME = "Arena"
local HALF_SIZE = 110 -- the arena is 220 x 220 studs
local WALL_HEIGHT = 30
local FLOOR_TOP = 0.5

-- A soft pastel palette keeps things lighthearted.
local COLORS = {
	Floor = Color3.fromRGB(150, 215, 160),
	Wall = Color3.fromRGB(120, 140, 210),
	Peach = Color3.fromRGB(255, 190, 130),
	Pink = Color3.fromRGB(245, 140, 160),
	Sky = Color3.fromRGB(130, 200, 245),
	Cream = Color3.fromRGB(250, 240, 210),
	Pad = Color3.fromRGB(255, 240, 120),
	Spawn = Color3.fromRGB(255, 255, 255),
}

local ArenaBuilder = {}

local function block(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Anchored = true
	part.Material = Enum.Material.SmoothPlastic
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- A box resting on the floor, centred at (x, z).
local function crate(name: string, size: Vector3, x: number, z: number, color: Color3, parent: Instance): Part
	return block(name, size, CFrame.new(x, FLOOR_TOP + size.Y / 2, z), color, parent)
end

-- A ramp (wedge) at `position`. `facing` rotates it around the vertical axis.
local function ramp(size: Vector3, position: Vector3, facing: number, color: Color3, parent: Instance)
	local wedge = Instance.new("WedgePart")
	wedge.Name = "Ramp"
	wedge.Size = size
	wedge.CFrame = CFrame.new(position) * CFrame.Angles(0, facing, 0)
	wedge.Color = color
	wedge.Anchored = true
	wedge.Material = Enum.Material.SmoothPlastic
	wedge.Parent = parent
end

function ArenaBuilder.build()
	if workspace:FindFirstChild(ARENA_NAME) then
		return -- you've made your own map
	end

	local arena = Instance.new("Folder")
	arena.Name = ARENA_NAME

	-- Floor and walls
	block("Floor", Vector3.new(HALF_SIZE * 2, 1, HALF_SIZE * 2), CFrame.new(0, 0, 0), COLORS.Floor, arena)
	local wallY = FLOOR_TOP + WALL_HEIGHT / 2
	for _, sign in { -1, 1 } do
		block(
			"Wall",
			Vector3.new(HALF_SIZE * 2, WALL_HEIGHT, 2),
			CFrame.new(0, wallY, sign * HALF_SIZE),
			COLORS.Wall,
			arena
		)
		block(
			"Wall",
			Vector3.new(2, WALL_HEIGHT, HALF_SIZE * 2),
			CFrame.new(sign * HALF_SIZE, wallY, 0),
			COLORS.Wall,
			arena
		)
	end

	-- Central tower: a platform on four pillars, reached by two ramps.
	local platformHeight = 12
	block("TowerTop", Vector3.new(24, 1, 24), CFrame.new(0, FLOOR_TOP + platformHeight + 0.5, 0), COLORS.Cream, arena)
	for _, x in { -10, 10 } do
		for _, z in { -10, 10 } do
			crate("Pillar", Vector3.new(3, platformHeight, 3), x, z, COLORS.Wall, arena)
		end
	end
	local rampSize = Vector3.new(8, platformHeight + 1, 22)
	local rampY = FLOOR_TOP + rampSize.Y / 2
	-- A WedgePart's tall end is at its back (+Z), so these slope up toward the tower.
	ramp(rampSize, Vector3.new(0, rampY, -12 - rampSize.Z / 2), 0, COLORS.Peach, arena)
	ramp(rampSize, Vector3.new(0, rampY, 12 + rampSize.Z / 2), math.pi, COLORS.Peach, arena)

	-- Cover, placed symmetrically so no side has an advantage.
	for _, sign in { -1, 1 } do
		crate("Cover", Vector3.new(16, 6, 3), sign * 40, sign * 30, COLORS.Pink, arena)
		crate("Cover", Vector3.new(3, 6, 16), sign * -40, sign * 30, COLORS.Sky, arena)
		crate("Cover", Vector3.new(8, 8, 8), sign * 70, sign * -10, COLORS.Peach, arena)
		crate("Cover", Vector3.new(8, 8, 8), sign * -70, sign * 10, COLORS.Peach, arena)
		crate("Cover", Vector3.new(24, 10, 3), sign * 25, sign * 75, COLORS.Wall, arena)
		crate("Cover", Vector3.new(3, 10, 24), sign * 75, sign * 60, COLORS.Pink, arena)
		crate("Crate", Vector3.new(5, 5, 5), sign * 15, sign * -45, COLORS.Cream, arena)
		crate("Crate", Vector3.new(5, 5, 5), sign * 55, sign * 45, COLORS.Cream, arena)
		-- Raised side platforms with a step up
		crate("SidePlatform", Vector3.new(20, 7, 12), sign * 85, sign * -75, COLORS.Sky, arena)
		crate("Step", Vector3.new(6, 3.5, 12), sign * 72, sign * -75, COLORS.Cream, arena)
	end

	-- Bouncy launch pads. The client script launches you when you touch one
	-- (movement physics run on each player's own computer in Roblox).
	for _, position in
		{ Vector3.new(-50, 0, -50), Vector3.new(50, 0, 50), Vector3.new(-50, 0, 50), Vector3.new(50, 0, -50) }
	do
		local pad = crate("LaunchPad", Vector3.new(7, 0.6, 7), position.X, position.Z, COLORS.Pad, arena)
		pad.Material = Enum.Material.Neon
		pad:SetAttribute("Power", Config.Movement.LaunchPadPower)
		CollectionService:AddTag(pad, "LaunchPad")
	end

	-- Spawn points around the edge. Neutral = anyone can spawn there.
	for i = 0, 7 do
		local angle = i / 8 * math.pi * 2
		local position = Vector3.new(math.cos(angle) * 92, FLOOR_TOP + 0.5, math.sin(angle) * 92)
		local spawnLocation = Instance.new("SpawnLocation")
		spawnLocation.Name = "Spawn"
		spawnLocation.Size = Vector3.new(6, 1, 6)
		spawnLocation.CFrame = CFrame.lookAt(position, Vector3.new(0, position.Y, 0)) -- face the middle
		spawnLocation.Anchored = true
		spawnLocation.Neutral = true
		spawnLocation.Duration = Config.Player.SpawnProtection -- force field length
		spawnLocation.Color = COLORS.Spawn
		spawnLocation.Material = Enum.Material.SmoothPlastic
		spawnLocation.Transparency = 0.4
		spawnLocation.Parent = arena
	end

	-- Turn off any other spawn points (like the one in the Baseplate template),
	-- which would give a long 10 second force field.
	for _, descendant in workspace:GetDescendants() do
		if descendant:IsA("SpawnLocation") then
			descendant.Enabled = false
		end
	end

	-- Bright, cheerful lighting.
	Lighting.ClockTime = 14
	Lighting.Brightness = 2.5
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 170)
	Lighting.GlobalShadows = true

	arena.Parent = workspace
end

return ArenaBuilder
