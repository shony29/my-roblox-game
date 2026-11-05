--!strict
--[[
	MovementController (client)
	===========================
	Handles what the player presses and makes it feel instant:

	  * Double jump: press jump again while in the air.
	  * Dash: press Shift (or X on a gamepad, or the on-screen button on mobile).
	  * Slide: press Ctrl or C (or B on a gamepad) while running.

	The client does the move right away so it feels snappy, and at the same
	time tells the server. The server is the referee: it replies with
	"allowed or not" and the real cooldown time. If the server says no, the
	move is cancelled, and if someone cheats anyway the server snaps them back.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MovementConfig = require(Shared:WaitForChild("Config"):WaitForChild("MovementConfig"))
local CameraConfig = require(Shared:WaitForChild("Config"):WaitForChild("CameraConfig"))
local MovementNet = require(Shared:WaitForChild("Net"):WaitForChild("MovementNet"))
local DashIndicator = require(script.Parent.Parent:WaitForChild("UI"):WaitForChild("DashIndicator"))

local DASH_ACTION = "BlobDash"
local SLIDE_ACTION = "BlobSlide"
local SPRINT_ACTION = "BlobSprint"

local player = Players.LocalPlayer
local remotes = MovementNet.get()

-- Everything about the current character.
type CharacterState = {
	humanoid: Humanoid,
	root: BasePart,
	connections: { RBXScriptConnection },

	airJumpsLeft: number,
	leftGroundAt: number,
	jumpedFromGround: boolean, -- false if we walked off a ledge (coyote time applies)
	bufferedJumpAt: number,

	dashing: boolean,
	dashEndsAt: number,
	dashDirection: Vector3,

	sliding: boolean,
	sprinting: boolean,
	slideStartedAt: number,
	slideDirection: Vector3,
}

local current: CharacterState? = nil

-- Cooldowns, in server time, so they match what the server says.
local dashReadyAt = 0
local slideReadyAt = 0
local lastJumpRequestAt = 0
local fovBoost = 0
local sprintHeld = false

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

-- Removes the up/down part of a direction and makes it length 1.
local function flatten(direction: Vector3): Vector3?
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.05 then
		return nil
	end
	return flat.Unit
end

local function cameraForward(): Vector3
	local camera = Workspace.CurrentCamera
	if camera then
		local flat = flatten(camera.CFrame.LookVector)
		if flat then
			return flat
		end
	end
	return Vector3.new(0, 0, -1)
end

local function isOnGround(humanoid: Humanoid): boolean
	return humanoid.FloorMaterial ~= Enum.Material.Air
end

------------------------------------------------------------------------
-- Moves
------------------------------------------------------------------------

local function stopDash(state: CharacterState)
	if not state.dashing then
		return
	end
	state.dashing = false
	-- Ease back to normal speed so the dash doesn't fling you too far.
	local v = state.root.AssemblyLinearVelocity
	local keep = state.dashDirection * MovementConfig.WalkSpeed
	state.root.AssemblyLinearVelocity = Vector3.new(keep.X, v.Y, keep.Z)
end

local function stopSlide(state: CharacterState)
	if not state.sliding then
		return
	end
	state.sliding = false
	state.humanoid.CameraOffset = Vector3.zero
end

local function tryDash()
	local state = current
	if not state or state.humanoid.Health <= 0 then
		return
	end
	if serverNow() < dashReadyAt then
		return -- still cooling down
	end

	-- Dash the way you are walking, or the way the camera faces if standing still.
	local direction = flatten(state.humanoid.MoveDirection) or cameraForward()

	stopSlide(state)
	state.dashing = true
	state.dashEndsAt = os.clock() + MovementConfig.DashDuration
	state.dashDirection = direction
	dashReadyAt = serverNow() + MovementConfig.DashCooldown -- our guess until the server answers
	fovBoost = CameraConfig.DashFovBoost

	remotes.Request:FireServer("Dash")
end

local function trySlide()
	local state = current
	if not state or state.humanoid.Health <= 0 or state.sliding or state.dashing then
		return
	end
	if serverNow() < slideReadyAt then
		return
	end
	if not isOnGround(state.humanoid) then
		return
	end
	local v = state.root.AssemblyLinearVelocity
	local flatVelocity = Vector3.new(v.X, 0, v.Z)
	if flatVelocity.Magnitude < MovementConfig.SlideMinSpeed then
		return -- you need to be running to slide
	end

	state.sliding = true
	state.slideStartedAt = os.clock()
	state.slideDirection = flatVelocity.Unit
	state.humanoid.CameraOffset = Vector3.new(0, -MovementConfig.SlideCameraDrop, 0)
	slideReadyAt = serverNow() + MovementConfig.SlideCooldown

	remotes.Request:FireServer("Slide")
end

local function onJumpRequest()
	local state = current
	if not state or state.humanoid.Health <= 0 then
		return
	end

	-- Holding jump sends many requests in a row; only count fresh presses.
	local t = os.clock()
	local gap = t - lastJumpRequestAt
	lastJumpRequestAt = t
	if gap < MovementConfig.JumpRetapTime then
		return
	end

	-- Jumping out of a slide keeps your speed: the slide just ends.
	if state.sliding then
		stopSlide(state)
		return
	end

	local humanoidState = state.humanoid:GetState()
	local inAir = humanoidState == Enum.HumanoidStateType.Freefall or humanoidState == Enum.HumanoidStateType.Jumping
	if not inAir then
		return
	end

	-- Coyote time: just walked off a ledge without jumping? A normal jump still works.
	if not state.jumpedFromGround and t - state.leftGroundAt < MovementConfig.CoyoteTime then
		state.jumpedFromGround = true
		local velocity = state.root.AssemblyLinearVelocity
		state.root.AssemblyLinearVelocity = Vector3.new(velocity.X, MovementConfig.JumpPower, velocity.Z)
		return
	end

	if t - state.leftGroundAt < MovementConfig.DoubleJumpDelay then
		return
	end
	if state.airJumpsLeft <= 0 then
		-- No air jumps left: remember the press and jump as soon as we land.
		state.bufferedJumpAt = t
		return
	end

	state.airJumpsLeft -= 1
	local v = state.root.AssemblyLinearVelocity
	state.root.AssemblyLinearVelocity = Vector3.new(v.X, MovementConfig.DoubleJumpPower, v.Z)

	remotes.Request:FireServer("DoubleJump")
end

------------------------------------------------------------------------
-- Every physics step: keep dashes and slides going
------------------------------------------------------------------------

-- Sprint while Shift is held and you're moving mostly forward. Stops while
-- sliding or just after firing. WalkSpeed is set on this device only; the
-- server's speed check allows up to SprintSpeed.
local function updateSprint(state: CharacterState)
	local humanoid = state.humanoid
	local lastShot = player:GetAttribute("LastShotAt")
	local recentlyShot = typeof(lastShot) == "number" and os.clock() - lastShot < MovementConfig.SprintShootLockout
	local moveDirection = flatten(humanoid.MoveDirection)
	local movingForward = moveDirection ~= nil and moveDirection:Dot(cameraForward()) > MovementConfig.SprintForwardDot
	state.sprinting = sprintHeld and movingForward and not recentlyShot and not state.sliding and humanoid.Health > 0
	local speed = if state.sprinting then MovementConfig.SprintSpeed else MovementConfig.WalkSpeed
	if humanoid.WalkSpeed ~= speed then
		humanoid.WalkSpeed = speed
	end
end

local function onPreSimulation(_dt: number)
	local state = current
	if not state then
		return
	end
	updateSprint(state)

	if state.dashing then
		if os.clock() >= state.dashEndsAt then
			stopDash(state)
		else
			-- A flat, straight dash (no falling during it, so air dashes work too).
			state.root.AssemblyLinearVelocity = state.dashDirection * MovementConfig.DashSpeed
		end
	end

	if state.sliding then
		local progress = (os.clock() - state.slideStartedAt) / MovementConfig.SlideDuration
		if progress >= 1 then
			stopSlide(state)
		else
			-- Start fast, slow down smoothly towards the end.
			local eased = 1 - (1 - progress) ^ 2
			local speed = MovementConfig.SlideStartSpeed
				+ (MovementConfig.SlideEndSpeed - MovementConfig.SlideStartSpeed) * eased
			local v = state.root.AssemblyLinearVelocity
			local push = state.slideDirection * speed
			state.root.AssemblyLinearVelocity = Vector3.new(push.X, v.Y, push.Z)
		end
	end
end

local function onRenderStep(dt: number)
	-- Field of view: wider while dashing or sprinting, easing back afterwards.
	local camera = Workspace.CurrentCamera
	local state = current
	local target = if state and state.dashing
		then CameraConfig.DashFovBoost
		elseif state and state.sprinting then CameraConfig.SprintFovBoost
		else 0
	fovBoost += (target - fovBoost) * math.min(dt * CameraConfig.FovLerpSpeed, 1)
	if camera then
		camera.FieldOfView = CameraConfig.FieldOfView + fovBoost
	end
end

------------------------------------------------------------------------
-- Server replies
------------------------------------------------------------------------

local function onResult(action: unknown, allowed: unknown, readyAt: unknown)
	if typeof(readyAt) ~= "number" or typeof(allowed) ~= "boolean" then
		return
	end
	local state = current
	if action == "Dash" then
		dashReadyAt = readyAt -- the server's time is the true one
		if not allowed and state then
			stopDash(state)
		end
	elseif action == "Slide" then
		slideReadyAt = readyAt
		if not allowed and state then
			stopSlide(state)
		end
	end
end

------------------------------------------------------------------------
-- Characters
------------------------------------------------------------------------

local function cleanup()
	local state = current
	if state then
		for _, connection in state.connections do
			connection:Disconnect()
		end
	end
	current = nil
end

local function onCharacterAdded(character: Model)
	cleanup()
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not (humanoid and humanoid:IsA("Humanoid") and root and root:IsA("BasePart")) then
		return
	end

	local state: CharacterState = {
		humanoid = humanoid,
		root = root,
		connections = {},
		airJumpsLeft = MovementConfig.MaxAirJumps,
		leftGroundAt = os.clock(),
		jumpedFromGround = false,
		bufferedJumpAt = 0,
		dashing = false,
		dashEndsAt = 0,
		dashDirection = Vector3.zero,
		sliding = false,
		sprinting = false,
		slideStartedAt = 0,
		slideDirection = Vector3.zero,
	}

	table.insert(
		state.connections,
		humanoid.StateChanged:Connect(function(old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
			local wasOnGround = old ~= Enum.HumanoidStateType.Freefall and old ~= Enum.HumanoidStateType.Jumping
			if (new == Enum.HumanoidStateType.Jumping or new == Enum.HumanoidStateType.Freefall) and wasOnGround then
				state.leftGroundAt = os.clock()
				state.jumpedFromGround = new == Enum.HumanoidStateType.Jumping
			elseif new == Enum.HumanoidStateType.Landed or new == Enum.HumanoidStateType.Running then
				state.airJumpsLeft = MovementConfig.MaxAirJumps
				-- Jump buffering: a jump pressed just before landing happens now.
				if new == Enum.HumanoidStateType.Landed and os.clock() - state.bufferedJumpAt < MovementConfig.JumpBuffer then
					state.bufferedJumpAt = 0
					state.humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
				end
			end
		end)
	)
	table.insert(
		state.connections,
		humanoid.Died:Connect(function()
			stopDash(state)
			stopSlide(state)
		end)
	)

	-- A new life starts with the dash ready.
	dashReadyAt = 0
	slideReadyAt = 0
	current = state
end

------------------------------------------------------------------------
-- Start
------------------------------------------------------------------------

local MovementController = {}
local started = false

function MovementController.start()
	if started then
		return
	end
	started = true

	remotes.Result.OnClientEvent:Connect(onResult)

	player.CharacterAdded:Connect(onCharacterAdded)
	player.CharacterRemoving:Connect(cleanup)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end

	-- High priority so Shift dashes instead of toggling Shift Lock.
	ContextActionService:BindActionAtPriority(
		DASH_ACTION,
		function(_name: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
			if inputState == Enum.UserInputState.Begin then
				tryDash()
			end
			return Enum.ContextActionResult.Sink
		end,
		true, -- also make an on-screen button for phones and tablets
		Enum.ContextActionPriority.High.Value,
		table.unpack(MovementConfig.DashKeys)
	)
	ContextActionService:SetTitle(DASH_ACTION, "Dash")

	ContextActionService:BindActionAtPriority(
		SLIDE_ACTION,
		function(_name: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
			if inputState == Enum.UserInputState.Begin then
				trySlide()
			end
			return Enum.ContextActionResult.Sink
		end,
		true,
		Enum.ContextActionPriority.High.Value,
		table.unpack(MovementConfig.SlideKeys)
	)
	ContextActionService:SetTitle(SLIDE_ACTION, "Slide")

	-- Hold to sprint (high priority so Shift doesn't toggle Shift Lock).
	ContextActionService:BindActionAtPriority(
		SPRINT_ACTION,
		function(_name: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
			if inputState == Enum.UserInputState.Begin then
				sprintHeld = true
			elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
				sprintHeld = false
			end
			return Enum.ContextActionResult.Sink
		end,
		false,
		Enum.ContextActionPriority.High.Value,
		table.unpack(MovementConfig.SprintKeys)
	)

	UserInputService.JumpRequest:Connect(onJumpRequest)
	RunService.PreSimulation:Connect(onPreSimulation)
	RunService.RenderStepped:Connect(onRenderStep)

	-- Cooldown badge.
	local playerGui = player:WaitForChild("PlayerGui")
	local indicator = DashIndicator.new(playerGui)
	RunService.RenderStepped:Connect(function()
		local secondsLeft = dashReadyAt - serverNow()
		indicator.update(1 - secondsLeft / MovementConfig.DashCooldown, secondsLeft)
	end)
end

return MovementController
