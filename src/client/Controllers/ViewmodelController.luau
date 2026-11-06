--!strict
--[[
	ViewmodelController: the gun you see in first person.

	In first person Roblox hides your own character, including the gun the
	server welded to your blob (other players still see that one). So we
	show a copy of it in front of the camera, held by a little slime hand.

	How it works:
	  * While the server gives you a gun (an "EquippedGun" on your
	    character), we BUILD our own copy here with the same shared code
	    (Cosmetics/GunBuilder, WeaponSkins and GunUpgrade), from your
	    EquippedWeapon, EquippedSkin and GunLevels. Building it ourselves
	    means it is always complete: copying the server's model could
	    catch it while its pieces were still arriving (a lone big block).
	  * It lives inside the camera, so only you see it, and it is purely
	    visual: shots are decided by WeaponController and the server.
	  * Every frame we place it at a fixed spot in front of the camera,
	    with a gentle sway when you turn and a small bob when you move.
	  * It has a "Muzzle" attachment, so your muzzle flash and tracers
	    start at the tip of the gun you see (never at your face).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MovementConfig = require(Shared:WaitForChild("Config"):WaitForChild("MovementConfig"))
local WeaponConfig = require(Shared:WaitForChild("Config"):WaitForChild("WeaponConfig"))
local ShopConfig = require(Shared:WaitForChild("Config"):WaitForChild("ShopConfig"))
local UpgradeConfig = require(Shared:WaitForChild("Config"):WaitForChild("UpgradeConfig"))
local GunBuilder = require(Shared:WaitForChild("Cosmetics"):WaitForChild("GunBuilder"))
local WeaponSkins = require(Shared:WaitForChild("Cosmetics"):WaitForChild("WeaponSkins"))
local GunUpgrade = require(Shared:WaitForChild("Cosmetics"):WaitForChild("GunUpgrade"))

local GUN_NAME = "EquippedGun" -- made by server/Components/GunModel
local VIEWMODEL_NAME = "Viewmodel"
-- Where the gun sits: right, down and forward from the camera, turned a
-- little toward the crosshair. The gun's back end starts here.
local HOLD_OFFSET = CFrame.new(1.05, -0.95, -1.3) * CFrame.Angles(0, math.rad(3), 0)
-- How much bigger than the real gun the first-person copy is. Bigger = the
-- gun and its skin are easier to see (other players see the normal size).
local VIEWMODEL_SCALE = 1.5
local SWAY_AMOUNT = 0.0016 -- how much the gun lags when you turn (per pixel of mouse movement)
local MAX_SWAY = math.rad(4)
local SWAY_RETURN_SPEED = 10
local EQUIP_TIME = 0.22 -- seconds for a new gun to rise into view
local KICK_STIFFNESS, KICK_DAMPING = 300, 22 -- spring that returns the gun after a shot
local MAX_KICK_PITCH = math.rad(12)

local player = Players.LocalPlayer

local ViewmodelController = {}
local started = false

local viewmodel: Model? = nil
local sway = Vector2.zero -- radians (x = yaw, y = pitch)
local bobTime = 0

-- Animation state (all ease back to rest on their own).
local kickZ, kickZVelocity = 0, 0 -- how far the gun is pushed back after a shot (studs)
local kickPitch = 0 -- how far the barrel tips up after a shot (radians)
local equipStartedAt = 0
local reloading = false
local reloadBlend, sprintBlend = 0, 0

local function destroyViewmodel()
	if viewmodel then
		viewmodel:Destroy()
		viewmodel = nil
	end
end

local function blobColor(): Color3
	local color = player:GetAttribute("BlobColor")
	return if typeof(color) == "Color3" then color else Color3.fromRGB(120, 220, 160)
end

-- Moves the gun forward so its back end (the stock) sits at HOLD_OFFSET
-- (long guns like the sniper then never poke into the camera).
local holdShift = CFrame.new()
local holding = false -- true while the server gives you a gun (matches, practice range)
local builtKey = "" -- what the current copy shows (weapon, skin, level)

-- Builds the gun you're holding, exactly like the server's, plus a slime hand.
local function buildGun(): Model?
	local weaponId = player:GetAttribute("EquippedWeapon")
	local stats = if typeof(weaponId) == "string" then WeaponConfig.get(weaponId) else nil
	if not stats then
		return nil
	end
	local gun = GunBuilder.build(stats, CFrame.new(), { anchored = true })
	local skinId = player:GetAttribute("EquippedSkin")
	WeaponSkins.apply(gun, ShopConfig.getSkin(if typeof(skinId) == "string" then skinId else nil))
	GunUpgrade.apply(gun, UpgradeConfig.parse(player:GetAttribute("GunLevels"))[stats.Id] or 0)
	gun.Name = VIEWMODEL_NAME
	for _, part in gun:GetDescendants() do
		if part:IsA("WeldConstraint") or part:IsA("Weld") then
			part:Destroy() -- moved by hand every frame, not welded to anything
		elseif part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.CastShadow = false
		end
	end

	-- A soft jelly "hand" gripping the gun, in your blob's colour.
	local grip = gun:FindFirstChild("Grip")
	if grip and grip:IsA("BasePart") then
		local hand = Instance.new("Part")
		hand.Name = "SlimeHand"
		hand.Shape = Enum.PartType.Ball
		hand.Size = Vector3.new(0.75, 0.75, 0.75)
		hand.Color = blobColor()
		hand.Material = Enum.Material.SmoothPlastic
		hand.Transparency = 0.1
		hand.Anchored = true
		hand.CanCollide = false
		hand.CanQuery = false
		hand.CanTouch = false
		hand.CastShadow = false
		hand.CFrame = grip.CFrame * CFrame.new(0, -0.05, 0.05)
		hand.Parent = gun
		-- A jelly arm reaching back to the bottom-right corner of the screen,
		-- so it looks like your slime is really holding the gun.
		local armCenter = hand.Position + Vector3.new(0.35, -0.65, 1.5)
		local arm = Instance.new("Part")
		arm.Name = "SlimeArm"
		arm.Size = Vector3.new(0.8, 0.8, 3.4)
		arm.CFrame = CFrame.lookAt(armCenter, armCenter + Vector3.new(0.3, -0.45, 1))
		arm.Color = blobColor()
		arm.Material = Enum.Material.SmoothPlastic
		arm.Transparency = 0.1
		arm.Anchored = true
		arm.CanCollide = false
		arm.CanQuery = false
		arm.CanTouch = false
		arm.CastShadow = false
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = arm
		arm.Parent = gun
	end
	return gun
end

-- Makes (or removes) the copy so it matches what you hold right now.
local function refresh()
	if not holding then
		builtKey = ""
		destroyViewmodel()
		return
	end
	local key = `{player:GetAttribute("EquippedWeapon")}|{player:GetAttribute("EquippedSkin")}|{player:GetAttribute("GunLevels")}`
	if key == builtKey and viewmodel then
		return
	end
	local gun = buildGun()
	if not gun then
		return
	end
	destroyViewmodel()
	builtKey = key

	-- Bigger in first person, so the gun and its skin are clear to see.
	pcall(function()
		gun:ScaleTo(VIEWMODEL_SCALE)
	end)
	-- How far the gun reaches back from its main block (stocks included),
	-- so the whole gun stays in front of the camera.
	local body = gun.PrimaryPart or gun:FindFirstChild("Body")
	local rear = 1
	if body and body:IsA("BasePart") then
		rear = 0
		for _, part in gun:GetDescendants() do
			-- (The arm reaches toward the camera on purpose, so it doesn't count.)
			if part:IsA("BasePart") and part.Name ~= "SlimeArm" then
				rear = math.max(rear, body.CFrame:PointToObjectSpace(part.Position).Z + part.Size.Magnitude / 2)
			end
		end
	end
	holdShift = CFrame.new(0, 0, -rear + 0.5)

	gun.Parent = Workspace.CurrentCamera
	viewmodel = gun
	equipStartedAt = os.clock() -- play the "raise into view" animation
end

local function watchCharacter(character: Model)
	holding = character:FindFirstChild(GUN_NAME) ~= nil
	builtKey = ""
	refresh()
	character.ChildAdded:Connect(function(child: Instance)
		if child.Name == GUN_NAME then
			holding = true
			refresh()
		end
	end)
	character.ChildRemoved:Connect(function(child: Instance)
		if child.Name == GUN_NAME and character:FindFirstChild(GUN_NAME) == nil then
			holding = false
			refresh()
		end
	end)
end

local function onRenderStep(dt: number)
	local model = viewmodel
	local camera = Workspace.CurrentCamera
	if not model or not camera then
		return
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local alive = humanoid ~= nil and humanoid.Health > 0

	-- Only show it while alive and actually in first person.
	local firstPerson = (camera.CFrame.Position - camera.Focus.Position).Magnitude < 1
	if not alive or not firstPerson then
		model:PivotTo(CFrame.new(0, -1e4, 0)) -- tucked away out of sight
		return
	end

	-- Sway: the gun lags a little behind fast turns, then catches up.
	local delta = UserInputService:GetMouseDelta()
	local target = Vector2.new(
		math.clamp(-delta.X * SWAY_AMOUNT, -MAX_SWAY, MAX_SWAY),
		math.clamp(-delta.Y * SWAY_AMOUNT, -MAX_SWAY, MAX_SWAY)
	)
	sway = sway:Lerp(target, 1 - math.exp(-SWAY_RETURN_SPEED * dt))

	-- Bob while moving, matching the camera bob.
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local speed = if root and root:IsA("BasePart")
		then Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
		else 0
	if speed > 1 and humanoid and humanoid.FloorMaterial ~= Enum.Material.Air then
		bobTime += dt * 9 * math.clamp(speed / 26, 0.5, 1.2)
	end
	local bobScale = math.clamp(speed / 26, 0, 1)
	local bob = CFrame.new(math.sin(bobTime) * 0.03 * bobScale, -math.abs(math.cos(bobTime)) * 0.03 * bobScale, 0)

	-- Fire kick: pushed back, then a spring brings it forward; the tip settles down.
	local kickAccel = -kickZ * KICK_STIFFNESS - kickZVelocity * KICK_DAMPING
	kickZVelocity += kickAccel * dt
	kickZ += kickZVelocity * dt
	kickPitch -= kickPitch * (1 - math.exp(-14 * dt))

	-- Equip: rises into view. Reload: dips and rolls. Sprint: lowers and angles away.
	local equipT = math.clamp((os.clock() - equipStartedAt) / EQUIP_TIME, 0, 1)
	local equipEase = 1 - (1 - equipT) ^ 3
	reloadBlend += ((if reloading then 1 else 0) - reloadBlend) * (1 - math.exp(-12 * dt))
	local sprinting = speed > MovementConfig.WalkSpeed + 1 and humanoid ~= nil and humanoid.FloorMaterial ~= Enum.Material.Air
	sprintBlend += ((if sprinting and not reloading then 1 else 0) - sprintBlend) * (1 - math.exp(-10 * dt))

	local pose = CFrame.new(0, -0.7 * (1 - equipEase) - 0.25 * reloadBlend - 0.12 * sprintBlend, kickZ)
		* CFrame.Angles(
			kickPitch - math.rad(25) * reloadBlend - math.rad(10) * sprintBlend,
			math.rad(18) * sprintBlend,
			math.rad(-20) * reloadBlend
		)

	model:PivotTo(camera.CFrame * HOLD_OFFSET * bob * CFrame.Angles(sway.Y, sway.X, 0) * pose * holdShift)
end

-- Called by WeaponController on every shot. `strength` is the weapon's RecoilKick.
function ViewmodelController.kick(strength: number)
	kickZVelocity += 3 + strength * 2
	kickPitch = math.min(kickPitch + math.rad(1 + strength * 1.5), MAX_KICK_PITCH)
end

-- Called by WeaponController whenever the reload state changes.
function ViewmodelController.setReloading(value: boolean)
	reloading = value
end

function ViewmodelController.start()
	if started then
		return
	end
	started = true

	player.CharacterAdded:Connect(watchCharacter)
	player.CharacterRemoving:Connect(function()
		holding = false
		refresh()
	end)
	-- A new gun, skin or upgrade colour: build the copy again.
	for _, attribute in { "EquippedWeapon", "EquippedSkin", "GunLevels" } do
		player:GetAttributeChangedSignal(attribute):Connect(refresh)
	end
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	-- Runs after the camera (and CameraController) so it sits exactly in view.
	RunService:BindToRenderStep("SlimeViewmodel", Enum.RenderPriority.Camera.Value + 2, onRenderStep)
end

-- Where the visible gun's tip is, for tracers. nil if there is no viewmodel.
function ViewmodelController.getMuzzlePosition(): Vector3?
	local model = viewmodel
	if not model then
		return nil
	end
	local muzzle = model:FindFirstChild("Muzzle", true)
	if muzzle and muzzle:IsA("Attachment") then
		return muzzle.WorldPosition
	end
	return nil
end

return ViewmodelController
