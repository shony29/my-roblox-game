--!strict
--[[
	BlobAnimator (client, visual only)
	==================================
	Makes every blob feel soft and fluid, on this player's screen only:

	  * Breathing: a slow, gentle swell while standing still.
	  * Stretch and squish: the blob stretches tall while jumping or falling,
	    and squishes flat with a little bounce when it lands.
	  * Trailing wobble: the top of the blob lags behind when you move, then
	    jiggles back when you stop. Fast moves (dash, slide) flatten it.
	  * Melty lobes: the bulges and the dollop on top each wobble a little
	    on their own, so the blob never looks stiff.
	  * Blinking: the eyes blink every few seconds.

	How it works: the server (server/Movement/BlobCharacter.luau) builds each
	blob from pieces welded to the character, and tags it "Blob". Every frame
	we move those welds and stretch the pieces' meshes. Springs (like a
	weight on a spring) give the bouncy, jelly-like follow-through.

	None of this changes where the character really is or what bullets hit
	(the hitbox is a separate box that never moves), so it can't affect
	fairness. Tune it in Shared/Movement/MovementConfig (the JIGGLE section).
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MovementConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Movement"):WaitForChild("MovementConfig"))

-- Must match server/Movement/BlobCharacter.luau.
local BLOB_TAG = "Blob"
local VISUAL_ATTRIBUTE = "BlobVisual"
local WOBBLE_ATTRIBUTE = "Wobble"
local GROUND_ATTRIBUTE = "GroundY"
local HEIGHT_ATTRIBUTE = "BlobHeight"

local BLINK_TIME = 0.12 -- seconds the eyes stay closed
local BLINK_MIN_GAP = 2.5
local BLINK_MAX_GAP = 5.5
local CLOSED_EYE_HEIGHT = 0.035 -- eye height (fraction of the face) while blinking

type Piece = {
	weld: Weld,
	base: Vector3, -- resting position relative to the root
	mesh: SpecialMesh?,
	wobble: number,
	phase: number, -- so each lobe wobbles slightly out of step
}

type Eye = {
	frame: Frame,
	openSize: UDim2,
}

type Blob = {
	model: Model,
	root: BasePart?,
	pieces: { Piece },
	eyes: { Eye },
	groundY: number,
	height: number,
	seed: number,

	-- springs
	lean: Vector3,
	leanVelocity: Vector3,
	squash: number,
	squashVelocity: number,

	-- blinking
	nextBlinkAt: number,
	blinkUntil: number,
	blinking: boolean,

	needsRescan: boolean,
}

local blobs: { [Model]: Blob } = {}
local random = Random.new()

local function numberAttribute(instance: Instance, name: string, default: number): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else default
end

-- Finds the pieces and eyes inside a blob model. Safe to run again when
-- more parts stream in.
local function scan(blob: Blob)
	local pieces: { Piece } = {}
	local eyes: { Eye } = {}
	local root: BasePart? = nil

	for _, descendant in blob.model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute(VISUAL_ATTRIBUTE) == true then
			local weld = descendant:FindFirstChildOfClass("Weld")
			if weld and weld.Part0 then
				root = weld.Part0
				-- Keep the old phase for pieces we already knew about.
				local phase = random:NextNumber(0, math.pi * 2)
				for _, known in blob.pieces do
					if known.weld == weld then
						phase = known.phase
					end
				end
				table.insert(pieces, {
					weld = weld,
					base = weld.C0.Position, -- replaced below if we already knew this piece
					mesh = descendant:FindFirstChildOfClass("SpecialMesh"),
					wobble = numberAttribute(descendant, WOBBLE_ATTRIBUTE, 0),
					phase = phase,
				})
			end
		elseif descendant:IsA("Frame") and (descendant.Name == "EyeL" or descendant.Name == "EyeR") then
			table.insert(eyes, { frame = descendant, openSize = descendant.Size })
		end
	end

	-- Re-scanning must not lose the resting positions we already recorded
	-- (by then the welds hold animated values, not resting ones).
	for _, piece in pieces do
		for _, known in blob.pieces do
			if known.weld == piece.weld then
				piece.base = known.base
			end
		end
	end
	for _, eye in eyes do
		for _, known in blob.eyes do
			if known.frame == eye.frame then
				eye.openSize = known.openSize
			end
		end
	end

	blob.pieces = pieces
	blob.eyes = eyes
	blob.root = root
	blob.needsRescan = false
end

local function onBlobAdded(instance: Instance)
	if not instance:IsA("Model") or blobs[instance] then
		return
	end
	local model = instance :: Model
	local now = os.clock()
	local blob: Blob = {
		model = model,
		root = nil,
		pieces = {},
		eyes = {},
		groundY = numberAttribute(model, GROUND_ATTRIBUTE, -3),
		height = numberAttribute(model, HEIGHT_ATTRIBUTE, 4),
		seed = random:NextNumber(0, 100),
		lean = Vector3.zero,
		leanVelocity = Vector3.zero,
		squash = 1,
		squashVelocity = 0,
		nextBlinkAt = now + random:NextNumber(BLINK_MIN_GAP, BLINK_MAX_GAP),
		blinkUntil = 0,
		blinking = false,
		needsRescan = true,
	}
	blobs[model] = blob
	scan(blob)

	-- With streaming, parts can arrive a little later. Pick them up.
	model.DescendantAdded:Connect(function()
		blob.needsRescan = true
	end)
end

local function onBlobRemoved(instance: Instance)
	if instance:IsA("Model") then
		blobs[instance] = nil
	end
end

-- One step of a spring: pulls `value` toward `target`, with bounce.
local function springNumber(value: number, velocity: number, target: number, stiffness: number, damping: number, dt: number): (number, number)
	local acceleration = (target - value) * stiffness - velocity * damping
	velocity += acceleration * dt
	return value + velocity * dt, velocity
end

local function springVector(value: Vector3, velocity: Vector3, target: Vector3, stiffness: number, damping: number, dt: number): (Vector3, Vector3)
	local acceleration = (target - value) * stiffness - velocity * damping
	velocity += acceleration * dt
	return value + velocity * dt, velocity
end

local function updateBlinking(blob: Blob, now: number)
	if blob.blinking and now >= blob.blinkUntil then
		blob.blinking = false
		for _, eye in blob.eyes do
			eye.frame.Size = eye.openSize
		end
	elseif not blob.blinking and now >= blob.nextBlinkAt then
		blob.blinking = true
		blob.blinkUntil = now + BLINK_TIME
		blob.nextBlinkAt = now + random:NextNumber(BLINK_MIN_GAP, BLINK_MAX_GAP)
		for _, eye in blob.eyes do
			eye.frame.Size = UDim2.new(eye.openSize.X, UDim.new(CLOSED_EYE_HEIGHT, 0))
		end
	end
end

local function updateBlob(blob: Blob, dt: number, now: number, cameraPosition: Vector3)
	if blob.needsRescan then
		scan(blob)
	end
	local root = blob.root
	if not root or not root.Parent then
		return
	end
	if (root.Position - cameraPosition).Magnitude > MovementConfig.JiggleDistance then
		return -- too far away to notice; save the work
	end

	-- How the blob is moving, from its own point of view.
	local velocity = root.CFrame:VectorToObjectSpace(root.AssemblyLinearVelocity)
	local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = flatVelocity.Magnitude

	-- Trailing lean: the top lags behind the way you're moving.
	local leanTarget = -flatVelocity * MovementConfig.LeanAmount
	if leanTarget.Magnitude > MovementConfig.MaxLean then
		leanTarget = leanTarget.Unit * MovementConfig.MaxLean
	end
	blob.lean, blob.leanVelocity = springVector(
		blob.lean,
		blob.leanVelocity,
		leanTarget,
		MovementConfig.JiggleStiffness,
		MovementConfig.JiggleDamping,
		dt
	)

	-- Stretch while moving up or down fast. When you land, the target snaps
	-- back to 1 and the spring overshoots, which is the squish.
	local squashTarget = 1 + math.min(math.abs(velocity.Y) * MovementConfig.StretchAmount, MovementConfig.MaxStretch)
	blob.squash, blob.squashVelocity = springNumber(
		blob.squash,
		blob.squashVelocity,
		squashTarget,
		MovementConfig.SquashStiffness,
		MovementConfig.SquashDamping,
		dt
	)

	local flatten = 1 - math.clamp(speed / MovementConfig.DashSpeed, 0, 1) * MovementConfig.SpeedFlatten
	local breathe = 1 + MovementConfig.BreatheAmount * math.sin(now * MovementConfig.BreatheSpeed + blob.seed)

	-- Taller means thinner and flatter means wider, so the blob keeps its volume.
	local stretchY = math.clamp(blob.squash * flatten * breathe, 0.55, 1.6)
	local stretchXZ = 1 / math.sqrt(stretchY)
	local meshScale = Vector3.new(stretchXZ, stretchY, stretchXZ)

	local ground = Vector3.new(0, blob.groundY, 0)
	local wobbleStrength = 0.05 + speed * 0.002
	for _, piece in blob.pieces do
		local fromGround = piece.base - ground
		local heightFraction = math.clamp(fromGround.Y / blob.height, 0, 1)

		-- Squash/stretch around the floor point, then lean (more at the top).
		local position = ground
			+ Vector3.new(fromGround.X * stretchXZ, fromGround.Y * stretchY, fromGround.Z * stretchXZ)
			+ blob.lean * heightFraction

		local scale = meshScale
		if piece.wobble > 0 then
			local p = piece.phase
			local w = piece.wobble * wobbleStrength
			position += Vector3.new(math.sin(now * 3.1 + p), 0.6 * math.sin(now * 2.3 + p * 1.7), math.cos(now * 2.7 + p)) * w
			-- Loose pieces also trail a little extra, like the goo is catching up.
			position += blob.lean * 0.25 * piece.wobble
			local pulse = 1 + 0.035 * piece.wobble * math.sin(now * 4 + p)
			scale = Vector3.new(meshScale.X * pulse, meshScale.Y / pulse, meshScale.Z * pulse)
		end

		piece.weld.C0 = CFrame.new(position)
		local mesh = piece.mesh
		if mesh then
			mesh.Scale = scale
		end
	end

	updateBlinking(blob, now)
end

local BlobAnimator = {}
local started = false

function BlobAnimator.start()
	if started then
		return
	end
	started = true

	CollectionService:GetInstanceAddedSignal(BLOB_TAG):Connect(onBlobAdded)
	CollectionService:GetInstanceRemovedSignal(BLOB_TAG):Connect(onBlobRemoved)
	for _, instance in CollectionService:GetTagged(BLOB_TAG) do
		task.spawn(onBlobAdded, instance)
	end

	RunService.RenderStepped:Connect(function(rawDt: number)
		-- Keep the springs stable if a frame takes a long time.
		local dt = math.min(rawDt, 1 / 30)
		local now = os.clock()
		local camera = Workspace.CurrentCamera
		local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
		for model, blob in blobs do
			if model.Parent == nil then
				blobs[model] = nil
			else
				updateBlob(blob, dt, now, cameraPosition)
			end
		end
	end)
end

return BlobAnimator
