--!strict
--[[
	LobbyBuilder: the slime bunker lobby (far away from the arenas).

	  Main hall   dark metal bunker with glowing slime tubes and tanks, pipes,
	              hazard stripes, slime puddles and a central slime pedestal.
	              A big neon SLIME SHOWDOWN sign above a round portal.
	  Side rooms  four big rooms (room for a crowd) behind glowing doorways:
	                left:  WEAPONS (every gun on display) and the ROBUX SHOP
	                       (a gold vault: a giant spinning coin, a round vault
	                       door, coin packs and bundles in lit glass cases)
	                right: PRACTICE RANGE (step on the pad) and DAILY SQUISHY
	                       (shelves of squishies and a squishy ball in a dome)
	  Hallway     through the portal: light strips overhead and glowing queue
	              pads with counters. Left: 1v1, 2v2, 4v4 (real players).
	              Right: practice matches against bots. At the end: FREE FOR ALL.

	Some decorations gently move on each player's screen (the spinning coin,
	the bobbing squishy ball): the server only marks them with attributes,
	and the client's LobbyAnimator moves them.

	Returns where players appear and the pads (QueueService reads them).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MapKit = require(script.Parent.MapKit)
local LobbyProps = require(script.Parent.LobbyProps)
local ShopProps = require(script.Parent.ShopProps)
local GunModel = require(script.Parent.Parent.Components.GunModel)
local WeaponConfig = require(ReplicatedStorage.Shared.Config.WeaponConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)
local RobuxShopConfig = require(ReplicatedStorage.Shared.Config.RobuxShopConfig)
local HatBuilder = require(ReplicatedStorage.Shared.Cosmetics.HatBuilder)
local CharmBuilder = require(ReplicatedStorage.Shared.Cosmetics.CharmBuilder)

export type Pad = {
	part: BasePart,
	mode: string, -- ModeConfig mode Id
	bots: boolean, -- true = fill the other slots with bots (practice)
	radius: number,
	counter: TextLabel, -- the "1/2" text above the pad
	screenCount: TextLabel?, -- the same count on the big screen behind the pad
	avatars: Frame?, -- where the screen shows who's waiting (QueueService fills it)
}

export type Lobby = {
	model: Model,
	spawnCFrame: CFrame,
	origin: Vector3,
	pads: { Pad },
	problems: { string }, -- pieces that failed to build (empty when all is well)
	rangePad: BasePart?, -- step on it to go to the practice range (PracticeService)
	ffaPad: Pad?, -- step on it to jump into free for all (FreeForAllService)
}

local ORIGIN = Vector3.new(0, 300, 700) -- centre of the main hall's floor
local HALL_X, HALL_Z, HALL_HEIGHT = 40, 35, 34 -- half width, half depth, height
local HALL_FRONT = ORIGIN.Z - HALL_Z -- the wall with the sign and the portal
local HALL_LENGTH, HALL_HALF_WIDTH, HALL_HEIGHT_2 = 92, 22, 26 -- the hallway
local PORTAL_RADIUS = 8
local PAD_RADIUS = 6.5
local DOOR_Z, DOOR_HALF, DOOR_HEIGHT = 22, 8, 16 -- the back pair of side doorways (weapons room, practice range); wide enough for a crowd
local DAILY_Z = -11 -- the front pair: the DAILY SQUISHY room's doorway (right wall) and the ROBUX SHOP's (left wall)
local ROOM_DEPTH, ROOM_HEIGHT = 44, 24 -- every side room: how far back it goes from the hall wall, and how tall it is
local RANGE_PAD_RADIUS = 7 -- the practice range pad (PracticeService reads its "PadRadius")
local GOLD = ShopProps.GOLD

local METAL, METAL_DARK = LobbyProps.METAL, LobbyProps.METAL_DARK
local GREEN, PURPLE, CYAN = LobbyProps.GREEN, LobbyProps.PURPLE, LobbyProps.CYAN

--[[
	A side room. `side` is -1 for a room behind the hall's left wall (it
	reaches toward -X) and 1 for the right wall. `cz` is the middle of its
	width (along Z) and `halfZ` half its width.
]]
type Room = { name: string, side: number, cz: number, halfZ: number }

local WEAPONS_ROOM: Room = { name = "Weapons", side = -1, cz = DOOR_Z - 1, halfZ = 14 } -- 44 x 28 studs
local ROBUX_ROOM: Room = { name = "Robux", side = -1, cz = DAILY_Z, halfZ = 13 } -- 44 x 26
local RANGE_ROOM: Room = { name = "Range", side = 1, cz = DOOR_Z, halfZ = 13 } -- 44 x 26
local DAILY_ROOM: Room = { name = "Daily", side = 1, cz = DAILY_Z, halfZ = 13 } -- 44 x 26

local LobbyBuilder = {}

-- Problems found while building (shown on screen and in the Output).
local problems: { string } = {}

local function record(label: string, err: unknown)
	local text = `{label}: {tostring(err)}`
	table.insert(problems, text)
	warn(`[LobbyBuilder] {text}`)
end

-- Runs one piece of the build. If it fails, it is skipped and reported,
-- so one broken decoration can't stop the whole bunker from appearing.
local function try(label: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		record(label, err)
	end
end

-- A copy of a helper module where every function is protected like `try`.
local function protect<T>(module: T, moduleName: string): T
	local safe = {}
	for name, value in module :: any do
		if typeof(value) == "function" then
			safe[name] = function(...)
				local results = table.pack(pcall(value, ...))
				if not results[1] then
					record(`{moduleName}.{name}`, results[2])
					return nil
				end
				return table.unpack(results, 2, results.n)
			end
		else
			safe[name] = value
		end
	end
	return safe :: any
end

local Props = protect(LobbyProps, "LobbyProps")
local Kit = protect(MapKit, "MapKit")

local function at(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end

local function box(model: Model, name: string, size: Vector3, center: Vector3, color: Color3, material: Enum.Material?)
	return Kit.part(model, name, size, CFrame.new(center), color, { material = material or Enum.Material.Metal })
end

-- A glowing decoration that nobody bumps into.
local function glowPart(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3)
	return Kit.part(model, name, size, cframe, color, { material = Enum.Material.Neon, collide = false, shadow = false })
end

local function prompt(parent: BasePart, name: string, action: string, object: string, distance: number?)
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = 0
	p.MaxActivationDistance = distance or 12
	p.RequiresLineOfSight = false
	p.Parent = parent
end

-- Side rooms -----------------------------------------------------------------

-- A point in a room: `depth` studs in from the hall wall, `y` up from the
-- floor, and `across` from the room's middle line (along Z).
local function inRoom(room: Room, depth: number, y: number, across: number): Vector3
	return at(room.side * (HALL_X + 2 + depth), y, room.cz + across)
end

-- The way from a room's back wall toward its doorway.
local function towardDoor(room: Room): Vector3
	return Vector3.new(-room.side, 0, 0)
end

-- Floor, ceiling, back wall and side walls (the hall's wall, with the
-- doorway in it, is the room's front).
local function shell(model: Model, room: Room, wallColor: Color3?, floorColor: Color3?, floorMaterial: Enum.Material?)
	local name = room.name
	local width = room.halfZ * 2
	box(model, name .. "Floor", Vector3.new(ROOM_DEPTH, 2, width), inRoom(room, ROOM_DEPTH / 2, -1, 0), floorColor or METAL_DARK, floorMaterial or Enum.Material.DiamondPlate)
	box(model, name .. "Ceiling", Vector3.new(ROOM_DEPTH, 2, width), inRoom(room, ROOM_DEPTH / 2, ROOM_HEIGHT + 1, 0), METAL_DARK)
	box(model, name .. "Wall", Vector3.new(2, ROOM_HEIGHT, width + 2), inRoom(room, ROOM_DEPTH + 1, ROOM_HEIGHT / 2, 0), wallColor or METAL)
	for _, sign in { -1, 1 } do
		box(model, name .. "Wall", Vector3.new(ROOM_DEPTH + 2, ROOM_HEIGHT, 2), inRoom(room, ROOM_DEPTH / 2 + 1, ROOM_HEIGHT / 2, sign * (room.halfZ + 1)), wallColor or METAL)
	end
end

-- Glowing strips across the ceiling, each with a light.
local function lamps(model: Model, room: Room, glow: Color3, count: number)
	for i = 1, count do
		local depth = ROOM_DEPTH * (i - 0.5) / count
		local lamp = box(model, room.name .. "Lamp", Vector3.new(1.4, 0.4, 10), inRoom(room, depth, ROOM_HEIGHT - 0.3, 0), Color3.fromRGB(235, 240, 255), Enum.Material.Neon)
		if lamp then
			Props.light(lamp, glow, 34, 1.1)
		end
	end
end

-- A panel on a wall with a glowing outline. `center` is on the wall's
-- surface and `facing` points out of the wall.
local function wallPanel(model: Model, center: Vector3, facing: Vector3, width: number, height: number, panelColor: Color3, glow: Color3)
	local frame = CFrame.lookAt(center, center + facing)
	Kit.part(model, "WallPanel", Vector3.new(width, height, 0.3), frame * CFrame.new(0, 0, -0.15), panelColor, { material = Enum.Material.SmoothPlastic, collide = false })
	for _, sign in { -1, 1 } do
		glowPart(model, "PanelGlow", Vector3.new(width + 0.3, 0.25, 0.4), frame * CFrame.new(0, sign * height / 2, -0.2), glow)
		glowPart(model, "PanelGlow", Vector3.new(0.25, height + 0.3, 0.4), frame * CFrame.new(sign * width / 2, 0, -0.2), glow)
	end
end

-- A round red-and-white target on a wall (`center` on the wall's surface).
local function wallTarget(model: Model, center: Vector3, facing: Vector3, diameter: number)
	local colors = { Color3.fromRGB(220, 50, 60), Color3.fromRGB(245, 245, 245) }
	for index, size in { 1, 0.78, 0.56, 0.34, 0.14 } do
		local out = 0.1 + index * 0.05 -- each smaller ring sits a little further out
		local cframe = CFrame.lookAt(center + facing * out, center + facing * (out + 1)) * CFrame.Angles(0, math.rad(90), 0)
		Kit.part(model, "WallTarget", Vector3.new(0.1, diameter * size, diameter * size), cframe, colors[(index - 1) % 2 + 1], { shape = Enum.PartType.Cylinder, collide = false, shadow = false })
	end
end

-- Main hall -------------------------------------------------------------------

local function buildHall(model: Model)
	box(model, "Floor", Vector3.new(HALL_X * 2, 2, HALL_Z * 2), at(0, -1, 0), METAL_DARK, Enum.Material.DiamondPlate)
	box(model, "Walkway", Vector3.new(16, 0.1, HALL_Z * 2 - 4), at(0, 0.05, 0), Color3.fromRGB(92, 96, 104), Enum.Material.DiamondPlate)
	Props.hazardLine(model, at(-8.6, 0, HALL_Z - 2), at(-8.6, 0, -HALL_Z + 2), 1.2)
	Props.hazardLine(model, at(8.6, 0, HALL_Z - 2), at(8.6, 0, -HALL_Z + 2), 1.2)
	box(model, "Ceiling", Vector3.new(HALL_X * 2, 2, HALL_Z * 2), at(0, HALL_HEIGHT + 1, 0), METAL_DARK)
	box(model, "WallBack", Vector3.new(HALL_X * 2, HALL_HEIGHT, 2), at(0, HALL_HEIGHT / 2, HALL_Z + 1), METAL)
	-- Corner posts close the little gaps where the walls meet.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			box(model, "CornerPost", Vector3.new(2, HALL_HEIGHT, 2), at(sx * (HALL_X + 1), HALL_HEIGHT / 2, sz * (HALL_Z + 1)), METAL)
		end
	end
	-- Side walls with doorways: WEAPONS and ROBUX SHOP on the left;
	-- PRACTICE RANGE and DAILY SQUISHY on the right.
	local doors = {
		{ side = -1, z = DOOR_Z, title = "WEAPONS", glow = PURPLE },
		{ side = -1, z = DAILY_Z, title = "ROBUX SHOP", glow = GOLD },
		{ side = 1, z = DOOR_Z, title = "PRACTICE RANGE", glow = CYAN },
		{ side = 1, z = DAILY_Z, title = "DAILY SQUISHY", glow = GREEN },
	}
	for _, side in { -1, 1 } do
		local x = side * (HALL_X + 1)
		local doorZs: { number } = {}
		for _, door in doors do
			if door.side == side then
				table.insert(doorZs, door.z)
			end
		end
		table.sort(doorZs)
		-- Wall pieces between the doorways, and a lintel over each one.
		local cursor = -HALL_Z
		for _, z in doorZs do
			local front = z - DOOR_HALF
			if front > cursor then
				box(model, "WallSide", Vector3.new(2, HALL_HEIGHT, front - cursor), at(x, HALL_HEIGHT / 2, (cursor + front) / 2), METAL)
			end
			box(model, "WallSide", Vector3.new(2, HALL_HEIGHT - DOOR_HEIGHT, DOOR_HALF * 2), at(x, DOOR_HEIGHT + (HALL_HEIGHT - DOOR_HEIGHT) / 2, z), METAL)
			cursor = z + DOOR_HALF
		end
		box(model, "WallSide", Vector3.new(2, HALL_HEIGHT, HALL_Z - cursor), at(x, HALL_HEIGHT / 2, (cursor + HALL_Z) / 2), METAL)
		-- Dark panels on the wall, clear of the doorways.
		for _, z in { -28, 5.5 } do
			box(model, "WallPanel", Vector3.new(0.6, 14, 10), at(side * (HALL_X - 0.2), 9, z), METAL_DARK)
		end
	end
	-- Glowing door frames and a sign over every doorway.
	for _, door in doors do
		local side, z, glow = door.side, door.z, door.glow
		for _, edge in { z - DOOR_HALF - 0.4, z + DOOR_HALF + 0.4 } do
			box(model, "DoorGlow", Vector3.new(0.8, DOOR_HEIGHT, 0.8), at(side * (HALL_X - 0.2), DOOR_HEIGHT / 2, edge), glow, Enum.Material.Neon)
		end
		box(model, "DoorGlow", Vector3.new(0.8, 0.8, DOOR_HALF * 2 + 1.6), at(side * (HALL_X - 0.2), DOOR_HEIGHT + 0.4, z), glow, Enum.Material.Neon)
		local signPos = at(side * (HALL_X - 0.5), DOOR_HEIGHT + 2.6, z)
		Props.neonSign(model, "DoorSign", Vector3.new(18, 4, 0.5), CFrame.lookAt(signPos, signPos + Vector3.new(-side, 0, 0)), door.title, glow)
	end
	-- Front wall around the portal opening (opening = 2 x radius wide).
	local gap = PORTAL_RADIUS * 1.05
	local sideWidth = HALL_X - gap
	for _, side in { -1, 1 } do
		box(model, "WallFront", Vector3.new(sideWidth, HALL_HEIGHT, 2), at(side * (gap + sideWidth / 2), HALL_HEIGHT / 2, -HALL_Z - 1), METAL)
	end
	box(model, "WallFrontTop", Vector3.new(gap * 2, HALL_HEIGHT - PORTAL_RADIUS * 2, 2), at(0, PORTAL_RADIUS * 2 + (HALL_HEIGHT - PORTAL_RADIUS * 2) / 2, -HALL_Z - 1), METAL)
	-- Floor through the doorway, joining the hall floor to the hallway floor.
	box(model, "PortalFloor", Vector3.new(gap * 2, 2, 6), at(0, -1, -HALL_Z - 1), METAL_DARK, Enum.Material.DiamondPlate)

	-- The portal: an octagon frame with a glowing purple inner ring.
	local portalCenter = at(0, PORTAL_RADIUS, -HALL_Z + 0.5)
	Props.octagonFrame(model, portalCenter, PORTAL_RADIUS + 1.2, METAL_DARK, 3, 2.4, Enum.Material.DiamondPlate)
	Props.octagonFrame(model, portalCenter + Vector3.new(0, 0, 0.8), PORTAL_RADIUS - 0.2, PURPLE, 1, 0.6, Enum.Material.Neon)

	-- The big neon sign above the portal.
	local signPosition = at(0, 25, -HALL_Z + 0.2)
	Props.neonSign(model, "BunkerSign", Vector3.new(36, 9, 0.6), CFrame.lookAt(signPosition, signPosition + Vector3.new(0, 0, 1)), "SLIME SHOWDOWN", Color3.fromRGB(190, 255, 150))

	-- How-to-play board on the front wall, in the clear space between the
	-- purple tube and the portal (so no tube hides it).
	local board = at(-17, 12, -HALL_Z + 0.2)
	Props.neonSign(model, "HowToPlay", Vector3.new(12, 9, 0.4), CFrame.lookAt(board, board + Vector3.new(0, 0, 1)),
		"HOW TO PLAY\nPress PLAY, or stand on a pad\nin the hallway to queue\nLeft doors: WEAPONS, ROBUX SHOP\nRight doors: PRACTICE RANGE,\nDAILY SQUISHY", Color3.fromRGB(200, 255, 180))

	-- Ceiling lamps.
	for _, x in { -20, 0, 20 } do
		for _, z in { -15, 15 } do
			local lamp = box(model, "CeilingLamp", Vector3.new(10, 0.5, 1.5), at(x, HALL_HEIGHT - 0.3, z), Color3.fromRGB(235, 240, 255), Enum.Material.Neon)
			Props.light(lamp, Color3.fromRGB(220, 235, 255), 34, 0.9)
		end
	end
end

local function buildSlime(model: Model)
	-- Tubes along the walls (clear of the doorways), a big tank on the
	-- right, a pedestal in the middle.
	Props.slimeTube(model, at(-34, 0, -27), 20, 6, GREEN)
	Props.slimeTube(model, at(-26, 0, -29), 16, 5, PURPLE)
	Props.slimeTube(model, at(-35, 0, 5.5), 18, 6, GREEN)
	Props.slimeTube(model, at(31, 0, -27), 22, 11, GREEN)
	Props.slimeTube(model, at(35, 0, 7), 14, 7, CYAN)
	Props.slimeTube(model, at(24, 0, 30), 14, 7, PURPLE)
	box(model, "PedestalBase", Vector3.new(12, 1, 12), at(0, 0.5, -10), METAL_DARK, Enum.Material.DiamondPlate)
	Props.slimeTube(model, at(0, 1, -10), 9, 5, GREEN)

	-- Pipes: along the side walls (above the door signs, with glowing glass
	-- sections) and overhead.
	for _, side in { -1, 1 } do
		Props.pipe(model, at(side * 38.5, 26.5, -HALL_Z + 2), at(side * 38.5, 26.5, HALL_Z - 2), 3, GREEN)
		Props.pipe(model, at(side * 38.5, 23, -HALL_Z + 2), at(side * 38.5, 23, HALL_Z - 2), 2, nil)
	end
	Props.pipe(model, at(-HALL_X + 1, 30, -12), at(HALL_X - 1, 30, -12), 2.5, GREEN)
	Props.pipe(model, at(-HALL_X + 1, 31, 10), at(HALL_X - 1, 31, 10), 2, PURPLE)

	-- Glowing slime puddles.
	Props.puddle(model, at(-12, 0, 6), 7, GREEN)
	Props.puddle(model, at(-18, 0, -20), 5, PURPLE)
	Props.puddle(model, at(6, 0, 18), 6, GREEN)
	Props.puddle(model, at(14, 0, -22), 4, GREEN)
	Props.puddle(model, at(22, 0, 4), 5, PURPLE)
end

-- A real squishy from the shop (Cosmetics/HatBuilder), standing on `base`
-- with its face toward `faceDirection`, anchored as a display piece.
local function displaySquishy(model: Model, hatId: string, base: Vector3, faceDirection: Vector3, scale: number)
	local built = HatBuilder.build(ShopConfig.getHat(hatId), CFrame.lookAt(base, base + faceDirection), Vector3.new(1, 0.6, 1))
	if built == nil then
		return
	end
	built.Name = "DisplaySquishy"
	for _, part in built:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
		end
	end
	if scale ~= 1 then
		built.WorldPivot = CFrame.new(base) -- grow from where it stands
		built:ScaleTo(scale)
	end
	built.Parent = model
end

--[[
	The DAILY SQUISHY room behind the right wall's front doorway: two rows
	of shelves full of squishies on each side wall, and in the middle the
	machine: a glass dome with a big squishy ball floating inside (on your
	screen it slowly bobs, looks around and changes colour).
]]
local function buildDailyRoom(model: Model)
	local room = DAILY_ROOM
	local doorward = towardDoor(room)
	shell(model, room)
	lamps(model, room, GREEN, 3)
	local signPos = inRoom(room, ROOM_DEPTH - 0.1, 18, 0)
	Props.neonSign(model, "DailySign", Vector3.new(16, 4.5, 0.4), CFrame.lookAt(signPos, signPos + doorward), "DAILY SQUISHY", GREEN)
	-- Slime tubes in the back corners.
	for _, sign in { -1, 1 } do
		Props.slimeTube(model, inRoom(room, ROOM_DEPTH - 3.5, 0, sign * 10.3), 20, 4.5, GREEN)
	end

	-- Shelves: two rows on each side wall, five squishies on each row, all
	-- turned to face you as you come in.
	local squishies = {
		"Squishy_DumplingPeach", "Squishy_Donut", "Squishy_JellyCubePink", "Squishy_IceCream", "Squishy_Popcorn",
		"Squishy_DumplingLilac", "Squishy_Butter", "Squishy_JellyCubeBlue", "Squishy_Cake", "Squishy_DumplingMint",
	}
	for _, sign in { -1, 1 } do
		local across = sign * (room.halfZ - 1.6)
		for row, y in { 4.5, 10 } do
			box(model, "DailyShelf", Vector3.new(30, 0.5, 3.2), inRoom(room, ROOM_DEPTH / 2, y - 0.25, across), METAL_DARK, Enum.Material.DiamondPlate)
			glowPart(model, "DailyShelfGlow", Vector3.new(30, 0.15, 0.2), CFrame.new(inRoom(room, ROOM_DEPTH / 2, y - 0.05, across - sign * 1.5)), GREEN)
			for i = 1, 5 do
				local index = (row - 1) * 5 + i
				local hatId = squishies[if sign > 0 then index else #squishies + 1 - index]
				try(`shelf squishy {hatId}`, function()
					displaySquishy(model, hatId, inRoom(room, 10 + (i - 1) * 6, y, across), Vector3.new(doorward.X * 0.5, 0, -sign), 1.25)
				end)
			end
		end
	end

	-- The machine in the middle: a glass dome on a glowing base, with a ring
	-- of light on the floor round it.
	local middle = ROOM_DEPTH / 2
	Kit.cylinder(model, "DailyFloorRing", inRoom(room, middle, 0, 0), 0.06, 17, GREEN, { material = Enum.Material.Neon, collide = false, shadow = false })
	Kit.cylinder(model, "DailyFloorInner", inRoom(room, middle, 0, 0), 0.08, 16, METAL_DARK, { material = Enum.Material.DiamondPlate, collide = false, shadow = false })
	local base = box(model, "DailyBase", Vector3.new(10, 3, 10), inRoom(room, middle, 1.5, 0), METAL_DARK, Enum.Material.DiamondPlate)
	Kit.cylinder(model, "DailyBaseGlow", inRoom(room, middle, 3, 0), 0.3, 10.8, GREEN, { material = Enum.Material.Neon, collide = false, shadow = false })
	-- (See-through plastic, not Roblox's Glass material: Glass would hide the
	-- ball's blush and shine, and anything else see-through behind it.)
	local dome = Kit.part(model, "DailyDome", Vector3.one * 10, CFrame.new(inRoom(room, middle, 7.6, 0)), Color3.fromRGB(220, 240, 255), { shape = Enum.PartType.Ball, material = Enum.Material.SmoothPlastic, transparency = 0.8 })
	if dome then
		dome.Reflectance = 0.12
	end
	-- Inside the dome: a big round squishy ball with a face.
	try("dome squishy ball", function()
		local center = inRoom(room, middle, 7.4, 0)
		local ball = HatBuilder.buildBall(Color3.fromRGB(255, 170, 210), CFrame.lookAt(center, center + doorward), 5.2)
		ball:SetAttribute("LobbyBob", 0.35)
		ball:SetAttribute("LobbySway", 18)
		ball:SetAttribute("LobbyPivot", ball.WorldPivot)
		local body = ball:FindFirstChild("Body")
		if body then
			body:SetAttribute("LobbyHue", 16) -- a slow pastel rainbow
		end
		ball.Parent = model
	end)
	local glowHolder = Kit.part(model, "DailyDomeLight", Vector3.one * 0.4, CFrame.new(inRoom(room, middle, 4, 0)), GREEN, { collide = false, transparency = 1, shadow = false })
	if glowHolder then
		Props.light(glowHolder, Color3.fromRGB(230, 255, 230), 16, 1.4)
	end
	if base then
		try("Daily Squishy prompt", function()
			prompt(base, "DailySquishy", "Open", "Daily Squishy", 14)
		end)
		-- "READY!" / "NEXT IN 5h" (each player's own client fills this in).
		try("Daily Squishy sign", function()
			local status = Instance.new("BillboardGui")
			status.Size = UDim2.fromScale(8, 2) -- in studs, so it shrinks with distance
			status.StudsOffset = Vector3.new(0, 12.5, 0)
			status.MaxDistance = 90
			status.LightInfluence = 0
			status.Parent = base
			local label = Instance.new("TextLabel")
			label.Name = "DailyStatus"
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.Font = Enum.Font.LuckiestGuy
			label.TextScaled = true
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextStrokeTransparency = 0.2
			label.Text = "READY!"
			label.Parent = status
		end)
	end
end

--[[
	The ROBUX SHOP behind the left wall's front doorway, dressed as a gold
	vault: a red carpet leads to a giant spinning coin, a huge round vault
	door glows on the back wall, and lit glass cases along the walls show
	each coin pack and bundle with its price. Every case (and the coin's
	stand) opens the shop's ROBUX tab.
]]
local function buildRobuxRoom(model: Model)
	local room = ROBUX_ROOM
	local doorward = towardDoor(room)
	local wallColor = Color3.fromRGB(34, 29, 44)
	local panelColor = Color3.fromRGB(48, 41, 60)
	shell(model, room, wallColor, Color3.fromRGB(30, 27, 36), Enum.Material.Marble)
	local random = Random.new(777) -- the same treasure every time
	local month = ShopConfig.currentMonth()
	local theme = RobuxShopConfig.themeFor(month)

	-- Dark lining on the inside of the hall's wall, so the whole room matches.
	try("robux room lining", function()
		local width = room.halfZ - DOOR_HALF
		for _, sign in { -1, 1 } do
			box(model, "RobuxLining", Vector3.new(0.4, ROOM_HEIGHT, width), inRoom(room, 0.2, ROOM_HEIGHT / 2, sign * (DOOR_HALF + width / 2)), wallColor, Enum.Material.SmoothPlastic)
		end
		box(model, "RobuxLining", Vector3.new(0.4, ROOM_HEIGHT - DOOR_HEIGHT, DOOR_HALF * 2), inRoom(room, 0.2, (DOOR_HEIGHT + ROOM_HEIGHT) / 2, 0), wallColor, Enum.Material.SmoothPlastic)
	end)

	-- Gold trim: a glowing line along the bottom of the walls, a gold band
	-- near the top, and glowing strips up the side walls.
	try("robux room trim", function()
		for _, sign in { -1, 1 } do
			local wallAcross = sign * (room.halfZ - 0.1)
			glowPart(model, "GoldBaseboard", Vector3.new(ROOM_DEPTH, 0.3, 0.2), CFrame.new(inRoom(room, ROOM_DEPTH / 2, 0.55, wallAcross)), GOLD)
			Kit.part(model, "GoldBand", Vector3.new(ROOM_DEPTH, 0.8, 0.3), CFrame.new(inRoom(room, ROOM_DEPTH / 2, ROOM_HEIGHT - 1.6, wallAcross)), ShopProps.GOLD_DARK, { material = Enum.Material.Metal, collide = false, shadow = false })
			for _, depth in { 13.5, 27.5 } do
				glowPart(model, "GoldStrip", Vector3.new(0.4, 14, 0.3), CFrame.new(inRoom(room, depth, 9, sign * (room.halfZ - 0.15))), GOLD)
			end
		end
		Kit.part(model, "GoldBand", Vector3.new(0.3, 0.8, room.halfZ * 2), CFrame.new(inRoom(room, ROOM_DEPTH - 0.1, ROOM_HEIGHT - 1.6, 0)), ShopProps.GOLD_DARK, { material = Enum.Material.Metal, collide = false, shadow = false })
	end)

	-- A red carpet with gold edges, from the doorway to the vault.
	try("robux carpet", function()
		local length = ROOM_DEPTH - 4
		local middle = inRoom(room, length / 2 + 0.3, 0.05, 0)
		Kit.part(model, "RedCarpet", Vector3.new(length, 0.1, 6), CFrame.new(middle), Color3.fromRGB(140, 24, 48), { material = Enum.Material.Fabric, collide = false, shadow = false })
		for _, sign in { -1, 1 } do
			glowPart(model, "CarpetEdge", Vector3.new(length, 0.14, 0.3), CFrame.new(middle + Vector3.new(0, 0.02, sign * 3.1)), GOLD)
		end
	end)

	-- The giant coin, spinning and bobbing above a glowing stand.
	try("giant coin", function()
		local standBase = inRoom(room, 27, 0, 0)
		local top, step = ShopProps.dais(model, standBase, 9, 13)
		local center = standBase + Vector3.new(0, top + 5, 0)
		local coin = ShopProps.giantCoin(model, CFrame.lookAt(center, center + doorward), 8.4)
		coin:SetAttribute("LobbySpin", 45)
		coin:SetAttribute("LobbyBob", 0.45)
		coin:SetAttribute("LobbyPivot", coin.WorldPivot)
		prompt(step, "RobuxCounter", "Open Robux shop", "Coins & bundles", 12)
	end)

	-- The vault door on the back wall, with the sign above it.
	try("vault door", function()
		local wallPoint = inRoom(room, ROOM_DEPTH, 8.5, 0)
		ShopProps.vaultDoor(model, CFrame.lookAt(wallPoint, wallPoint + doorward), 13)
		local signPos = inRoom(room, ROOM_DEPTH - 0.1, 19.6, 0)
		Props.neonSign(model, "RobuxSign", Vector3.new(20, 4, 0.4), CFrame.lookAt(signPos, signPos + doorward), "COINS & BUNDLES", GOLD)
	end)

	-- The coin packs in glass cases along the walls (smallest nearest the
	-- door). "Left" is as you walk in.
	local packSpots = {
		{ depth = 9, across = 9.4 }, -- pouch (left)
		{ depth = 9, across = -9.4 }, -- jar (right)
		{ depth = 18, across = 9.4 }, -- bucket (left)
		{ depth = 18, across = -9.4 }, -- vault (right)
	}
	for index, pack in RobuxShopConfig.CoinPacks do
		local spot = packSpots[index]
		if spot then
			try(`coin pack {pack.Id}`, function()
				local sign = math.sign(spot.across)
				local base = inRoom(room, spot.depth, 0, spot.across)
				local look = Vector3.new(doorward.X * 0.35, 0, -sign).Unit -- toward the carpet, a little toward the door
				wallPanel(model, inRoom(room, spot.depth, 8, sign * room.halfZ), Vector3.new(0, 0, -sign), 6.6, 13, panelColor, GOLD)
				local plinth, top = ShopProps.displayStand(model, CFrame.lookAt(base, base + look), 4.4, {
					title = pack.DisplayName,
					detail = `+{pack.Coins} COINS`,
					price = `R$ {pack.Robux}`,
					badge = pack.Badge,
					badgeColor = if pack.Badge == "BEST VALUE" then Color3.fromRGB(255, 90, 140) else Color3.fromRGB(70, 160, 255),
				})
				if index == 1 then
					ShopProps.pouch(model, top, 1, random)
				elseif index == 2 then
					ShopProps.jar(model, top, 1, random)
				elseif index == 3 then
					ShopProps.bucket(model, top, 0.95, random)
				else
					ShopProps.safe(model, top, 1)
				end
				prompt(plinth, "RobuxCounter", "Buy coins", pack.DisplayName, 10)
			end)
		end
	end

	-- The bundles in bigger cases near the back: a treasure chest (Coin
	-- Rush) and a present in this month's colours (Monthly Collection).
	local bundleSpots = { { depth = 37.5, across = 9.2 }, { depth = 37.5, across = -9.2 } }
	for index, bundle in RobuxShopConfig.Bundles do
		local spot = bundleSpots[index]
		if spot then
			try(`bundle {bundle.Id}`, function()
				local sign = math.sign(spot.across)
				local base = inRoom(room, spot.depth, 0, spot.across)
				local look = Vector3.new(doorward.X * 0.5, 0, -sign).Unit
				wallPanel(model, inRoom(room, spot.depth, 8.5, sign * room.halfZ), Vector3.new(0, 0, -sign), 7.6, 14, panelColor, GOLD)
				local _, coins, worth = RobuxShopConfig.bundleContents(bundle, month)
				local saving = if worth > 0 then math.floor((1 - bundle.Robux / worth) * 100 + 0.5) else 0
				local items = #bundle.Themed
				local detail = if bundle.Coins > 0
					then `{coins} COINS + {items} ITEMS`
					elseif theme then `{string.upper(theme.Name)} SET`
					else `{items} THEMED ITEMS`
				local plinth, top = ShopProps.displayStand(model, CFrame.lookAt(base, base + look), 5.2, {
					title = bundle.DisplayName,
					detail = detail,
					price = `R$ {bundle.Robux}`,
					badge = if saving > 0 then `SAVE {saving}%` else nil,
					badgeColor = Color3.fromRGB(255, 90, 140),
				})
				if bundle.Coins > 0 then
					ShopProps.chest(model, top, 1.05, random)
				else
					local boxColor = if theme then theme.Main else Color3.fromRGB(255, 120, 170)
					local ribbon = if theme then theme.Accent else GOLD
					ShopProps.giftBox(model, top, 2.8, boxColor, ribbon)
				end
				prompt(plinth, "RobuxCounter", "See bundle", bundle.DisplayName, 10)
			end)
		end
	end

	-- Treasure in the corners: heaps of gold (with a gem) by the doorway,
	-- stacks of gold bars at the back.
	try("robux treasure", function()
		for _, sign in { -1, 1 } do
			ShopProps.coinPile(model, inRoom(room, 3.2, 0, sign * 10.6), 3.6, random)
			local gem = CharmBuilder.build("Gem", { scale = 2.4 })
			local gemAt = inRoom(room, 3.1, 1.9, sign * 10.4)
			gem:PivotTo(CFrame.lookAt(gemAt, inRoom(room, 0, 1.9, 0)) * CFrame.Angles(math.rad(-20), 0, math.rad(15)))
			gem.Parent = model
			ShopProps.goldBars(model, CFrame.new(inRoom(room, ROOM_DEPTH - 1.8, 0, sign * 10.8)), 4)
		end
	end)

	-- Light: a ring of light above the coin and two long warm strips.
	try("robux lights", function()
		local ringCenter = inRoom(room, 27, ROOM_HEIGHT - 0.4, 0)
		local segments, radius = 20, 6.5
		local segmentLength = 2 * math.pi * radius / segments * 1.05
		for i = 0, segments - 1 do
			local angle = i * 2 * math.pi / segments
			local position = ringCenter + Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
			glowPart(model, "RingLight", Vector3.new(0.5, 0.3, segmentLength), CFrame.lookAt(position, ringCenter) * CFrame.Angles(0, math.rad(90), 0), ShopProps.GOLD_LIGHT)
		end
		local hub = Kit.part(model, "RingLightHub", Vector3.one * 0.5, CFrame.new(ringCenter), GOLD, { collide = false, transparency = 1, shadow = false })
		if hub then
			Props.light(hub, Color3.fromRGB(255, 225, 170), 40, 1.3)
		end
		for _, sign in { -1, 1 } do
			local strip = box(model, "RobuxLamp", Vector3.new(30, 0.4, 1), inRoom(room, 20, ROOM_HEIGHT - 0.3, sign * 8), Color3.fromRGB(255, 240, 215), Enum.Material.Neon)
			if strip then
				Props.light(strip, GOLD, 30, 0.9)
			end
		end
	end)
end

--[[
	WEAPONS room behind the left wall's back doorway: every gun on its own
	display table with its price (rarest at the back), and a counter at the
	back that opens the shop's Guns tab.
]]
local function buildWeaponsRoom(model: Model)
	local room = WEAPONS_ROOM
	local doorward = towardDoor(room)
	shell(model, room)
	lamps(model, room, Color3.fromRGB(230, 215, 255), 3)
	-- A big target painted on the floor.
	for index, diameter in { 26, 20, 14, 8, 3 } do
		Kit.cylinder(model, "FloorRing", inRoom(room, ROOM_DEPTH / 2, 0.02 + index * 0.01, 0), 0.04, diameter, if index % 2 == 1 then Color3.fromRGB(150, 36, 52) else Color3.fromRGB(70, 24, 36), { material = Enum.Material.SmoothPlastic, collide = false, shadow = false })
	end
	local signPos = inRoom(room, ROOM_DEPTH - 0.1, 16, 0)
	Props.neonSign(model, "WeaponsSign", Vector3.new(18, 5, 0.4), CFrame.lookAt(signPos, signPos + doorward), "WEAPONS", PURPLE)

	-- Display tables: four along each side wall, in pairs from the door back.
	local roomCenter = inRoom(room, ROOM_DEPTH / 2, 3.6, 0)
	for index, item in ShopConfig.Weapons do
		local stats = WeaponConfig.get(item.WeaponId)
		local pair = math.ceil(index / 2) - 1
		local across = if index % 2 == 1 then -(room.halfZ - 3) else room.halfZ - 3
		if stats and pair <= 3 then
			try(`weapon display {item.WeaponId}`, function()
				local depth = 8 + pair * 9.5
				local sign = math.sign(across)
				wallPanel(model, inRoom(room, depth, 7, sign * room.halfZ), Vector3.new(0, 0, -sign), 7, 9, Color3.fromRGB(40, 36, 56), PURPLE)
				local base = inRoom(room, depth, 0, across)
				box(model, "DisplayTable", Vector3.new(4, 3, 4), base + Vector3.new(0, 1.5, 0), METAL_DARK, Enum.Material.DiamondPlate)
				box(model, "DisplayGlow", Vector3.new(4.3, 0.2, 4.3), base + Vector3.new(0, 3.05, 0), PURPLE, Enum.Material.Neon)
				-- The gun lies side-on to the middle of the room, so you see its full length.
				local gunPos = base + Vector3.new(0, 3.9, 0)
				local face = CFrame.lookAt(gunPos, Vector3.new(roomCenter.X, gunPos.Y, roomCenter.Z))
				local gun = GunModel.display(stats, CFrame.lookAt(gunPos, gunPos + face.RightVector) * CFrame.Angles(0, 0, math.rad(10)), 1.5)
				local bounds = gun:GetBoundingBox()
				gun:PivotTo(gun:GetPivot() + (gunPos - bounds.Position)) -- centred on the table
				gun.Parent = model
				-- Name and price floating above.
				local tag = Kit.part(model, "PriceTag", Vector3.new(1, 1, 1), CFrame.new(base + Vector3.new(0, 5.8, 0)), PURPLE, { collide = false, transparency = 1, shadow = false })
				if tag then
					local billboard = Instance.new("BillboardGui")
					billboard.Size = UDim2.fromScale(4.2, 1.4) -- in studs: small, and smaller far away
					billboard.LightInfluence = 0
					billboard.MaxDistance = 45
					billboard.Parent = tag
					local name = Instance.new("TextLabel")
					name.BackgroundTransparency = 1
					name.Size = UDim2.fromScale(1, 0.55)
					name.Font = Enum.Font.FredokaOne
					name.TextScaled = true
					name.TextColor3 = Color3.new(1, 1, 1)
					name.TextStrokeTransparency = 0.3
					name.Text = item.DisplayName
					name.Parent = billboard
					local price = Instance.new("TextLabel")
					price.BackgroundTransparency = 1
					price.Position = UDim2.fromScale(0, 0.55)
					price.Size = UDim2.fromScale(1, 0.45)
					price.Font = Enum.Font.FredokaOne
					price.TextScaled = true
					local rarity = ShopConfig.rarityOf(item :: any)
					price.TextColor3 = rarity.Color
					price.TextStrokeTransparency = 0.3
					price.Text = if item.Price <= 0 then `{string.upper(rarity.Name)} · FREE` else `{string.upper(rarity.Name)} · {item.Price} coins`
					price.Parent = billboard
				end
			end)
		end
	end

	-- The counter at the back (under the sign) opens the Guns tab of the shop.
	local counter = box(model, "WeaponsCounter", Vector3.new(3.2, 3.5, 12), inRoom(room, ROOM_DEPTH - 3.5, 1.75, 0), METAL_DARK, Enum.Material.DiamondPlate)
	box(model, "WeaponsCounterTop", Vector3.new(3.6, 0.3, 12.4), inRoom(room, ROOM_DEPTH - 3.5, 3.65, 0), PURPLE, Enum.Material.Neon)
	if counter then
		try("weapons prompt", function()
			prompt(counter, "WeaponsCounter", "Browse weapons", "Unlock guns with coins", 12)
		end)
	end
end

--[[
	PRACTICE RANGE room behind the right wall's back doorway: a big glowing
	pad (step on it to go to the range), a glowing line leading to it and
	targets on the walls.
]]
local function buildRangeRoom(model: Model): BasePart?
	local room = RANGE_ROOM
	local doorward = towardDoor(room)
	shell(model, room)
	lamps(model, room, CYAN, 3)
	local signPos = inRoom(room, ROOM_DEPTH - 0.1, 18, 0)
	Props.neonSign(model, "RangeSign", Vector3.new(18, 4.5, 0.4), CFrame.lookAt(signPos, signPos + doorward), "PRACTICE RANGE", CYAN)
	try("range targets", function()
		wallTarget(model, inRoom(room, ROOM_DEPTH, 8.5, 0), doorward, 8)
		for _, sign in { -1, 1 } do
			for _, depth in { 12, 26, 38 } do
				wallTarget(model, inRoom(room, depth, 9, sign * room.halfZ), Vector3.new(0, 0, -sign), 5)
			end
		end
	end)

	-- A glowing line from the doorway to the pad.
	local padDepth = 26
	local lineLength = padDepth - RANGE_PAD_RADIUS - 1.5
	glowPart(model, "RangeFloorLine", Vector3.new(lineLength, 0.1, 0.6), CFrame.new(inRoom(room, lineLength / 2 + 0.5, 0.05, 0)), CYAN)

	local pad = Kit.cylinder(model, "RangePad", inRoom(room, padDepth, 0, 0), 0.3, RANGE_PAD_RADIUS * 2, CYAN, { material = Enum.Material.Neon, collide = false, shadow = false })
	Kit.cylinder(model, "RangePadRing", inRoom(room, padDepth, 0, 0), 0.2, RANGE_PAD_RADIUS * 2 + 1.6, Color3.fromRGB(40, 60, 80), { material = Enum.Material.DiamondPlate, collide = false, shadow = false })
	-- Glowing posts all round it.
	for i = 0, 7 do
		local angle = math.rad(i * 45 + 22.5)
		local post = inRoom(room, padDepth, 2.5, 0) + Vector3.new(math.cos(angle), 0, math.sin(angle)) * (RANGE_PAD_RADIUS + 1.6)
		glowPart(model, "RangePadPost", Vector3.new(0.6, 5, 0.6), CFrame.new(post), CYAN)
	end
	if pad then
		pad:SetAttribute("RangePad", true)
		pad:SetAttribute("PadRadius", RANGE_PAD_RADIUS)
		Props.light(pad, CYAN, 18, 1.5)
		try("range pad sign", function()
			local billboard = Instance.new("BillboardGui")
			billboard.Size = UDim2.fromScale(8, 2.2) -- in studs
			billboard.StudsOffset = Vector3.new(0, 7, 0)
			billboard.MaxDistance = 90
			billboard.LightInfluence = 0
			billboard.Parent = pad
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Size = UDim2.fromScale(1, 1)
			label.Font = Enum.Font.FredokaOne
			label.TextScaled = true
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextStrokeTransparency = 0.2
			label.Text = "PRACTICE RANGE\nstep on the pad"
			label.Parent = billboard
		end)
	end
	return pad
end

-- Hallway ---------------------------------------------------------------------

--[[
	The big screen behind a queue pad: a glowing frame, the "0/2" count, the
	faces of everyone waiting (QueueService adds them) and the mode's name.
	Returns the count label and the box the faces go in.
]]
local function queueScreen(parent: Instance, cframe: CFrame, title: string, color: Color3): (TextLabel?, Frame?)
	local panel = Kit.part(parent, "QueueScreen", Vector3.new(14, 10, 0.4), cframe, Color3.fromRGB(26, 28, 40), { material = Enum.Material.SmoothPlastic })
	if panel == nil then
		return nil, nil
	end
	-- Neon frame round the edge.
	for _, y in { -5.2, 5.2 } do
		Kit.part(parent, "ScreenFrame", Vector3.new(14.8, 0.4, 0.5), cframe * CFrame.new(0, y, -0.1), color, { material = Enum.Material.Neon, shadow = false })
	end
	for _, x in { -7.2, 7.2 } do
		Kit.part(parent, "ScreenFrame", Vector3.new(0.4, 10.8, 0.5), cframe * CFrame.new(x, 0, -0.1), color, { material = Enum.Material.Neon, shadow = false })
	end
	-- The mode's sign hanging above the screen.
	Props.neonSign(parent, "ModeSign", Vector3.new(9, 2.6, 0.4), cframe * CFrame.new(0, 7.2, -0.2), title, Color3.fromRGB(26, 28, 40), color)

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.Parent = panel
	local count = Instance.new("TextLabel")
	count.Name = "Count"
	count.BackgroundTransparency = 1
	count.Size = UDim2.new(1, 0, 0, 110)
	count.Font = Enum.Font.FredokaOne
	count.TextScaled = true
	count.TextColor3 = Color3.new(1, 1, 1)
	count.Text = "0/0"
	count.Parent = gui
	local avatars = Instance.new("Frame")
	avatars.Name = "Avatars"
	avatars.BackgroundTransparency = 1
	avatars.Position = UDim2.fromOffset(10, 115)
	avatars.Size = UDim2.new(1, -20, 0, 230)
	avatars.Parent = gui
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(96, 112)
	grid.CellPadding = UDim2.fromOffset(8, 6)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = avatars
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.BackgroundTransparency = 1
	hint.Position = UDim2.new(0, 0, 1, -52)
	hint.Size = UDim2.new(1, 0, 0, 44)
	hint.Font = Enum.Font.FredokaOne
	hint.TextScaled = true
	hint.TextColor3 = color
	hint.Text = "STAND ON THE PAD TO JOIN"
	hint.Parent = gui
	return count, avatars
end

-- The hallway behind the portal, with queue pads on both sides and the
-- free-for-all pad at the end.
local function buildHallway(model: Model): ({ Pad }, Pad?)
	local startZ = HALL_FRONT - 2
	local endZ = startZ - HALL_LENGTH
	local midZ = (startZ + endZ) / 2
	-- The hallway itself (its own step, so a problem here never stops the pads below).
	try("hallway walls and lights", function()
		box(model, "HallwayFloor", Vector3.new(HALL_HALF_WIDTH * 2, 2, HALL_LENGTH), Vector3.new(ORIGIN.X, ORIGIN.Y - 1, midZ), METAL_DARK, Enum.Material.DiamondPlate)
		box(model, "HallwayCeiling", Vector3.new(HALL_HALF_WIDTH * 2, 2, HALL_LENGTH), Vector3.new(ORIGIN.X, ORIGIN.Y + HALL_HEIGHT_2 + 1, midZ), METAL_DARK)
		for _, side in { -1, 1 } do
			box(model, "HallwayWall", Vector3.new(2, HALL_HEIGHT_2, HALL_LENGTH), Vector3.new(ORIGIN.X + side * (HALL_HALF_WIDTH + 1), ORIGIN.Y + HALL_HEIGHT_2 / 2, midZ), METAL)
			Props.hazardLine(model, Vector3.new(ORIGIN.X + side * 4.5, ORIGIN.Y, startZ - 2), Vector3.new(ORIGIN.X + side * 4.5, ORIGIN.Y, endZ + 2), 1)
		end
		box(model, "HallwayEnd", Vector3.new(HALL_HALF_WIDTH * 2, HALL_HEIGHT_2, 2), Vector3.new(ORIGIN.X, ORIGIN.Y + HALL_HEIGHT_2 / 2, endZ - 1), METAL)
		-- Angled light strips along the ceiling.
		for i = 0, 10 do
			local z = startZ - 6 - i * 8
			for _, side in { -1, 1 } do
				local strip = Vector3.new(ORIGIN.X + side * 9, ORIGIN.Y + HALL_HEIGHT_2 - 0.4, z)
				local part = Kit.part(model, "LightStrip", Vector3.new(8, 0.3, 0.6), CFrame.new(strip) * CFrame.Angles(0, math.rad(side * 25), 0), Color3.fromRGB(255, 120, 150), { material = Enum.Material.Neon, collide = false, shadow = false })
				if i % 3 == 0 then
					Props.light(part, Color3.fromRGB(255, 190, 210), 24, 0.6)
				end
			end
		end
	end)

	-- Pads: left = real players, right = practice with bots.
	local padsFolder = Instance.new("Folder")
	padsFolder.Name = "QueuePads"
	padsFolder.Parent = model
	local layout = {
		{ z = -18, left = { mode = "Duel", title = "1v1 DUEL", color = GREEN }, right = { mode = "Duel", title = "1v1 vs BOT", color = PURPLE } },
		{ z = -42, left = { mode = "TeamDuel", title = "2v2 TEAMS", color = CYAN }, right = { mode = "TeamDuel", title = "2v2 BOTS", color = PURPLE } },
		{ z = -66, left = { mode = "TeamCombat", title = "4v4 SQUADS", color = Color3.fromRGB(255, 170, 70) }, right = { mode = "TeamCombat", title = "4v4 BOTS", color = PURPLE } },
	}
	local pads: { Pad } = {}
	for _, row in layout do
		for _, side in { -1, 1 } do
			local info = if side < 0 then row.left else row.right
			local center = Vector3.new(ORIGIN.X + side * 13, ORIGIN.Y, startZ + row.z)
			local pad, counter = Props.queuePad(padsFolder, center, PAD_RADIUS, info.color, info.title)
			-- The big screen on the wall behind the pad.
			local screenPos = Vector3.new(ORIGIN.X + side * (HALL_HALF_WIDTH - 0.3), ORIGIN.Y + 8.5, center.Z)
			local screenCount: TextLabel?, avatars: Frame? = nil, nil
			try(`queue screen {info.title}`, function()
				screenCount, avatars = queueScreen(model, CFrame.lookAt(screenPos, screenPos + Vector3.new(-side, 0, 0)), info.title, info.color)
			end)
			if pad and counter then
				table.insert(pads, {
					part = pad,
					mode = info.mode,
					bots = side > 0,
					radius = PAD_RADIUS,
					counter = counter,
					screenCount = screenCount,
					avatars = avatars,
				})
			end
		end
	end

	-- FREE FOR ALL at the end of the hallway: step on it to jump straight in.
	local ffaPad: Pad? = nil
	try("free for all pad", function()
		local ffaColor = Color3.fromRGB(255, 80, 120)
		local ffaRadius = 10
		local center = Vector3.new(ORIGIN.X, ORIGIN.Y, endZ + 13)
		local pad, counter = Props.queuePad(padsFolder, center, ffaRadius, ffaColor, "FREE FOR ALL")
		local screenPos = Vector3.new(ORIGIN.X, ORIGIN.Y + 8.5, endZ + 0.3)
		local screenCount: TextLabel?, avatars: Frame? = nil, nil
		try("queue screen FREE FOR ALL", function()
			screenCount, avatars = queueScreen(model, CFrame.lookAt(screenPos, screenPos + Vector3.new(0, 0, 1)), "FREE FOR ALL", ffaColor)
		end)
		local signPos = Vector3.new(ORIGIN.X, ORIGIN.Y + 19, endZ + 0.4)
		Props.neonSign(model, "FreeForAllSign", Vector3.new(18, 4, 0.4), CFrame.lookAt(signPos, signPos + Vector3.new(0, 0, 1)), "JUMP IN ANY TIME", ffaColor)
		if pad and counter then
			ffaPad = {
				part = pad,
				mode = "FreeForAll",
				bots = false,
				radius = ffaRadius,
				counter = counter,
				screenCount = screenCount,
				avatars = avatars,
			}
		end
	end)
	return pads, ffaPad
end

function LobbyBuilder.build(): Lobby
	local old = Workspace:FindFirstChild("Lobby")
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "Lobby"

	table.clear(problems)
	try("hall", function()
		buildHall(model)
	end)
	try("slime decorations", function()
		buildSlime(model)
	end)
	local pads: { Pad } = {}
	local ffaPad: Pad? = nil
	try("hallway and queue pads", function()
		pads, ffaPad = buildHallway(model)
	end)
	try("weapons room", function()
		buildWeaponsRoom(model)
	end)
	try("robux shop room", function()
		buildRobuxRoom(model)
	end)
	try("daily squishy room", function()
		buildDailyRoom(model)
	end)
	local rangePad: BasePart? = nil
	try("practice range room", function()
		rangePad = buildRangeRoom(model)
	end)

	model.Parent = Workspace
	return {
		model = model,
		spawnCFrame = CFrame.lookAt(at(0, 4, 24), at(0, 4, -HALL_Z)),
		origin = ORIGIN,
		pads = pads,
		problems = table.clone(problems),
		rangePad = rangePad,
		ffaPad = ffaPad,
	}
end

return LobbyBuilder
