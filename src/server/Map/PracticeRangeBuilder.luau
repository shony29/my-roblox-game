--!strict
--[[
	PracticeRangeBuilder: the practice range, a bright floating island high
	in the sky (far from the lobby and the arenas) for warming up your aim.

	  Deck     where you appear: white tiles, low walls, chunky white towers
	           and a glowing BACK TO LOBBY pad.
	  Lane     a long shooting lane with a coloured stripe every 25 studs
	           (25, 50, 75 ... 175, with distance signs on the walls) and
	           slime targets standing at every distance.
	  Sky      floating bullseye targets all around the deck.

	Every target is a Model whose hit part has the "PracticeTarget"
	attribute. PracticeService pops a target when it's shot and puts it
	back a moment later.

	Like the lobby, each piece is built separately: a piece that fails is
	skipped and reported (problems list) instead of breaking the range.
]]

local Workspace = game:GetService("Workspace")

local MapKit = require(script.Parent.MapKit)
local LobbyProps = require(script.Parent.LobbyProps)

export type Range = {
	model: Model,
	origin: Vector3,
	spawnCFrame: CFrame,
	exitPad: BasePart?,
	problems: { string },
}

local ORIGIN = Vector3.new(0, 500, -900) -- middle of the deck, on its floor
local DECK_X, DECK_Z = 36, 22 -- half width and half depth of the deck
local LANE_HALF, BAND, BAND_COUNT = 14, 25, 7 -- lane half width, stripe length
local LANE_WALL = 16

local WHITE = Color3.fromRGB(246, 248, 252)
local WHITE_2 = Color3.fromRGB(228, 233, 241)
local TRIM = Color3.fromRGB(196, 204, 217)
local CYAN = Color3.fromRGB(90, 220, 255)
local BAND_COLORS = {
	Color3.fromRGB(255, 96, 104),
	Color3.fromRGB(255, 160, 80),
	Color3.fromRGB(255, 222, 90),
	Color3.fromRGB(110, 214, 122),
	Color3.fromRGB(92, 176, 255),
	Color3.fromRGB(176, 120, 255),
	Color3.fromRGB(72, 74, 88),
}
local TARGET_COLORS = { Color3.fromRGB(255, 80, 110), Color3.fromRGB(190, 90, 255), Color3.fromRGB(255, 140, 60) }

local PracticeRangeBuilder = {}

local problems: { string } = {}

local function try(label: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		local text = `{label}: {tostring(err)}`
		table.insert(problems, text)
		warn(`[PracticeRangeBuilder] {text}`)
	end
end

local function at(x: number, y: number, z: number): Vector3
	return ORIGIN + Vector3.new(x, y, z)
end

local function block(parent: Instance, name: string, size: Vector3, center: Vector3, color: Color3, options: MapKit.Options?): Part
	return MapKit.part(parent, name, size, CFrame.new(center), color, options or { material = Enum.Material.SmoothPlastic })
end

-- Text on the front of a thin panel (distance numbers, signs).
local function textPanel(parent: Instance, size: Vector3, cframe: CFrame, text: string, textColor: Color3, panelColor: Color3)
	local panel = MapKit.part(parent, "Sign", size, cframe, panelColor, { shadow = false })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.Parent = panel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = textColor
	label.Text = text
	label.Parent = gui
end

-- The deck: checkered white tiles, low walls, towers and the exit pad.
local function buildDeck(model: Model): BasePart?
	local tileX, tileZ = 9, 11
	for ix = 0, (DECK_X * 2) / tileX - 1 do
		for iz = 0, (DECK_Z * 2) / tileZ - 1 do
			local x = -DECK_X + tileX * (ix + 0.5)
			local z = -DECK_Z + tileZ * (iz + 0.5)
			block(model, "Tile", Vector3.new(tileX, 2, tileZ), at(x, -1, z), if (ix + iz) % 2 == 0 then WHITE else WHITE_2)
		end
	end
	-- Low walls round the back and sides, with a grey cap.
	block(model, "Rim", Vector3.new(DECK_X * 2 + 4, 3, 2), at(0, 1.5, DECK_Z + 1), WHITE)
	block(model, "RimCap", Vector3.new(DECK_X * 2 + 4, 0.4, 2.2), at(0, 3.2, DECK_Z + 1), TRIM)
	for _, side in { -1, 1 } do
		block(model, "Rim", Vector3.new(2, 3, DECK_Z * 2), at(side * (DECK_X + 1), 1.5, 0), WHITE)
		block(model, "RimCap", Vector3.new(2.2, 0.4, DECK_Z * 2), at(side * (DECK_X + 1), 3.2, 0), TRIM)
		-- Front corners next to the lane: waist-high firing line.
		local width = DECK_X - LANE_HALF
		block(model, "FiringLine", Vector3.new(width, 2.5, 1.5), at(side * (LANE_HALF + width / 2), 1.25, -DECK_Z - 0.75), WHITE_2)
		-- Chunky towers at the corners.
		for _, z in { -DECK_Z + 4, DECK_Z - 4 } do
			local x = side * (DECK_X + 7)
			block(model, "Tower", Vector3.new(8, 26, 8), at(x, 3, z), WHITE)
			block(model, "TowerTop", Vector3.new(9, 1, 9), at(x, 16.5, z), TRIM)
			block(model, "TowerBase", Vector3.new(10, 12, 10), at(x, -10, z), WHITE_2)
		end
	end
	-- Glowing decoration squares (like landing pads).
	for _, x in { -18, 18 } do
		MapKit.part(model, "GlowPad", Vector3.new(6, 0.2, 6), CFrame.new(at(x, 0.1, 6)), CYAN, { material = Enum.Material.Neon, collide = false, shadow = false, transparency = 0.2 })
	end
	-- The way back: a glowing pad near the spawn.
	local exitPad = MapKit.part(model, "ExitPad", Vector3.new(7, 0.4, 7), CFrame.new(at(-27, 0.2, 14)), Color3.fromRGB(120, 255, 150), { material = Enum.Material.Neon, collide = false, shadow = false })
	exitPad:SetAttribute("RangeExit", true)
	local sign = Instance.new("BillboardGui")
	sign.Size = UDim2.fromScale(7, 1.9) -- in studs, so it shrinks with distance
	sign.StudsOffset = Vector3.new(0, 4.5, 0)
	sign.LightInfluence = 0
	sign.Parent = exitPad
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.2
	label.Text = "BACK TO LOBBY"
	label.Parent = sign
	return exitPad
end

-- The lane: coloured distance stripes, walls with distance signs, an end wall.
local function buildLane(model: Model)
	local startZ = -DECK_Z
	for i = 1, BAND_COUNT do
		local z0 = startZ - BAND * (i - 1)
		local center = z0 - BAND / 2
		block(model, "LaneStripe", Vector3.new(LANE_HALF * 2, 2, BAND), at(0, -1, center), BAND_COLORS[i])
		for _, side in { -1, 1 } do
			block(model, "LaneWall", Vector3.new(2, LANE_WALL, BAND), at(side * (LANE_HALF + 1), LANE_WALL / 2, center), if i % 2 == 0 then WHITE else WHITE_2)
			block(model, "LaneWallCap", Vector3.new(2.4, 0.6, BAND), at(side * (LANE_HALF + 1), LANE_WALL + 0.3, center), TRIM)
			-- Distance sign on the inside of the wall, facing the shooters.
			local signPos = at(side * (LANE_HALF - 0.1), 7, z0 - 1)
			textPanel(model, Vector3.new(4, 3, 0.3), CFrame.lookAt(signPos, signPos + Vector3.new(-side, 0, 1)), tostring(BAND * i), Color3.new(1, 1, 1), BAND_COLORS[i])
		end
	end
	local endZ = startZ - BAND * BAND_COUNT
	block(model, "LaneEnd", Vector3.new(LANE_HALF * 2 + 4, LANE_WALL, 2), at(0, LANE_WALL / 2, endZ - 1), WHITE)
	-- Big sign over the lane entrance.
	local signPos = at(0, LANE_WALL + 5, startZ)
	LobbyProps.neonSign(model, "RangeSign", Vector3.new(30, 6, 0.6), CFrame.lookAt(signPos, signPos + Vector3.new(0, 0, 1)), "PRACTICE RANGE", Color3.fromRGB(70, 90, 140), WHITE)
end

-- A slime target standing on the lane: base, jelly body and two eyes.
local function slimeTarget(parent: Instance, base: Vector3, color: Color3)
	local target = Instance.new("Model")
	target.Name = "SlimeTarget"
	MapKit.cylinder(target, "Base", base, 0.4, 4.2, Color3.fromRGB(60, 62, 72), { collide = false })
	local body = MapKit.part(target, "Body", Vector3.new(3.6, 3.6, 3.6), CFrame.new(base + Vector3.new(0, 2.2, 0)), color, { shape = Enum.PartType.Ball, collide = false })
	body.CanQuery = true -- bullets hit the body
	body:SetAttribute("PracticeTarget", true)
	for _, x in { -0.6, 0.6 } do
		-- Eyes on the side facing the deck (+Z).
		MapKit.part(target, "Eye", Vector3.new(0.5, 0.7, 0.3), CFrame.new(base + Vector3.new(x, 2.8, 1.75)), Color3.fromRGB(30, 30, 40), { collide = false, shadow = false })
	end
	target.PrimaryPart = body
	target.Parent = parent
end

-- A floating bullseye facing `lookAt`: red and white rings.
local function bullseye(parent: Instance, position: Vector3, lookAt: Vector3, size: number)
	local target = Instance.new("Model")
	target.Name = "Bullseye"
	local facing = CFrame.lookAt(position, lookAt) * CFrame.Angles(0, math.rad(90), 0) -- disc faces `lookAt`
	local rings = {
		{ d = size, color = Color3.new(1, 1, 1) },
		{ d = size * 0.75, color = Color3.fromRGB(235, 50, 60) },
		{ d = size * 0.5, color = Color3.new(1, 1, 1) },
		{ d = size * 0.25, color = Color3.fromRGB(235, 50, 60) },
	}
	for index, ring in rings do
		local disc = MapKit.part(target, if index == 1 then "Board" else "Ring", Vector3.new(0.3, ring.d, ring.d), facing * CFrame.new(0.06 * (index - 1), 0, 0), ring.color, { collide = false, shadow = false })
		disc.Shape = Enum.PartType.Cylinder
		if index == 1 then
			disc.CanQuery = true -- the board is what bullets hit
			disc:SetAttribute("PracticeTarget", true)
			target.PrimaryPart = disc
		end
	end
	target.Parent = parent
end

local function buildTargets(model: Model)
	local folder = Instance.new("Folder")
	folder.Name = "Targets"
	folder.Parent = model
	-- Two slime targets at every distance, shifted so they don't line up.
	for i = 1, BAND_COUNT do
		local z = -DECK_Z - BAND * i + 6
		for index, x in { -6 + (i % 3) * 2, 5 - (i % 2) * 3 } do
			try(`lane target {i}.{index}`, function()
				slimeTarget(folder, at(x, 0, z), TARGET_COLORS[(i + index) % #TARGET_COLORS + 1])
			end)
		end
	end
	-- Floating bullseyes in a ring around the deck, at different heights.
	local center = at(0, 6, 0)
	for i = 0, 11 do
		local angle = math.rad(i * 30 + 15)
		local distance = 55 + (i % 3) * 12
		local position = center + Vector3.new(math.cos(angle) * distance, 6 + (i % 4) * 6, math.sin(angle) * distance)
		-- Skip the ones that would sit inside the lane.
		if not (math.abs(position.X - ORIGIN.X) < LANE_HALF + 4 and position.Z < ORIGIN.Z - DECK_Z) then
			try(`bullseye {i}`, function()
				bullseye(folder, position, center, 5 + (i % 2) * 2)
			end)
		end
	end
end

-- Builds the range (replacing an old one). Returns where players appear.
function PracticeRangeBuilder.build(): Range
	local old = Workspace:FindFirstChild("PracticeRange")
	if old then
		old:Destroy()
	end
	table.clear(problems)
	local model = Instance.new("Model")
	model.Name = "PracticeRange"

	local exitPad: BasePart? = nil
	try("deck", function()
		exitPad = buildDeck(model)
	end)
	try("lane", function()
		buildLane(model)
	end)
	try("targets", function()
		buildTargets(model)
	end)

	model.Parent = Workspace
	return {
		model = model,
		origin = ORIGIN,
		spawnCFrame = CFrame.lookAt(at(0, 4, 12), at(0, 4, -60)),
		exitPad = exitPad,
		problems = table.clone(problems),
	}
end

return PracticeRangeBuilder
