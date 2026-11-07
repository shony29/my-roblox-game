--!strict
--[[
	LobbyAnimator: gentle movement for lobby decorations, on this screen only.

	The server marks things in the lobby with attributes, and this script
	moves them every frame (smooth, and nothing goes over the network):

	  on a Model
	    LobbySpin    keep turning round, in degrees per second
	    LobbyBob     float up and down by this many studs
	    LobbySway    turn left and right by up to this many degrees
	    LobbyPivot   (optional) the CFrame to move around
	  on a part
	    LobbyHue     slowly cycle through soft pastel colours
	                 (seconds for one full rainbow)
	  on a slime tube (Map/LobbyProps.slimeTube sets SlimeTube and friends)
	    bubbles rise through the slime (made here, on this screen only),
	    the slime's rounded top wobbles and sloshes, and the glow breathes.

	Examples: the giant gold coin in the ROBUX SHOP spins and bobs, and the
	squishy ball in the Daily Squishy dome bobs, looks around and changes
	colour. Every movement mixes a few slow waves, so nothing looks
	mechanical. Only things near the camera move, so it costs nothing in a
	match.
]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local NEAR = 150 -- studs: further away than this, things stay still
local BOB_PERIOD = 3.4 -- seconds for one float up and down
local SWAY_PERIOD = 7 -- seconds for one look left and right
local PASTEL_SATURATION, PASTEL_BRIGHTNESS = 0.38, 1

type Mover = {
	pivot: CFrame, -- where it rests
	spin: number,
	bob: number,
	sway: number,
	phase: number, -- so two movers never move in step
	parts: { BasePart },
	offsets: { CFrame }, -- each part relative to the pivot
	targets: { CFrame }, -- reused every frame
}

type Tint = { period: number, phase: number }

type Bubble = {
	mesh: SpecialMesh,
	radius: number, -- how far from the tube's middle
	angle: number,
	speed: number, -- studs per second
	phase: number, -- 0..1: where on its way up it starts
}

type Tube = {
	bottom: Vector3, -- middle of the slime's bottom
	level: number, -- how high the slime reaches
	phase: number,
	surfaceRest: CFrame,
	surfaceMesh: SpecialMesh,
	light: PointLight?,
	brightness: number,
	bubbles: { Bubble },
	parts: { BasePart }, -- the surface first, then the bubbles
	targets: { CFrame }, -- reused every frame
}

local BUBBLE_FADE = 0.12 -- share of the way up spent growing in, and shrinking away at the top
local WHITE = Color3.new(1, 1, 1)

local LobbyAnimator = {}
local started = false

local movers: { [Model]: Mover } = {}
local tints: { [BasePart]: Tint } = {}
local tubes: { [Model]: Tube } = {}
local settingUp: { [Model]: boolean } = {}

local function number(instance: Instance, name: string): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else 0
end

local function addPart(mover: Mover, part: BasePart)
	if table.find(mover.parts, part) then
		return
	end
	-- Parts arrive where the server put them, i.e. relative to the resting pivot.
	table.insert(mover.parts, part)
	table.insert(mover.offsets, mover.pivot:ToObjectSpace(part.CFrame))
	table.insert(mover.targets, part.CFrame)
end

local function removePart(mover: Mover, part: BasePart)
	local index = table.find(mover.parts, part)
	if index then
		table.remove(mover.parts, index)
		table.remove(mover.offsets, index)
		table.remove(mover.targets, index)
	end
end

local function registerModel(model: Model)
	if movers[model] then
		return
	end
	local spin, bob, sway = number(model, "LobbySpin"), number(model, "LobbyBob"), number(model, "LobbySway")
	if spin == 0 and bob == 0 and sway == 0 then
		return
	end
	local savedPivot = model:GetAttribute("LobbyPivot")
	local mover: Mover = {
		pivot = if typeof(savedPivot) == "CFrame" then savedPivot else model:GetPivot(),
		spin = spin,
		bob = bob,
		sway = sway,
		phase = math.random() * 10,
		parts = {},
		offsets = {},
		targets = {},
	}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			addPart(mover, descendant)
		end
	end
	-- Pieces can still be arriving from the server.
	model.DescendantAdded:Connect(function(descendant: Instance)
		if descendant:IsA("BasePart") and movers[model] == mover then
			addPart(mover, descendant)
		end
	end)
	model.DescendantRemoving:Connect(function(descendant: Instance)
		if descendant:IsA("BasePart") then
			removePart(mover, descendant)
		end
	end)
	movers[model] = mover
end

-- A tiny glowing ball (a bubble), made on this screen only.
local function makeBubble(model: Model, color: Color3, size: number, at: Vector3): (BasePart, SpecialMesh)
	local part = Instance.new("Part")
	part.Name = "SlimeBubble"
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Neon
	part.Color = color
	part.Size = Vector3.one * size
	part.CFrame = CFrame.new(at)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.zero -- grows in as it starts rising
	mesh.Parent = part
	part.Parent = model
	return part, mesh
end

-- Gets a slime tube moving: finds its surface and light, and adds bubbles.
local function setUpTube(model: Model)
	if tubes[model] or settingUp[model] then
		return
	end
	local bottom = model:GetAttribute("SlimeBottom")
	local level = model:GetAttribute("SlimeLevel")
	local diameter = model:GetAttribute("SlimeDiameter")
	local color = model:GetAttribute("SlimeColor")
	if typeof(bottom) ~= "Vector3" or typeof(level) ~= "number" or typeof(diameter) ~= "number" or typeof(color) ~= "Color3" then
		return
	end
	settingUp[model] = true
	task.spawn(function()
		-- The tube's parts may still be arriving from the server.
		local surface = model:WaitForChild("TubeSurface", 10)
		local core = model:WaitForChild("TubeSlimeCore", 5)
		settingUp[model] = nil
		if surface == nil or not surface:IsA("BasePart") or model.Parent == nil then
			return
		end
		local surfaceMesh = surface:FindFirstChildOfClass("SpecialMesh")
		if surfaceMesh == nil then
			local found = surface:WaitForChild("Mesh", 5)
			surfaceMesh = if found and found:IsA("SpecialMesh") then found else nil
		end
		if surfaceMesh == nil or tubes[model] then
			return
		end
		local light = if core then core:FindFirstChildOfClass("PointLight") else nil
		local tube: Tube = {
			bottom = bottom,
			level = level,
			phase = math.random() * 20,
			surfaceRest = surface.CFrame,
			surfaceMesh = surfaceMesh,
			light = light,
			brightness = if light then light.Brightness else 0,
			bubbles = {},
			parts = { surface },
			targets = { surface.CFrame },
		}
		-- Bubbles rise in the softer outer layer, in front of the bright core
		-- (the core is 60% as wide as the slime).
		local random = Random.new()
		local outer = diameter / 2
		local coreRadius = outer * 0.6
		local ring = outer - coreRadius
		local bubbleColor = color:Lerp(WHITE, 0.65)
		for _ = 1, math.clamp(math.floor(level * diameter / 7), 5, 18) do
			local size = math.clamp(ring * random:NextNumber(0.45, 0.85), 0.22, 0.8)
			local inner = math.min(coreRadius + size * 0.4, outer - size * 0.5)
			local part, mesh = makeBubble(model, bubbleColor, size, bottom)
			table.insert(tube.bubbles, {
				mesh = mesh,
				radius = random:NextNumber(inner, outer - size * 0.5),
				angle = random:NextNumber(0, math.pi * 2),
				speed = random:NextNumber(1.1, 2.6),
				phase = random:NextNumber(),
			})
			table.insert(tube.parts, part)
			table.insert(tube.targets, part.CFrame)
		end
		tubes[model] = tube
	end)
end

-- One frame of a slime tube. A few slow waves are mixed together, so the
-- slime never moves in an obvious loop.
local function updateTube(tube: Tube, now: number)
	local t = now + tube.phase
	-- The rounded top bobs, tips a little from side to side and squishes.
	local lift = math.sin(t * 1.3) * 0.12 + math.sin(t * 2.7 + 1.3) * 0.05
	local tip = CFrame.Angles(math.sin(t * 0.9) * 0.06 + math.sin(t * 2.1) * 0.02, 0, math.sin(t * 1.1 + 0.6) * 0.06)
	tube.targets[1] = tube.surfaceRest * CFrame.new(0, lift, 0) * tip
	tube.surfaceMesh.Scale = Vector3.new(1 + math.sin(t * 1.6) * 0.03, 1 + math.sin(t * 2.2 + 0.4) * 0.25, 1 + math.cos(t * 1.4) * 0.03)
	-- Bubbles rise from the bottom to the top, swaying as they go: they grow
	-- in at the bottom, get a little bigger on the way up and shrink away
	-- into the top.
	local travel = tube.level + 0.4
	for index, bubble in tube.bubbles do
		local progress = (now * bubble.speed / travel + bubble.phase) % 1
		local angle = bubble.angle + math.sin(now * 0.7 + bubble.phase * 7) * 0.35
		local radius = bubble.radius + math.sin(now * 2.4 + bubble.phase * 12) * 0.1
		tube.targets[index + 1] = CFrame.new(tube.bottom + Vector3.new(math.cos(angle) * radius, progress * travel - 0.3, math.sin(angle) * radius))
		local grow = math.clamp(math.min(progress, 1 - progress) / BUBBLE_FADE, 0, 1)
		bubble.mesh.Scale = Vector3.one * (grow * (0.7 + 0.3 * progress))
	end
	Workspace:BulkMoveTo(tube.parts, tube.targets, Enum.BulkMoveMode.FireCFrameChanged)
	-- The glow breathes.
	local light = tube.light
	if light then
		light.Brightness = tube.brightness * (1 + math.sin(t * 1.5) * 0.18)
	end
end

local function consider(instance: Instance)
	if instance:IsA("Model") then
		registerModel(instance)
		if instance:GetAttribute("SlimeTube") == true then
			setUpTube(instance)
		end
	elseif instance:IsA("BasePart") and number(instance, "LobbyHue") > 0 and tints[instance] == nil then
		tints[instance] = { period = number(instance, "LobbyHue"), phase = math.random() }
	end
end

local function watch(lobby: Instance)
	for _, descendant in lobby:GetDescendants() do
		consider(descendant)
	end
	lobby.DescendantAdded:Connect(consider)
end

local function update()
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return
	end
	local eye = camera.CFrame.Position
	local now = os.clock()
	for model, mover in movers do
		if model.Parent == nil then
			movers[model] = nil
			continue
		end
		if #mover.parts == 0 or (mover.pivot.Position - eye).Magnitude > NEAR then
			continue
		end
		local t = now + mover.phase
		local yaw = mover.spin * now + math.sin(t * 2 * math.pi / SWAY_PERIOD) * mover.sway
		local lift = math.sin(t * 2 * math.pi / BOB_PERIOD) * mover.bob
		local target = mover.pivot * CFrame.new(0, lift, 0) * CFrame.Angles(0, math.rad(yaw), 0)
		for index, offset in mover.offsets do
			mover.targets[index] = target * offset
		end
		Workspace:BulkMoveTo(mover.parts, mover.targets, Enum.BulkMoveMode.FireCFrameChanged)
	end
	for part, tint in tints do
		if part.Parent == nil then
			tints[part] = nil
		elseif (part.Position - eye).Magnitude <= NEAR then
			local hue = (now / tint.period + tint.phase) % 1
			part.Color = Color3.fromHSV(hue, PASTEL_SATURATION, PASTEL_BRIGHTNESS)
		end
	end
	for model, tube in tubes do
		if model.Parent == nil then
			tubes[model] = nil
		elseif (tube.bottom - eye).Magnitude <= NEAR then
			updateTube(tube, now)
		end
	end
end

function LobbyAnimator.start()
	if started then
		return
	end
	started = true
	-- The lobby may already be here, or arrive (or be rebuilt) later.
	local lobby = Workspace:FindFirstChild("Lobby")
	if lobby then
		watch(lobby)
	end
	Workspace.ChildAdded:Connect(function(child: Instance)
		if child.Name == "Lobby" then
			watch(child)
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return LobbyAnimator
