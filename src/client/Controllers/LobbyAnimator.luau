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

	Examples: the giant gold coin in the ROBUX SHOP spins and bobs, and the
	squishy ball in the Daily Squishy dome bobs, looks around and changes
	colour. Only things near the camera move, so it costs nothing in a match.
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

local LobbyAnimator = {}
local started = false

local movers: { [Model]: Mover } = {}
local tints: { [BasePart]: Tint } = {}

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

local function consider(instance: Instance)
	if instance:IsA("Model") then
		registerModel(instance)
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
