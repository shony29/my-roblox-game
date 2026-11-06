--!strict
--[[
	CameraController: first-person camera feel.

	Roblox's own first-person camera (CameraMode = LockFirstPerson, set in
	default.project.json) handles aiming, so mouse input is never delayed or
	smoothed. On top of it we add small COSMETIC offsets through
	Humanoid.CameraOffset, which always settle back to zero:
	  * walking / sprinting bob (tiny, so it never hurts aiming)
	  * a short dip when landing, bigger after longer falls
	  * the lower view while sliding
	  * recoil kick (weapons call CameraController.kick)

	Also applies the mouse sensitivity from Config/CameraConfig.
	Field of view is handled by MovementController (sprint/dash widening).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local CameraConfig = require(Config:WaitForChild("CameraConfig"))
local MovementConfig = require(Config:WaitForChild("MovementConfig"))

local player = Players.LocalPlayer

local CameraController = {}
local started = false

-- Cosmetic state, all in studs or degrees, all easing back to zero.
local bobTime = 0
local landingDip = 0
local slideDrop = 0
local recoilPitch = 0 -- degrees, added by kick()
local wasInAir = false
local lastFallSpeed = 0

-- Called by weapons when firing: a small upward kick that recovers by itself.
function CameraController.kick(pitchDegrees: number)
	recoilPitch = math.clamp(recoilPitch + pitchDegrees, 0, 8)
end

local function onRenderStep(dt: number)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root or not root:IsA("BasePart") or humanoid.Health <= 0 then
		return
	end

	local velocity = root.AssemblyLinearVelocity
	local flatSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	local inAir = humanoid.FloorMaterial == Enum.Material.Air

	-- Landing dip: the faster you were falling, the bigger the dip.
	if inAir then
		lastFallSpeed = math.max(-velocity.Y, 0)
	elseif wasInAir then
		landingDip = math.min(lastFallSpeed * CameraConfig.LandingDipPerSpeed, CameraConfig.MaxLandingDip)
	end
	wasInAir = inAir
	local settle = 1 - math.exp(-CameraConfig.LandingRecoverySpeed * dt) -- frame-rate independent easing
	landingDip -= landingDip * settle

	-- Bob only while moving on the ground. Sprinting bobs a little more.
	local bobAmount = 0
	if not inAir and flatSpeed > 1 then
		local sprinting = flatSpeed > MovementConfig.WalkSpeed + 1
		bobAmount = if sprinting then CameraConfig.SprintBobAmount else CameraConfig.WalkBobAmount
		bobTime += dt * CameraConfig.BobSpeed * math.clamp(flatSpeed / MovementConfig.SprintSpeed, 0.5, 1.2)
	end
	local bob = Vector3.new(math.sin(bobTime) * bobAmount, math.abs(math.cos(bobTime)) * bobAmount, 0)

	-- Lower view while sliding (MovementController sets this attribute).
	local slideTarget = if player:GetAttribute("Sliding") == true then MovementConfig.SlideCameraDrop else 0
	slideDrop += (slideTarget - slideDrop) * (1 - math.exp(-12 * dt))

	humanoid.CameraOffset = bob + Vector3.new(0, -landingDip - slideDrop, 0)

	-- Recoil: Roblox's camera has just set this frame's view (we run right
	-- after it), so tilt it up by the current kick. Shots read the camera,
	-- so they follow the kick too. The kick then shrinks every frame, so
	-- the view eases back down on its own.
	if recoilPitch > 0.001 then
		local camera = Workspace.CurrentCamera
		if camera then
			camera.CFrame *= CFrame.Angles(math.rad(recoilPitch), 0, 0)
		end
		recoilPitch -= recoilPitch * (1 - math.exp(-CameraConfig.RecoilRecoverySpeed * dt))
	else
		recoilPitch = 0
	end
end

function CameraController.start()
	if started then
		return
	end
	started = true
	-- The Settings window's saved choice wins (SettingsController keeps it up to date).
	local saved = game:GetService("Players").LocalPlayer:GetAttribute("SettingSensitivity")
	UserInputService.MouseDeltaSensitivity = if typeof(saved) == "number" then saved else CameraConfig.MouseSensitivity
	RunService:BindToRenderStep("SlimeCamera", Enum.RenderPriority.Camera.Value + 1, onRenderStep)
end

return CameraController
