--!strict
--[[
	MovementService (server)
	========================
	The server is the referee. It:

	  * Sets each player's walk speed and jump power.
	  * Gives each player a random bright color and turns them into a blob.
	  * Decides whether a Dash, Double Jump or Slide is allowed (cooldowns,
	    how many air jumps are left, whether you were running fast enough).
	  * Watches how far and how high every player moves. If someone moves
	    faster or higher than the rules allow (for example with a cheat),
	    the server gently snaps them back to their last fair position.

	Roblox lets each player's own computer move their character (that is why
	movement feels instant). So the server cannot stop a cheater from trying,
	but it can notice and undo it, which is what the checks below do.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MovementConfig = require(ReplicatedStorage.Shared.Movement.MovementConfig)
local MovementNet = require(ReplicatedStorage.Shared.Movement.MovementNet)
local BlobCharacter = require(script.Parent.BlobCharacter)

type PlayerState = {
	-- cooldowns (server time, in seconds)
	lastDashAt: number,
	lastSlideAt: number,
	lastAirJumpAt: number,
	airJumpsUsed: number,

	-- a short time where extra speed is allowed (after an approved dash/slide)
	fastUntil: number,
	fastSpeed: number,

	-- position checks
	lastSamplePosition: Vector3?,
	lastSampleTime: number,
	lastGoodCFrame: CFrame?,
	groundY: number,
	lastGroundedAt: number,
	recentSpeed: number,
	strikes: number,
	skipChecksUntil: number,

	-- spam protection
	requestWindowStart: number,
	requestCount: number,
}

local COLOR_ATTRIBUTE = "BlobColor"
local NEVER = -math.huge

local MovementService = {}

local states: { [Player]: PlayerState } = {}
local remotes = MovementNet.get()

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function newState(): PlayerState
	return {
		lastDashAt = NEVER,
		lastSlideAt = NEVER,
		lastAirJumpAt = NEVER,
		airJumpsUsed = 0,
		fastUntil = NEVER,
		fastSpeed = 0,
		lastSamplePosition = nil,
		lastSampleTime = 0,
		lastGoodCFrame = nil,
		groundY = 0,
		lastGroundedAt = NEVER,
		recentSpeed = 0,
		strikes = 0,
		skipChecksUntil = NEVER,
		requestWindowStart = 0,
		requestCount = 0,
	}
end

-- Returns the living character's Humanoid and root part, or nil.
local function getBody(player: Player): (Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return humanoid, root
	end
	return nil, nil
end

-- How high a jump with a given upward speed goes (physics: v^2 / 2g).
local function jumpHeight(upSpeed: number): number
	return (upSpeed * upSpeed) / (2 * Workspace.Gravity)
end

-- Checks for ground just under the player's feet with a short downward ray.
local function isGrounded(humanoid: Humanoid, root: BasePart): boolean
	local character = root.Parent
	if not character then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local distance = BlobCharacter.groundOffset(humanoid, root) + 1.5
	return Workspace:Raycast(root.Position, Vector3.new(0, -distance, 0), params) ~= nil
end

-- Lets another system (a teleporter, a launch pad...) move a player
-- without the speed checks thinking it was a cheat.
function MovementService.allowFreeMovement(player: Player, seconds: number)
	local state = states[player]
	if state then
		state.skipChecksUntil = math.max(state.skipChecksUntil, now() + seconds)
		state.lastSamplePosition = nil
	end
end

-- Allows extra speed for a short time after an approved dash or slide.
local function grantSpeed(state: PlayerState, speed: number, duration: number)
	local t = now()
	if t >= state.fastUntil then
		state.fastSpeed = speed -- the previous allowance has run out
	else
		state.fastSpeed = math.max(state.fastSpeed, speed) -- e.g. dash during a slide
	end
	state.fastUntil = math.max(state.fastUntil, t + duration + MovementConfig.ActionGraceTime)
end

------------------------------------------------------------------------
-- Deciding whether an action is allowed
------------------------------------------------------------------------

-- Each function returns: allowed?, and the server time it can be used again.
local function handleDash(_player: Player, state: PlayerState): (boolean, number)
	local t = now()
	local readyAt = state.lastDashAt + MovementConfig.DashCooldown
	if t < readyAt - MovementConfig.CooldownLeniency then
		return false, readyAt
	end
	state.lastDashAt = t
	grantSpeed(state, MovementConfig.DashSpeed, MovementConfig.DashDuration)
	return true, t + MovementConfig.DashCooldown
end

local function handleSlide(_player: Player, state: PlayerState): (boolean, number)
	local t = now()
	local readyAt = state.lastSlideAt + MovementConfig.SlideCooldown
	if t < readyAt - MovementConfig.CooldownLeniency then
		return false, readyAt
	end
	-- You must have been on the ground recently and actually running.
	local recentlyGrounded = t - state.lastGroundedAt < 0.4
	local wasRunning = state.recentSpeed >= MovementConfig.SlideMinSpeed * 0.6
	if not (recentlyGrounded and wasRunning) then
		return false, readyAt
	end
	state.lastSlideAt = t
	grantSpeed(state, MovementConfig.SlideStartSpeed, MovementConfig.SlideDuration)
	return true, t + MovementConfig.SlideCooldown
end

local function handleDoubleJump(_player: Player, state: PlayerState): (boolean, number)
	if state.airJumpsUsed >= MovementConfig.MaxAirJumps then
		return false, 0
	end
	state.airJumpsUsed += 1
	state.lastAirJumpAt = now()
	return true, 0
end

local function onRequest(player: Player, action: unknown)
	local state = states[player]
	if not state then
		return
	end

	-- Ignore players who flood the server with requests.
	local t = os.clock()
	if t - state.requestWindowStart >= 1 then
		state.requestWindowStart = t
		state.requestCount = 0
	end
	state.requestCount += 1
	if state.requestCount > MovementConfig.MaxRequestsPerSecond then
		return
	end

	-- Never trust what the client sends: check it is a real action name.
	if typeof(action) ~= "string" or not MovementNet.isAction(action) then
		return
	end
	local humanoid, root = getBody(player)
	if not (humanoid and root) then
		return
	end

	local allowed: boolean, readyAt: number
	if action == "Dash" then
		allowed, readyAt = handleDash(player, state)
	elseif action == "Slide" then
		allowed, readyAt = handleSlide(player, state)
	else
		allowed, readyAt = handleDoubleJump(player, state)
	end

	remotes.Result:FireClient(player, action, allowed, readyAt)
end

------------------------------------------------------------------------
-- Watching movement (the anti-cheat part)
------------------------------------------------------------------------

local function snapBack(state: PlayerState, root: BasePart)
	local good = state.lastGoodCFrame
	if good then
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = good
	end
	state.strikes = 0
	state.lastSamplePosition = good and good.Position or nil
	state.lastSampleTime = now()
end

local function checkPlayer(player: Player, state: PlayerState)
	local humanoid, root = getBody(player)
	if not (humanoid and root) then
		state.lastSamplePosition = nil
		return
	end

	local t = now()
	local position = root.Position
	local grounded = isGrounded(humanoid, root)
	if grounded then
		state.lastGroundedAt = t
		state.groundY = position.Y
		-- Don't reset air jumps right after one was approved (the server may
		-- still see the player on the ground because of lag).
		if t - state.lastAirJumpAt > 0.3 then
			state.airJumpsUsed = 0
		end
	end

	local last = state.lastSamplePosition
	if last == nil or t < state.skipChecksUntil then
		-- Start (or restart) tracking from here.
		state.lastSamplePosition = position
		state.lastSampleTime = t
		state.lastGoodCFrame = root.CFrame
		state.groundY = position.Y
		state.strikes = 0
		return
	end

	local dt = math.max(t - state.lastSampleTime, 1 / 60)
	local flatDistance = Vector3.new(position.X - last.X, 0, position.Z - last.Z).Magnitude
	state.recentSpeed = flatDistance / dt

	-- Too fast?
	local allowedSpeed = humanoid.WalkSpeed
	if allowedSpeed > MovementConfig.WalkSpeed then
		-- The client can change its own WalkSpeed; only trust our value.
		allowedSpeed = MovementConfig.WalkSpeed
	end
	if t < state.fastUntil then
		allowedSpeed = math.max(allowedSpeed, state.fastSpeed)
	end
	local maxDistance = allowedSpeed * MovementConfig.SpeedTolerance * dt + MovementConfig.DistanceSlack
	local tooFast = flatDistance > maxDistance

	-- Too high? (higher than a jump plus the approved air jumps)
	local maxRise = jumpHeight(MovementConfig.JumpPower)
		+ state.airJumpsUsed * jumpHeight(MovementConfig.DoubleJumpPower)
	local rise = position.Y - state.groundY
	local tooHigh = rise > maxRise * MovementConfig.HeightTolerance + MovementConfig.HeightSlack

	state.lastSamplePosition = position
	state.lastSampleTime = t

	if tooFast or tooHigh then
		state.strikes += 1
		if state.strikes >= MovementConfig.StrikesBeforeCorrection then
			snapBack(state, root)
		end
	else
		state.strikes = 0
		state.lastGoodCFrame = root.CFrame
	end
end

------------------------------------------------------------------------
-- Players and characters
------------------------------------------------------------------------

local function onCharacterAdded(player: Player, character: Model)
	local state = states[player]
	if state then
		-- Fresh life: reset cooldowns and give a moment to spawn in.
		local fresh = newState()
		fresh.skipChecksUntil = now() + MovementConfig.SpawnGraceTime
		states[player] = fresh
	end

	local humanoid = character:WaitForChild("Humanoid", 10)
	if humanoid and humanoid:IsA("Humanoid") then
		humanoid.WalkSpeed = MovementConfig.WalkSpeed
		humanoid.UseJumpPower = true
		humanoid.JumpPower = MovementConfig.JumpPower
	end

	local color = player:GetAttribute(COLOR_ATTRIBUTE)
	if typeof(color) ~= "Color3" then
		color = BlobCharacter.randomColor()
		player:SetAttribute(COLOR_ATTRIBUTE, color)
	end
	BlobCharacter.apply(character, color :: Color3)
end

local function onPlayerAdded(player: Player)
	states[player] = newState()
	-- Choose the color once, so it stays the same after respawning.
	player:SetAttribute(COLOR_ATTRIBUTE, BlobCharacter.randomColor())

	player.CharacterAdded:Connect(function(character: Model)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

local started = false

function MovementService.start()
	if started then
		return
	end
	started = true

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player: Player)
		states[player] = nil
	end)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	remotes.Request.OnServerEvent:Connect(onRequest)

	-- Check everyone a few times per second (not every frame, to save work).
	local timer = 0
	RunService.Heartbeat:Connect(function(dt: number)
		timer += dt
		if timer < MovementConfig.CheckInterval then
			return
		end
		timer = 0
		for player, state in states do
			checkPlayer(player, state)
		end
	end)
end

return MovementService
