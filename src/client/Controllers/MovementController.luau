--!strict
--[[
	MovementController
	The fast, slippery movement: double jump, a quick dash, and bouncy
	launch pads.

	Why is this on the client? In Roblox, each player's own computer runs
	their character's physics, so movement feels instant with no lag.
	That's normal and fine for movement; the important stuff (damage,
	coins, purchases) is always decided by the server.
]]

local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Hud = require(script.Parent.HudController)

local MOVE = Config.Movement
local BASE_FOV = 75
local DASH_FOV = 88
local AIR_JUMP_DELAY = 0.2 -- stops one long key press from using both jumps at once
local PAD_COOLDOWN = 0.5

local player = Players.LocalPlayer

local MovementController = {}

local humanoid: Humanoid? = nil
local root: BasePart? = nil
local airJumpsUsed = 0
local lastJumpTime = 0
local lastDashTime = -math.huge
local lastPadTime = 0
local characterConnections: { RBXScriptConnection } = {}

local function isAlive(): boolean
	return humanoid ~= nil and root ~= nil and (humanoid :: Humanoid).Health > 0
end

-- A quick zoom-out of the camera makes the dash feel punchy.
local function fovKick()
	local camera = workspace.CurrentCamera
	camera.FieldOfView = DASH_FOV
	TweenService:Create(camera, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		FieldOfView = BASE_FOV,
	}):Play()
end

local function dash()
	local hum, hrp = humanoid, root
	if not hum or not hrp or hum.Health <= 0 then
		return
	end
	local now = os.clock()
	if now - lastDashTime < MOVE.DashCooldown then
		return
	end

	-- Dash the way you're moving, or forward if you're standing still.
	local direction = hum.MoveDirection
	if direction.Magnitude < 0.1 then
		local look = workspace.CurrentCamera.CFrame.LookVector
		direction = Vector3.new(look.X, 0, look.Z)
	end
	if direction.Magnitude < 0.01 then
		return
	end
	direction = direction.Unit
	lastDashTime = now

	-- LinearVelocity pushes the character sideways for a moment.
	-- "Plane" mode only controls X/Z, so gravity still works normally.
	local attachment = Instance.new("Attachment")
	attachment.Parent = hrp
	local push = Instance.new("LinearVelocity")
	push.Attachment0 = attachment
	push.RelativeTo = Enum.ActuatorRelativeTo.World
	push.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	push.PrimaryTangentAxis = Vector3.xAxis
	push.SecondaryTangentAxis = Vector3.zAxis
	push.PlaneVelocity = Vector2.new(direction.X, direction.Z) * MOVE.DashSpeed
	push.MaxForce = math.huge
	push.Parent = hrp
	Debris:AddItem(push, MOVE.DashDuration)
	Debris:AddItem(attachment, MOVE.DashDuration)

	fovKick()
end

local function onJumpRequest()
	local hum, hrp = humanoid, root
	if not hum or not hrp or hum.Health <= 0 then
		return
	end
	local state = hum:GetState()
	local inAir = state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping
	if not inAir or airJumpsUsed >= MOVE.MaxAirJumps then
		return
	end
	if os.clock() - lastJumpTime < AIR_JUMP_DELAY then
		return
	end
	airJumpsUsed += 1
	hum:ChangeState(Enum.HumanoidStateType.Jumping)
	local velocity = hrp.AssemblyLinearVelocity
	hrp.AssemblyLinearVelocity = Vector3.new(velocity.X, MOVE.DoubleJumpPower, velocity.Z)
end

local function onTouched(hit: BasePart)
	local hrp = root
	if not hrp or not CollectionService:HasTag(hit, "LaunchPad") then
		return
	end
	local now = os.clock()
	if now - lastPadTime < PAD_COOLDOWN then
		return
	end
	lastPadTime = now
	local power = hit:GetAttribute("Power")
	local velocity = hrp.AssemblyLinearVelocity
	hrp.AssemblyLinearVelocity =
		Vector3.new(velocity.X, if typeof(power) == "number" then power else MOVE.LaunchPadPower, velocity.Z)
	airJumpsUsed = 0 -- get your double jump back after a bounce
end

local function onCharacterAdded(character: Model)
	for _, connection in characterConnections do
		connection:Disconnect()
	end
	table.clear(characterConnections)

	local hum = character:WaitForChild("Humanoid") :: Humanoid
	local hrp = character:WaitForChild("HumanoidRootPart") :: BasePart
	humanoid = hum
	root = hrp
	airJumpsUsed = 0
	lastDashTime = -math.huge -- fresh dash every life
	workspace.CurrentCamera.FieldOfView = BASE_FOV

	table.insert(
		characterConnections,
		hum.StateChanged:Connect(function(_, newState)
			if newState == Enum.HumanoidStateType.Landed or newState == Enum.HumanoidStateType.Running then
				airJumpsUsed = 0
			elseif newState == Enum.HumanoidStateType.Jumping then
				lastJumpTime = os.clock()
			end
		end)
	)
	table.insert(characterConnections, hum.Touched:Connect(onTouched))
end

function MovementController.start()
	player.CharacterAdded:Connect(onCharacterAdded)
	player.CharacterRemoving:Connect(function()
		humanoid = nil
		root = nil
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player.Character)
	end

	UserInputService.JumpRequest:Connect(onJumpRequest)

	-- Shift / Q on keyboard, B on a gamepad, plus an on-screen button on phones.
	ContextActionService:BindAction("Dash", function(_, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			dash()
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.LeftShift, Enum.KeyCode.Q, Enum.KeyCode.ButtonB)
	ContextActionService:SetTitle("Dash", "Dash")

	-- Keep the dash meter on the HUD up to date.
	RunService.RenderStepped:Connect(function()
		local ready = if isAlive() then (os.clock() - lastDashTime) / MOVE.DashCooldown else 0
		Hud.setDashReady(ready)
	end)
end

return MovementController
