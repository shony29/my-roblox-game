--!strict
--[[
	BlobAnimator (client, visual only): makes every slime feel soft and alive.

	  Idle      gentle breathing, melty lobes wobble, eyes blink
	  Walking   rhythmic squash-and-stretch bounce, lean toward the movement
	  Sprinting stronger lean, faster rhythm, deeper bounce
	  Jumping   stretches tall while rising/falling, wobbles in the air
	  Landing   squishes on impact (harder after bigger falls), springs back
	  Damage    quick jelly ripple and squinting eyes
	  Death     collapses and bursts into the eliminator's topping (Effects/ToppingEffects)

	How: the server (Components/BlobCharacter) builds each blob from pieces
	welded to the character and tags it "Blob". Every frame we move those
	welds and stretch the pieces' meshes, using springs for the bouncy
	follow-through. Frame-rate independent (scaled by frame time), no
	networking, and the hitbox never moves, so aiming and hits are unaffected.

	Intensity: MovementConfig.JiggleIntensity, reduced to a quarter when the
	player's "ReducedMotion" attribute is true (a future Settings option).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ToppingEffects = require(script.Parent.Parent:WaitForChild("Effects"):WaitForChild("ToppingEffects"))
local MovementConfig =
	require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("MovementConfig"))

-- Must match server/Components/BlobCharacter.luau.
local BLOB_TAG = "Blob"
local VISUAL_ATTRIBUTE = "BlobVisual"
local WOBBLE_ATTRIBUTE = "Wobble"
local GROUND_ATTRIBUTE = "GroundY"
local HEIGHT_ATTRIBUTE = "BlobHeight"

local BLINK_TIME = 0.12
local BLINK_MIN_GAP, BLINK_MAX_GAP = 2.5, 5.5
local CLOSED_EYE_HEIGHT = 0.035
local HURT_TIME = 0.25 -- seconds of ripple and squint after taking damage
local COLLAPSE_TIME = 0.22 -- seconds to squash flat when eliminated
local LANDING_MIN_FALL_SPEED = 8 -- studs/s; slower landings don't squish extra

type Piece = { weld: Weld, base: Vector3, mesh: SpecialMesh?, wobble: number, phase: number }
type Eye = { frame: Frame, openSize: UDim2 }
type Blob = {
	model: Model,
	owner: Player?,
	root: BasePart?,
	pieces: { Piece },
	eyes: { Eye },
	groundY: number,
	height: number,
	seed: number,
	lean: Vector3,
	leanVelocity: Vector3,
	squash: number,
	squashVelocity: number,
	stepPhase: number,
	lastVerticalSpeed: number,
	nextBlinkAt: number,
	blinkUntil: number,
	blinking: boolean,
	hurtUntil: number,
	diedAt: number?,
	needsRescan: boolean,
	connections: { RBXScriptConnection },
}

local player = Players.LocalPlayer
local blobs: { [Model]: Blob } = {}
local qualityScale = 1 -- from GraphicsController: Low animates only nearby blobs
local burstCount = 28
local random = Random.new()

local function numberAttribute(instance: Instance, name: string, default: number): number
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else default
end

-- Finds the welded pieces and the eyes. Safe to run again when parts stream in;
-- keeps the resting positions it already recorded.
local function scan(blob: Blob)
	local known: { [Weld]: Piece } = {}
	for _, piece in blob.pieces do
		known[piece.weld] = piece
	end
	local pieces: { Piece } = {}
	local eyes: { Eye } = {}
	for _, descendant in blob.model:GetDescendants() do
		if descendant:IsA("BasePart") and descendant:GetAttribute(VISUAL_ATTRIBUTE) == true then
			local weld = descendant:FindFirstChildOfClass("Weld")
			if weld and weld.Part0 then
				blob.root = weld.Part0
				table.insert(pieces, known[weld] or {
					weld = weld,
					base = weld.C0.Position,
					mesh = descendant:FindFirstChildOfClass("SpecialMesh"),
					wobble = numberAttribute(descendant, WOBBLE_ATTRIBUTE, 0),
					phase = random:NextNumber(0, math.pi * 2),
				})
			end
		elseif descendant:IsA("Frame") and (descendant.Name == "EyeL" or descendant.Name == "EyeR") then
			local openSize = descendant.Size
			for _, eye in blob.eyes do
				if eye.frame == descendant then
					openSize = eye.openSize
				end
			end
			table.insert(eyes, { frame = descendant, openSize = openSize })
		end
	end
	blob.pieces = pieces
	blob.eyes = eyes
	blob.needsRescan = false
end

local function setEyesHeight(blob: Blob, heightScale: number?)
	for _, eye in blob.eyes do
		eye.frame.Size = if heightScale
			then UDim2.new(eye.openSize.X, UDim.new(heightScale, 0))
			else eye.openSize
	end
end

local function onBlobRemoved(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local blob = blobs[instance]
	if blob then
		for _, connection in blob.connections do
			connection:Disconnect()
		end
		blobs[instance] = nil
	end
end

local function watchHealth(blob: Blob)
	local character = blob.model.Parent
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	local lastHealth = humanoid.Health
	table.insert(blob.connections, humanoid.HealthChanged:Connect(function(health: number)
		if health < lastHealth and health > 0 then
			blob.hurtUntil = os.clock() + HURT_TIME
			blob.squashVelocity -= 2.2 -- a quick squish, the springs make it ripple
		end
		lastHealth = health
	end))
	table.insert(blob.connections, humanoid.Died:Connect(function()
		blob.diedAt = os.clock()
		local root = blob.root
		local dome = blob.model:FindFirstChild("Dome")
		if root then
			local position = root.Position
			local color = if dome and dome:IsA("BasePart") then dome.Color else Color3.new(1, 1, 1)
			-- The server tags the eliminated slime with the eliminator's topping
			-- (kill effect); give that a moment to arrive, then burst.
			task.delay(0.1, function()
				local topping = if character then character:GetAttribute("BurstTopping") else nil
				ToppingEffects.play(position, if typeof(topping) == "string" then topping else nil, color, burstCount < 28)
			end)
		end
	end))
end

local function onBlobAdded(instance: Instance)
	if not instance:IsA("Model") or blobs[instance] then
		return
	end
	local model = instance :: Model
	local character = model.Parent
	local blob: Blob = {
		model = model,
		owner = if character and character:IsA("Model") then Players:GetPlayerFromCharacter(character) else nil,
		root = nil,
		pieces = {},
		eyes = {},
		groundY = numberAttribute(model, GROUND_ATTRIBUTE, -2),
		height = numberAttribute(model, HEIGHT_ATTRIBUTE, 4),
		seed = random:NextNumber(0, 100),
		lean = Vector3.zero,
		leanVelocity = Vector3.zero,
		squash = 1,
		squashVelocity = 0,
		stepPhase = 0,
		lastVerticalSpeed = 0,
		nextBlinkAt = os.clock() + random:NextNumber(BLINK_MIN_GAP, BLINK_MAX_GAP),
		blinkUntil = 0,
		blinking = false,
		hurtUntil = 0,
		diedAt = nil,
		needsRescan = true,
		connections = {},
	}
	blobs[model] = blob
	scan(blob)
	watchHealth(blob)
	table.insert(blob.connections, model.DescendantAdded:Connect(function()
		blob.needsRescan = true -- parts can stream in a little later
	end))
end

local function updateFace(blob: Blob, now: number)
	if now < blob.hurtUntil then
		setEyesHeight(blob, 0.06) -- squint
		blob.blinking = true
		blob.blinkUntil = blob.hurtUntil
	elseif blob.blinking and now >= blob.blinkUntil then
		blob.blinking = false
		setEyesHeight(blob, nil)
	elseif not blob.blinking and now >= blob.nextBlinkAt then
		blob.blinking = true
		blob.blinkUntil = now + BLINK_TIME
		blob.nextBlinkAt = now + random:NextNumber(BLINK_MIN_GAP, BLINK_MAX_GAP)
		setEyesHeight(blob, CLOSED_EYE_HEIGHT)
	end
end

local function updateBlob(blob: Blob, dt: number, now: number, cameraPosition: Vector3, firstPerson: boolean, intensity: number)
	if blob.needsRescan then
		scan(blob)
	end
	local root = blob.root
	if not root or not root.Parent then
		return
	end
	if blob.owner == player and firstPerson then
		return -- your own blob is hidden in first person
	end
	if (root.Position - cameraPosition).Magnitude > MovementConfig.JiggleDistance * qualityScale then
		return
	end

	local velocity = root.CFrame:VectorToObjectSpace(root.AssemblyLinearVelocity)
	local flatVelocity = Vector3.new(velocity.X, 0, velocity.Z)
	local speed = flatVelocity.Magnitude
	local grounded = math.abs(velocity.Y) < 1.5

	-- Lean toward the movement; the spring adds lag on starts and a wobble on stops.
	local leanTarget = flatVelocity * MovementConfig.LeanAmount
	if leanTarget.Magnitude > MovementConfig.MaxLean then
		leanTarget = leanTarget.Unit * MovementConfig.MaxLean
	end
	local leanAccel = (leanTarget - blob.lean) * MovementConfig.JiggleStiffness - blob.leanVelocity * MovementConfig.JiggleDamping
	blob.leanVelocity += leanAccel * dt
	blob.lean += blob.leanVelocity * dt

	-- Landing: the faster the fall, the bigger the squish.
	if blob.lastVerticalSpeed < -LANDING_MIN_FALL_SPEED and velocity.Y > -1 then
		local fallSpeed = -blob.lastVerticalSpeed
		blob.squashVelocity -= math.min(fallSpeed * MovementConfig.LandingSquashPerSpeed, 0.35)
			* math.sqrt(MovementConfig.SquashStiffness)
	end
	blob.lastVerticalSpeed = velocity.Y

	-- Stretch while moving up/down; a rhythmic bounce while walking or sprinting.
	local squashTarget = 1 + math.min(math.abs(velocity.Y) * MovementConfig.StretchAmount, MovementConfig.MaxStretch)
	if grounded and speed > 1 then
		local sprinting = speed > MovementConfig.WalkSpeed + 1
		blob.stepPhase += speed * MovementConfig.StepsPerStud * math.pi * 2 * dt
		local bounce = if sprinting then MovementConfig.SprintBounceAmount else MovementConfig.WalkBounceAmount
		squashTarget += math.sin(blob.stepPhase) * bounce
	end
	local squashAccel = (squashTarget - blob.squash) * MovementConfig.SquashStiffness
		- blob.squashVelocity * MovementConfig.SquashDamping
	blob.squashVelocity += squashAccel * dt
	blob.squash += blob.squashVelocity * dt

	local flatten = 1 - math.clamp(speed / MovementConfig.DashSpeed, 0, 1) * MovementConfig.SpeedFlatten
	local breathe = 1 + MovementConfig.BreatheAmount * math.sin(now * MovementConfig.BreatheSpeed + blob.seed)
	local raw = blob.squash * flatten * breathe

	-- Eliminated: squash flat and spread out, like a popped jelly.
	local diedAt = blob.diedAt
	if diedAt then
		local t = math.clamp((now - diedAt) / COLLAPSE_TIME, 0, 1)
		raw = 1 - 0.8 * t
	end

	local stretchY = math.clamp(1 + (raw - 1) * intensity, 0.18, 1.6)
	local stretchXZ = 1 / math.sqrt(stretchY)
	local meshScale = Vector3.new(stretchXZ, stretchY, stretchXZ)
	local lean = blob.lean * intensity

	local hurt = now < blob.hurtUntil
	local wobbleStrength = (0.05 + speed * 0.002) * (if hurt then 4 else 1) * intensity
	local ground = Vector3.new(0, blob.groundY, 0)
	for _, piece in blob.pieces do
		local fromGround = piece.base - ground
		local heightFraction = math.clamp(fromGround.Y / blob.height, 0, 1)
		local position = ground
			+ Vector3.new(fromGround.X * stretchXZ, fromGround.Y * stretchY, fromGround.Z * stretchXZ)
			+ lean * heightFraction
		local scale = meshScale
		if piece.wobble > 0 then
			local p = piece.phase
			local w = piece.wobble * wobbleStrength
			position += Vector3.new(math.sin(now * 3.1 + p), 0.6 * math.sin(now * 2.3 + p * 1.7), math.cos(now * 2.7 + p)) * w
			position += lean * 0.25 * piece.wobble -- loose goo trails a little extra
			local pulse = 1 + 0.035 * piece.wobble * intensity * math.sin(now * 4 + p)
			scale = Vector3.new(meshScale.X * pulse, meshScale.Y / pulse, meshScale.Z * pulse)
		end
		piece.weld.C0 = CFrame.new(position)
		local mesh = piece.mesh
		if mesh then
			mesh.Scale = scale
		end
	end

	updateFace(blob, now)
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
		local dt = math.min(rawDt, 1 / 30) -- keeps the springs stable on slow frames
		local now = os.clock()
		local camera = Workspace.CurrentCamera
		local cameraPosition = if camera then camera.CFrame.Position else Vector3.zero
		local firstPerson = camera ~= nil and (camera.CFrame.Position - camera.Focus.Position).Magnitude < 1
		local quality = player:GetAttribute("GraphicsQuality")
		qualityScale = if quality == "Low" then 0.4 elseif quality == "High" then 1.25 else 1
		burstCount = if quality == "Low" then 10 else 28
		local intensity = MovementConfig.JiggleIntensity * (if player:GetAttribute("ReducedMotion") == true then 0.25 else 1)
		for model, blob in blobs do
			if model.Parent == nil then
				onBlobRemoved(model)
			else
				updateBlob(blob, dt, now, cameraPosition, firstPerson, intensity)
			end
		end
	end)
end

return BlobAnimator
