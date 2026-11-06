--!strict
--[[
	LobbyBuilder: the slime bunker lobby (far away from the arenas).

	  Main hall   dark metal bunker with glowing slime tubes and tanks, pipes,
	              hazard stripes, slime puddles and a central slime pedestal.
	              A big neon SLIME SHOWDOWN sign above a round portal.
	              Right: the DAILY SQUISHY machine. (The shop is a window you
	              open with B or the SHOP button; it has no counter here.)
	  Hallway     through the portal: light strips overhead and glowing queue
	              pads with counters. Left: 1v1, 2v2, 4v4 (real players).
	              Right: practice matches against bots.

	Returns where players appear and the pads (QueueService reads them).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MapKit = require(script.Parent.MapKit)
local LobbyProps = require(script.Parent.LobbyProps)
local GunModel = require(script.Parent.Parent.Components.GunModel)
local WeaponConfig = require(ReplicatedStorage.Shared.Config.WeaponConfig)
local ShopConfig = require(ReplicatedStorage.Shared.Config.ShopConfig)

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
}

local ORIGIN = Vector3.new(0, 300, 700) -- centre of the main hall's floor
local HALL_X, HALL_Z, HALL_HEIGHT = 40, 35, 34 -- half width, half depth, height
local HALL_FRONT = ORIGIN.Z - HALL_Z -- the wall with the sign and the portal
local HALL_LENGTH, HALL_HALF_WIDTH, HALL_HEIGHT_2 = 92, 22, 26 -- the hallway
local PORTAL_RADIUS = 8
local PAD_RADIUS = 6.5
local DOOR_Z, DOOR_HALF, DOOR_HEIGHT = 22, 6, 14 -- the side doorways (weapons room, practice range)

local METAL, METAL_DARK = LobbyProps.METAL, LobbyProps.METAL_DARK
local GREEN, PURPLE, CYAN = LobbyProps.GREEN, LobbyProps.PURPLE, LobbyProps.CYAN

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

local function buildHall(model: Model)
	box(model, "Floor", Vector3.new(HALL_X * 2, 2, HALL_Z * 2), at(0, -1, 0), METAL_DARK, Enum.Material.DiamondPlate)
	box(model, "Walkway", Vector3.new(16, 0.1, HALL_Z * 2 - 4), at(0, 0.05, 0), Color3.fromRGB(92, 96, 104), Enum.Material.DiamondPlate)
	Props.hazardLine(model, at(-8.6, 0, HALL_Z - 2), at(-8.6, 0, -HALL_Z + 2), 1.2)
	Props.hazardLine(model, at(8.6, 0, HALL_Z - 2), at(8.6, 0, -HALL_Z + 2), 1.2)
	box(model, "Ceiling", Vector3.new(HALL_X * 2, 2, HALL_Z * 2), at(0, HALL_HEIGHT + 1, 0), METAL_DARK)
	box(model, "WallBack", Vector3.new(HALL_X * 2, HALL_HEIGHT, 2), at(0, HALL_HEIGHT / 2, HALL_Z + 1), METAL)
	-- Side walls, each with a doorway: WEAPONS room on the left, PRACTICE RANGE on the right.
	local doorFront, doorBack = DOOR_Z - DOOR_HALF, DOOR_Z + DOOR_HALF
	for _, side in { -1, 1 } do
		local x = side * (HALL_X + 1)
		local frontLength = doorFront + HALL_Z
		local backLength = HALL_Z - doorBack
		box(model, "WallSide", Vector3.new(2, HALL_HEIGHT, frontLength), at(x, HALL_HEIGHT / 2, -HALL_Z + frontLength / 2), METAL)
		box(model, "WallSide", Vector3.new(2, HALL_HEIGHT, backLength), at(x, HALL_HEIGHT / 2, doorBack + backLength / 2), METAL)
		box(model, "WallSide", Vector3.new(2, HALL_HEIGHT - DOOR_HEIGHT, DOOR_HALF * 2), at(x, DOOR_HEIGHT + (HALL_HEIGHT - DOOR_HEIGHT) / 2, DOOR_Z), METAL)
		for _, z in { -20, 0 } do
			box(model, "WallPanel", Vector3.new(0.6, 14, 12), at(side * (HALL_X - 0.2), 9, z), METAL_DARK)
		end
		-- Glowing door frame and a sign over the doorway.
		local glow = if side < 0 then PURPLE else CYAN
		for _, z in { doorFront - 0.4, doorBack + 0.4 } do
			box(model, "DoorGlow", Vector3.new(0.8, DOOR_HEIGHT, 0.8), at(side * (HALL_X - 0.2), DOOR_HEIGHT / 2, z), glow, Enum.Material.Neon)
		end
		box(model, "DoorGlow", Vector3.new(0.8, 0.8, DOOR_HALF * 2 + 1.6), at(side * (HALL_X - 0.2), DOOR_HEIGHT + 0.4, DOOR_Z), glow, Enum.Material.Neon)
		local signPos = at(side * (HALL_X - 0.5), DOOR_HEIGHT + 2.9, DOOR_Z)
		Props.neonSign(model, "DoorSign", Vector3.new(16, 4, 0.5), CFrame.lookAt(signPos, signPos + Vector3.new(-side, 0, 0)), if side < 0 then "WEAPONS" else "PRACTICE RANGE", glow)
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

	-- Ceiling lamps.
	for _, x in { -20, 0, 20 } do
		for _, z in { -15, 15 } do
			local lamp = box(model, "CeilingLamp", Vector3.new(10, 0.5, 1.5), at(x, HALL_HEIGHT - 0.3, z), Color3.fromRGB(235, 240, 255), Enum.Material.Neon)
			Props.light(lamp, Color3.fromRGB(220, 235, 255), 34, 0.9)
		end
	end
end

local function buildSlime(model: Model)
	-- Tubes along the walls, a big tank on the right, a pedestal in the middle.
	Props.slimeTube(model, at(-34, 0, -26), 20, 6, GREEN)
	Props.slimeTube(model, at(-26, 0, -29), 16, 5, PURPLE)
	Props.slimeTube(model, at(-35, 0, 12), 18, 6, GREEN)
	Props.slimeTube(model, at(32, 0, -24), 22, 11, GREEN)
	Props.slimeTube(model, at(35, 0, 9), 14, 7, CYAN)
	Props.slimeTube(model, at(24, 0, 30), 14, 7, PURPLE)
	box(model, "PedestalBase", Vector3.new(12, 1, 12), at(0, 0.5, -10), METAL_DARK, Enum.Material.DiamondPlate)
	Props.slimeTube(model, at(0, 1, -10), 9, 5, GREEN)

	-- Pipes: along the side walls (with glowing glass sections) and overhead.
	for _, side in { -1, 1 } do
		Props.pipe(model, at(side * 38.5, 24, -HALL_Z + 2), at(side * 38.5, 24, HALL_Z - 2), 3, GREEN)
		Props.pipe(model, at(side * 38.5, 20.5, -HALL_Z + 2), at(side * 38.5, 20.5, HALL_Z - 2), 2, nil) -- above the door signs
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

local function buildDailyMachine(model: Model)
	-- (Where the shop counter used to be, on the left wall: one more slime tube.)
	Props.slimeTube(model, at(-35, 0, -1), 16, 6, PURPLE)

	-- DAILY SQUISHY machine (right wall): a glass dome with a squishy inside.
	-- It sits in the gap between the big green tank and the cyan tube.
	local dailyZ = -11
	local base = box(model, "DailyBase", Vector3.new(9, 3, 9), at(31, 1.5, dailyZ), METAL_DARK, Enum.Material.DiamondPlate)
	Kit.part(model, "DailyDome", Vector3.new(8, 8, 8), CFrame.new(at(31, 7, dailyZ)), Color3.fromRGB(220, 240, 255), { shape = Enum.PartType.Ball, material = Enum.Material.Glass, transparency = 0.6 })
	local squishy = Kit.part(model, "DailySquishyToy", Vector3.new(4.5, 4.5, 4.5), CFrame.new(at(31, 5.4, dailyZ)), Color3.fromRGB(120, 230, 160), { shape = Enum.PartType.Ball, collide = false })
	Props.light(squishy, GREEN, 12, 1.2)
	local dailySign = at(37, 15, dailyZ)
	Props.neonSign(model, "DailySign", Vector3.new(12, 5, 0.5), CFrame.lookAt(dailySign, dailySign + Vector3.new(-1, 0, 0)), "DAILY SQUISHY", GREEN)
	try("Daily Squishy prompt", function()
		prompt(base, "DailySquishy", "Open", "Daily Squishy")
	end)
	-- "READY!" / "NEXT IN 5h" (each player's own client fills this in).
	try("Daily Squishy sign", function()
	local status = Instance.new("BillboardGui")
	status.Size = UDim2.fromScale(6, 1.5) -- in studs, so it shrinks with distance
	status.StudsOffset = Vector3.new(0, 7.5, 0)
	status.MaxDistance = 80
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

	-- How-to-play board on the front wall, in the clear space between the
	-- purple tube and the portal (so no tube hides it).
	local board = at(-17, 12, -HALL_Z + 0.2)
	Props.neonSign(model, "HowToPlay", Vector3.new(12, 9, 0.4), CFrame.lookAt(board, board + Vector3.new(0, 0, 1)),
		"HOW TO PLAY\nPress PLAY, or stand on a pad\nin the hallway to queue\nLeft door: WEAPONS\nRight door: PRACTICE RANGE", Color3.fromRGB(200, 255, 180))
end

-- WEAPONS room behind the left doorway: every gun on a display table with
-- its price, and a counter that opens the shop's Guns tab.
local function buildWeaponsRoom(model: Model)
	local cx, cz, halfX, halfZ, height = -59, 20, 17, 14, 16
	box(model, "WeaponsFloor", Vector3.new(halfX * 2, 2, halfZ * 2), at(cx, -1, cz), METAL_DARK, Enum.Material.DiamondPlate)
	box(model, "WeaponsCeiling", Vector3.new(halfX * 2, 2, halfZ * 2), at(cx, height + 1, cz), METAL_DARK)
	box(model, "WeaponsWall", Vector3.new(2, height, halfZ * 2 + 2), at(cx - halfX - 1, height / 2, cz), METAL)
	for _, side in { -1, 1 } do
		box(model, "WeaponsWall", Vector3.new(halfX * 2 + 2, height, 2), at(cx, height / 2, cz + side * (halfZ + 1)), METAL)
	end
	-- A big target painted on the floor.
	local rings = { 24, 18, 12, 6, 2 }
	for index, diameter in rings do
		Kit.cylinder(model, "FloorRing", at(cx, 0.02 + index * 0.01, cz), 0.04, diameter, if index % 2 == 1 then Color3.fromRGB(150, 36, 52) else Color3.fromRGB(70, 24, 36), { material = Enum.Material.SmoothPlastic, collide = false, shadow = false })
	end
	-- Lights and the sign on the back wall.
	for _, z in { cz - 7, cz + 7 } do
		local lamp = box(model, "WeaponsLamp", Vector3.new(12, 0.4, 1.2), at(cx, height - 0.3, z), Color3.fromRGB(235, 230, 255), Enum.Material.Neon)
		Props.light(lamp, Color3.fromRGB(230, 215, 255), 30, 1)
	end
	local signPos = at(cx - halfX + 0.1, 11, cz)
	Props.neonSign(model, "WeaponsSign", Vector3.new(16, 4.5, 0.4), CFrame.lookAt(signPos, signPos + Vector3.new(1, 0, 0)), "WEAPONS", PURPLE)

	-- Display tables: four along the back wall, two on each side wall.
	local spots = {
		Vector3.new(cx - halfX + 2.5, 0, cz - 9), Vector3.new(cx - halfX + 2.5, 0, cz - 3),
		Vector3.new(cx - halfX + 2.5, 0, cz + 3), Vector3.new(cx - halfX + 2.5, 0, cz + 9),
		Vector3.new(cx - 6, 0, cz - halfZ + 2.5), Vector3.new(cx + 5, 0, cz - halfZ + 2.5),
		Vector3.new(cx - 6, 0, cz + halfZ - 2.5), Vector3.new(cx + 5, 0, cz + halfZ - 2.5),
	}
	local roomCenter = at(cx, 3.6, cz)
	for index, item in ShopConfig.Weapons do
		local spot = spots[index]
		local stats = WeaponConfig.get(item.WeaponId)
		if spot and stats then
			try(`weapon display {item.WeaponId}`, function()
				local base = at(spot.X, 0, spot.Z)
				box(model, "DisplayTable", Vector3.new(4, 3, 4), base + Vector3.new(0, 1.5, 0), METAL_DARK, Enum.Material.DiamondPlate)
				box(model, "DisplayGlow", Vector3.new(4.3, 0.2, 4.3), base + Vector3.new(0, 3.05, 0), PURPLE, Enum.Material.Neon)
				-- The gun lies side-on to the middle of the room, so you see its full length.
				local gunPos = base + Vector3.new(0, 3.9, 0)
				local face = CFrame.lookAt(gunPos, Vector3.new(roomCenter.X, gunPos.Y, roomCenter.Z))
				local gun = GunModel.display(stats, CFrame.lookAt(gunPos, gunPos + face.RightVector) * CFrame.Angles(0, 0, math.rad(10)), 1.5)
				local box = gun:GetBoundingBox()
				gun:PivotTo(gun:GetPivot() + (gunPos - box.Position)) -- centred on the table
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

	-- The counter: opens the Guns tab of the shop.
	-- (Off to one side, so it doesn't block the doorway.)
	local counter = box(model, "WeaponsCounter", Vector3.new(8, 3.5, 3), at(cx + 6, 1.75, cz - 7), METAL_DARK, Enum.Material.DiamondPlate)
	box(model, "WeaponsCounterTop", Vector3.new(8.4, 0.3, 3.4), at(cx + 6, 3.65, cz - 7), PURPLE, Enum.Material.Neon)
	try("weapons prompt", function()
		prompt(counter, "WeaponsCounter", "Browse weapons", "Unlock guns with coins")
	end)
end

-- PRACTICE RANGE doorway on the right: a small room with a glowing pad.
local function buildRangeDoor(model: Model): BasePart?
	local cx, cz, halfX, halfZ, height = 51, DOOR_Z, 9, 8, 16
	box(model, "RangeRoomFloor", Vector3.new(halfX * 2, 2, halfZ * 2), at(cx, -1, cz), METAL_DARK, Enum.Material.DiamondPlate)
	box(model, "RangeRoomCeiling", Vector3.new(halfX * 2, 2, halfZ * 2), at(cx, height + 1, cz), METAL_DARK)
	box(model, "RangeRoomWall", Vector3.new(2, height, halfZ * 2 + 2), at(cx + halfX + 1, height / 2, cz), METAL)
	for _, side in { -1, 1 } do
		box(model, "RangeRoomWall", Vector3.new(halfX * 2 + 2, height, 2), at(cx, height / 2, cz + side * (halfZ + 1)), METAL)
	end
	local lamp = box(model, "RangeRoomLamp", Vector3.new(8, 0.4, 1.2), at(cx, height - 0.3, cz), Color3.fromRGB(220, 250, 255), Enum.Material.Neon)
	Props.light(lamp, CYAN, 26, 1.2)
	local signPos = at(cx + halfX + 0.1, 11, cz)
	Props.neonSign(model, "RangeSign", Vector3.new(14, 4, 0.4), CFrame.lookAt(signPos, signPos + Vector3.new(-1, 0, 0)), "PRACTICE RANGE", CYAN)

	local pad = Kit.cylinder(model, "RangePad", at(cx + 1, 0, cz), 0.3, 8, CYAN, { material = Enum.Material.Neon, collide = false, shadow = false })
	Kit.cylinder(model, "RangePadRing", at(cx + 1, 0, cz), 0.2, 9.4, Color3.fromRGB(40, 60, 80), { material = Enum.Material.DiamondPlate, collide = false, shadow = false })
	if pad then
		pad:SetAttribute("RangePad", true)
		Props.light(pad, CYAN, 14, 1.5)
		try("range pad sign", function()
			local billboard = Instance.new("BillboardGui")
			billboard.Size = UDim2.fromScale(7, 2) -- in studs
			billboard.StudsOffset = Vector3.new(0, 6, 0)
			billboard.MaxDistance = 80
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

-- The hallway behind the portal, with queue pads on both sides.
local function buildHallway(model: Model): { Pad }
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
		box(model, "Shutter", Vector3.new(16, 14, 0.6), Vector3.new(ORIGIN.X, ORIGIN.Y + 7, endZ + 0.4), Color3.fromRGB(70, 72, 80), Enum.Material.Metal)
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
	return pads
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
	try("Daily Squishy machine", function()
		buildDailyMachine(model)
	end)
	local pads: { Pad } = {}
	try("hallway and queue pads", function()
		pads = buildHallway(model)
	end)
	try("weapons room", function()
		buildWeaponsRoom(model)
	end)
	local rangePad: BasePart? = nil
	try("practice range door", function()
		rangePad = buildRangeDoor(model)
	end)

	model.Parent = Workspace
	return {
		model = model,
		spawnCFrame = CFrame.lookAt(at(0, 4, 24), at(0, 4, -HALL_Z)),
		origin = ORIGIN,
		pads = pads,
		problems = table.clone(problems),
		rangePad = rangePad,
	}
end

return LobbyBuilder
