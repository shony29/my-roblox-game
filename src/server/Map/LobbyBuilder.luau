--!strict
--[[
	LobbyBuilder: the slime bunker lobby (far away from the arenas).

	  Main hall   dark metal bunker with glowing slime tubes and tanks, pipes,
	              hazard stripes, slime puddles and a central slime pedestal.
	              A big neon SLIME SHOWDOWN sign above a round portal.
	              Left: the SHOP counter. Right: the DAILY SQUISHY machine.
	  Hallway     through the portal: light strips overhead and glowing queue
	              pads with counters. Left: 1v1, 2v2, 4v4 (real players).
	              Right: practice matches against bots.

	Returns where players appear and the pads (QueueService reads them).
]]

local Workspace = game:GetService("Workspace")

local MapKit = require(script.Parent.MapKit)
local LobbyProps = require(script.Parent.LobbyProps)

export type Pad = {
	part: BasePart,
	mode: string, -- ModeConfig mode Id
	bots: boolean, -- true = fill the other slots with bots (practice)
	radius: number,
	counter: TextLabel, -- the "1/2" text above the pad
}

export type Lobby = {
	model: Model,
	spawnCFrame: CFrame,
	origin: Vector3,
	pads: { Pad },
}

local ORIGIN = Vector3.new(0, 300, 700) -- centre of the main hall's floor
local HALL_X, HALL_Z, HALL_HEIGHT = 40, 35, 34 -- half width, half depth, height
local HALL_FRONT = ORIGIN.Z - HALL_Z -- the wall with the sign and the portal
local HALL_LENGTH, HALL_HALF_WIDTH, HALL_HEIGHT_2 = 92, 22, 26 -- the hallway
local PORTAL_RADIUS = 8
local PAD_RADIUS = 6.5

local METAL, METAL_DARK = LobbyProps.METAL, LobbyProps.METAL_DARK
local GREEN, PURPLE, CYAN = LobbyProps.GREEN, LobbyProps.PURPLE, LobbyProps.CYAN

local LobbyBuilder = {}

local function at(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end

local function box(model: Model, name: string, size: Vector3, center: Vector3, color: Color3, material: Enum.Material?)
	return MapKit.part(model, name, size, CFrame.new(center), color, { material = material or Enum.Material.Metal })
end

local function buildHall(model: Model)
	box(model, "Floor", Vector3.new(HALL_X * 2, 2, HALL_Z * 2), at(0, -1, 0), METAL_DARK, Enum.Material.DiamondPlate)
	box(model, "Walkway", Vector3.new(16, 0.1, HALL_Z * 2 - 4), at(0, 0.05, 0), Color3.fromRGB(92, 96, 104), Enum.Material.DiamondPlate)
	LobbyProps.hazardLine(model, at(-8.6, 0, HALL_Z - 2), at(-8.6, 0, -HALL_Z + 2), 1.2)
	LobbyProps.hazardLine(model, at(8.6, 0, HALL_Z - 2), at(8.6, 0, -HALL_Z + 2), 1.2)
	box(model, "Ceiling", Vector3.new(HALL_X * 2, 2, HALL_Z * 2), at(0, HALL_HEIGHT + 1, 0), METAL_DARK)
	box(model, "WallBack", Vector3.new(HALL_X * 2, HALL_HEIGHT, 2), at(0, HALL_HEIGHT / 2, HALL_Z + 1), METAL)
	for _, side in { -1, 1 } do
		box(model, "WallSide", Vector3.new(2, HALL_HEIGHT, HALL_Z * 2), at(side * (HALL_X + 1), HALL_HEIGHT / 2, 0), METAL)
		-- Wall panels and a closed side door with a glowing frame.
		for _, z in { -20, 0, 20 } do
			box(model, "WallPanel", Vector3.new(0.6, 14, 12), at(side * (HALL_X - 0.2), 9, z), METAL_DARK)
		end
		box(model, "SideDoor", Vector3.new(0.8, 12, 9), at(side * (HALL_X - 0.4), 6, 26), Color3.fromRGB(60, 62, 70))
		box(model, "SideDoorGlow", Vector3.new(0.9, 0.6, 10), at(side * (HALL_X - 0.4), 12.3, 26), GREEN, Enum.Material.Neon)
	end
	-- Front wall around the portal opening (opening = 2 x radius wide).
	local gap = PORTAL_RADIUS * 1.05
	local sideWidth = HALL_X - gap
	for _, side in { -1, 1 } do
		box(model, "WallFront", Vector3.new(sideWidth, HALL_HEIGHT, 2), at(side * (gap + sideWidth / 2), HALL_HEIGHT / 2, -HALL_Z - 1), METAL)
	end
	box(model, "WallFrontTop", Vector3.new(gap * 2, HALL_HEIGHT - PORTAL_RADIUS * 2, 2), at(0, PORTAL_RADIUS * 2 + (HALL_HEIGHT - PORTAL_RADIUS * 2) / 2, -HALL_Z - 1), METAL)

	-- The portal: an octagon frame with a glowing purple inner ring.
	local portalCenter = at(0, PORTAL_RADIUS, -HALL_Z + 0.5)
	LobbyProps.octagonFrame(model, portalCenter, PORTAL_RADIUS + 1.2, METAL_DARK, 3, 2.4, Enum.Material.DiamondPlate)
	LobbyProps.octagonFrame(model, portalCenter + Vector3.new(0, 0, 0.8), PORTAL_RADIUS - 0.2, PURPLE, 1, 0.6, Enum.Material.Neon)

	-- The big neon sign above the portal.
	local signPosition = at(0, 25, -HALL_Z + 0.2)
	LobbyProps.neonSign(model, "BunkerSign", Vector3.new(36, 9, 0.6), CFrame.lookAt(signPosition, signPosition + Vector3.new(0, 0, 1)), "SLIME SHOWDOWN", Color3.fromRGB(190, 255, 150))

	-- Ceiling lamps.
	for _, x in { -20, 0, 20 } do
		for _, z in { -15, 15 } do
			local lamp = box(model, "CeilingLamp", Vector3.new(10, 0.5, 1.5), at(x, HALL_HEIGHT - 0.3, z), Color3.fromRGB(235, 240, 255), Enum.Material.Neon)
			LobbyProps.light(lamp, Color3.fromRGB(220, 235, 255), 34, 0.9)
		end
	end
end

local function buildSlime(model: Model)
	-- Tubes along the walls, a big tank on the right, a pedestal in the middle.
	LobbyProps.slimeTube(model, at(-34, 0, -26), 20, 6, GREEN)
	LobbyProps.slimeTube(model, at(-26, 0, -29), 16, 5, PURPLE)
	LobbyProps.slimeTube(model, at(-35, 0, 12), 18, 6, GREEN)
	LobbyProps.slimeTube(model, at(32, 0, -24), 22, 11, GREEN)
	LobbyProps.slimeTube(model, at(34, 0, 14), 14, 7, CYAN)
	LobbyProps.slimeTube(model, at(30, 0, 26), 14, 7, PURPLE)
	box(model, "PedestalBase", Vector3.new(12, 1, 12), at(0, 0.5, -10), METAL_DARK, Enum.Material.DiamondPlate)
	LobbyProps.slimeTube(model, at(0, 1, -10), 9, 5, GREEN)

	-- Pipes: along the side walls (with glowing glass sections) and overhead.
	for _, side in { -1, 1 } do
		LobbyProps.pipe(model, at(side * 38.5, 24, -HALL_Z + 2), at(side * 38.5, 24, HALL_Z - 2), 3, GREEN)
		LobbyProps.pipe(model, at(side * 38.5, 18, -HALL_Z + 2), at(side * 38.5, 18, HALL_Z - 2), 2, nil)
	end
	LobbyProps.pipe(model, at(-HALL_X + 1, 30, -12), at(HALL_X - 1, 30, -12), 2.5, GREEN)
	LobbyProps.pipe(model, at(-HALL_X + 1, 31, 10), at(HALL_X - 1, 31, 10), 2, PURPLE)

	-- Glowing slime puddles.
	LobbyProps.puddle(model, at(-12, 0, 6), 7, GREEN)
	LobbyProps.puddle(model, at(-18, 0, -20), 5, PURPLE)
	LobbyProps.puddle(model, at(6, 0, 18), 6, GREEN)
	LobbyProps.puddle(model, at(14, 0, -22), 4, GREEN)
	LobbyProps.puddle(model, at(22, 0, 4), 5, PURPLE)
end

local function prompt(parent: BasePart, name: string, action: string, object: string)
	local p = Instance.new("ProximityPrompt")
	p.Name = name
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = 0
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	p.Parent = parent
end

local function buildShopAndDaily(model: Model)
	-- SHOP counter (left).
	local counter = box(model, "ShopCounter", Vector3.new(5, 4, 14), at(-31, 2, 0), METAL_DARK, Enum.Material.DiamondPlate)
	box(model, "ShopCounterTop", Vector3.new(5.6, 0.4, 14.6), at(-31, 4.2, 0), CYAN, Enum.Material.Neon)
	box(model, "ShopMachine", Vector3.new(4, 12, 7), at(-37, 6, 0), METAL)
	box(model, "ShopScreen", Vector3.new(0.3, 5, 5), at(-34.9, 8, 0), CYAN, Enum.Material.Neon)
	local shopSign = at(-36, 16, 0)
	LobbyProps.neonSign(model, "ShopSign", Vector3.new(14, 4, 0.5), CFrame.lookAt(shopSign, shopSign + Vector3.new(1, 0, 0)), "SHOP", CYAN)
	prompt(counter, "ShopCounter", "Open Shop", "Guns, squishies & skins")

	-- DAILY SQUISHY machine (right): a glass dome with a squishy inside.
	local base = box(model, "DailyBase", Vector3.new(9, 3, 9), at(31, 1.5, 0), METAL_DARK, Enum.Material.DiamondPlate)
	MapKit.part(model, "DailyDome", Vector3.new(8, 8, 8), CFrame.new(at(31, 7, 0)), Color3.fromRGB(220, 240, 255), { shape = Enum.PartType.Ball, material = Enum.Material.Glass, transparency = 0.6 })
	local squishy = MapKit.part(model, "DailySquishyToy", Vector3.new(4.5, 4.5, 4.5), CFrame.new(at(31, 5.4, 0)), Color3.fromRGB(120, 230, 160), { shape = Enum.PartType.Ball, collide = false })
	LobbyProps.light(squishy, GREEN, 12, 1.2)
	local dailySign = at(37, 15, 0)
	LobbyProps.neonSign(model, "DailySign", Vector3.new(14, 5, 0.5), CFrame.lookAt(dailySign, dailySign + Vector3.new(-1, 0, 0)), "DAILY SQUISHY", GREEN)
	prompt(base, "DailySquishy", "Open", "Daily Squishy")
	-- "READY!" / "NEXT IN 5h" (each player's own client fills this in).
	local status = Instance.new("BillboardGui")
	status.Size = UDim2.fromOffset(200, 50)
	status.StudsOffset = Vector3.new(0, 7.5, 0)
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

	-- How-to-play board on the front wall.
	local board = at(-24, 12, -HALL_Z + 0.2)
	LobbyProps.neonSign(model, "HowToPlay", Vector3.new(12, 9, 0.4), CFrame.lookAt(board, board + Vector3.new(0, 0, 1)),
		"HOW TO PLAY\nWalk through the portal\nStand on a pad to queue\nShop: guns & squishies\nDaily Squishy: free item!", Color3.fromRGB(200, 255, 180))
end

-- The hallway behind the portal, with queue pads on both sides.
local function buildHallway(model: Model): { Pad }
	local startZ = HALL_FRONT - 2
	local endZ = startZ - HALL_LENGTH
	local midZ = (startZ + endZ) / 2
	box(model, "HallwayFloor", Vector3.new(HALL_HALF_WIDTH * 2, 2, HALL_LENGTH), Vector3.new(ORIGIN.X, ORIGIN.Y - 1, midZ), METAL_DARK, Enum.Material.DiamondPlate)
	box(model, "HallwayCeiling", Vector3.new(HALL_HALF_WIDTH * 2, 2, HALL_LENGTH), Vector3.new(ORIGIN.X, ORIGIN.Y + HALL_HEIGHT_2 + 1, midZ), METAL_DARK)
	for _, side in { -1, 1 } do
		box(model, "HallwayWall", Vector3.new(2, HALL_HEIGHT_2, HALL_LENGTH), Vector3.new(ORIGIN.X + side * (HALL_HALF_WIDTH + 1), ORIGIN.Y + HALL_HEIGHT_2 / 2, midZ), METAL)
		LobbyProps.hazardLine(model, Vector3.new(ORIGIN.X + side * 4.5, ORIGIN.Y, startZ - 2), Vector3.new(ORIGIN.X + side * 4.5, ORIGIN.Y, endZ + 2), 1)
	end
	box(model, "HallwayEnd", Vector3.new(HALL_HALF_WIDTH * 2, HALL_HEIGHT_2, 2), Vector3.new(ORIGIN.X, ORIGIN.Y + HALL_HEIGHT_2 / 2, endZ - 1), METAL)
	box(model, "Shutter", Vector3.new(16, 14, 0.6), Vector3.new(ORIGIN.X, ORIGIN.Y + 7, endZ + 0.4), Color3.fromRGB(70, 72, 80), Enum.Material.CorrugatedMetal)
	-- Angled light strips along the ceiling.
	for i = 0, 10 do
		local z = startZ - 6 - i * 8
		for _, side in { -1, 1 } do
			local strip = Vector3.new(ORIGIN.X + side * 9, ORIGIN.Y + HALL_HEIGHT_2 - 0.4, z)
			local part = MapKit.part(model, "LightStrip", Vector3.new(8, 0.3, 0.6), CFrame.new(strip) * CFrame.Angles(0, math.rad(side * 25), 0), Color3.fromRGB(255, 120, 150), { material = Enum.Material.Neon, collide = false, shadow = false })
			if i % 3 == 0 then
				LobbyProps.light(part, Color3.fromRGB(255, 190, 210), 24, 0.6)
			end
		end
	end

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
			local pad, counter = LobbyProps.queuePad(padsFolder, center, PAD_RADIUS, info.color, info.title)
			table.insert(pads, { part = pad, mode = info.mode, bots = side > 0, radius = PAD_RADIUS, counter = counter })
			-- A big poster on the wall behind the pad.
			local posterPosition = Vector3.new(ORIGIN.X + side * (HALL_HALF_WIDTH - 0.3), ORIGIN.Y + 11, center.Z)
			LobbyProps.neonSign(model, "Poster", Vector3.new(14, 9, 0.4), CFrame.lookAt(posterPosition, posterPosition + Vector3.new(-side, 0, 0)), info.title, info.color, Color3.fromRGB(40, 36, 52))
		end
	end
	return pads
end

function LobbyBuilder.build(): Lobby
	local old = Workspace:FindFirstChild("Lobby")
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "Lobby"

	buildHall(model)
	buildSlime(model)
	buildShopAndDaily(model)
	local pads = buildHallway(model)

	model.Parent = Workspace
	return {
		model = model,
		spawnCFrame = CFrame.lookAt(at(0, 4, 24), at(0, 4, -HALL_Z)),
		origin = ORIGIN,
		pads = pads,
	}
end

return LobbyBuilder
