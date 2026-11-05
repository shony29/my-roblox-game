--!strict
--[[
	WeaponController
	Your Splat Blaster: hold click to fire paint, R to reload.

	The client does the *feel* (instant tracer, recoil, ammo counter) so it's
	snappy, then tells the server "I fired from here, this way". The server
	re-checks everything and decides what was actually hit, and it sends
	back the real ammo count whenever it disagrees with ours.
]]

local ContextActionService = game:GetService("ContextActionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Hud = require(script.Parent.HudController)

local WEAPON = Config.Weapon
local PAINT_COLOR = Color3.fromRGB(255, 120, 200)
local VIEWMODEL_OFFSET = CFrame.new(0.9, -0.85, -1.9) -- where the blaster sits on screen

local player = Players.LocalPlayer

local WeaponController = {}

local fireRemote = Remotes.event("Fire")
local reloadRemote = Remotes.event("Reload")

local ammo = WEAPON.MagazineSize
local reloading = false
local triggerHeld = false
local lastShotTime = 0
local recoil = 0 -- jumps up when firing, then settles back to 0

-- All our local effects go in one folder so raycasts can ignore them.
local effectsFolder = Instance.new("Folder")
effectsFolder.Name = "LocalEffects"
effectsFolder.Parent = workspace

------------------------------------------------------------------------
-- The blaster you see in first person (only exists on your screen)
------------------------------------------------------------------------

local function viewmodelPart(name: string, size: Vector3, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

local viewmodel = Instance.new("Model")
viewmodel.Name = "Viewmodel"
local blasterBody = viewmodelPart("Body", Vector3.new(0.45, 0.55, 1.6), Color3.fromRGB(45, 45, 65), viewmodel)
local blasterTank = viewmodelPart("Tank", Vector3.new(0.35, 0.45, 0.6), PAINT_COLOR, viewmodel)
local blasterTip = viewmodelPart("Tip", Vector3.new(0.3, 0.3, 0.25), PAINT_COLOR, viewmodel)
blasterTip.Material = Enum.Material.Neon
viewmodel.PrimaryPart = blasterBody

local function placeViewmodel(cframe: CFrame)
	blasterBody.CFrame = cframe
	blasterTank.CFrame = cframe * CFrame.new(0, 0.45, 0.2)
	blasterTip.CFrame = cframe * CFrame.new(0, 0, -0.9)
end

------------------------------------------------------------------------
-- Effects
------------------------------------------------------------------------

local function drawTracer(from: Vector3, to: Vector3)
	local distance = (to - from).Magnitude
	if distance < 0.1 then
		return
	end
	local tracer = Instance.new("Part")
	tracer.Anchored = true
	tracer.CanCollide = false
	tracer.CanQuery = false
	tracer.CanTouch = false
	tracer.CastShadow = false
	tracer.Material = Enum.Material.Neon
	tracer.Color = PAINT_COLOR
	tracer.Size = Vector3.new(0.15, 0.15, distance)
	tracer.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -distance / 2)
	tracer.Parent = effectsFolder
	TweenService:Create(tracer, TweenInfo.new(0.12), { Transparency = 1 }):Play()
	Debris:AddItem(tracer, 0.15)

	-- A little paint splat where it landed.
	local splat = Instance.new("Part")
	splat.Shape = Enum.PartType.Ball
	splat.Anchored = true
	splat.CanCollide = false
	splat.CanQuery = false
	splat.CanTouch = false
	splat.Material = Enum.Material.Neon
	splat.Color = PAINT_COLOR
	splat.Size = Vector3.one * 0.8
	splat.Position = to
	splat.Parent = effectsFolder
	TweenService:Create(splat, TweenInfo.new(0.3), { Size = Vector3.one * 0.1, Transparency = 1 }):Play()
	Debris:AddItem(splat, 0.35)
end

------------------------------------------------------------------------
-- Shooting
------------------------------------------------------------------------

local function getAliveCharacter(): Model?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if character and humanoid and humanoid.Health > 0 then
		return character
	end
	return nil
end

local function updateHud()
	Hud.setAmmo(ammo, WEAPON.MagazineSize, reloading)
end

local function startReload()
	if reloading or ammo >= WEAPON.MagazineSize or not getAliveCharacter() then
		return
	end
	reloading = true
	updateHud()
	reloadRemote:FireServer() -- the server refills us and sends AmmoChanged when done
end

local function tryFire()
	local character = getAliveCharacter()
	if not character or reloading then
		return
	end
	if ammo <= 0 then
		startReload()
		return
	end
	local now = os.clock()
	if now - lastShotTime < WEAPON.FireInterval then
		return
	end
	lastShotTime = now
	ammo -= 1
	recoil = 1

	-- Aim straight out of the camera, at the crosshair.
	local camera = workspace.CurrentCamera
	local origin = camera.CFrame.Position
	local direction = camera.CFrame.LookVector

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character, effectsFolder, camera }
	local result = workspace:Raycast(origin, direction * WEAPON.Range, params)
	local hitPosition = if result then result.Position else origin + direction * WEAPON.Range

	drawTracer(blasterTip.Position, hitPosition)
	fireRemote:FireServer(origin, direction)

	updateHud()
	if ammo <= 0 then
		startReload()
	end
end

------------------------------------------------------------------------

function WeaponController.start()
	-- Mouse: hold to keep firing. `gameProcessed` is true when clicking on UI (like the shop).
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if not gameProcessed and input.UserInputType == Enum.UserInputType.MouseButton1 then
			triggerHeld = true
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			triggerHeld = false
		end
	end)

	-- Gamepad trigger + an on-screen Fire button on phones.
	ContextActionService:BindAction("Fire", function(_, state: Enum.UserInputState)
		triggerHeld = state == Enum.UserInputState.Begin or state == Enum.UserInputState.Change
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.ButtonR2)
	ContextActionService:SetTitle("Fire", "Fire")

	ContextActionService:BindAction("Reload", function(_, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			startReload()
		end
		return Enum.ContextActionResult.Sink
	end, true, Enum.KeyCode.R, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle("Reload", "Reload")

	-- The server's word on ammo always wins.
	Remotes.event("AmmoChanged").OnClientEvent:Connect(function(serverAmmo: number, serverReloading: boolean)
		ammo = serverAmmo
		reloading = serverReloading
		updateHud()
	end)

	Remotes.event("HitConfirmed").OnClientEvent:Connect(function(killed: boolean)
		Hud.flashHitMarker(killed)
	end)

	-- Draw other players' shots.
	Remotes.event("ShotFired").OnClientEvent:Connect(function(shooter: Player, origin: Vector3, hitPosition: Vector3)
		if shooter ~= player then
			drawTracer(origin, hitPosition)
		end
	end)

	-- Fresh magazine every life.
	player.CharacterAdded:Connect(function()
		ammo = WEAPON.MagazineSize
		reloading = false
		triggerHeld = false
		updateHud()
	end)

	-- Every frame: position the blaster on screen and keep firing while held.
	RunService.RenderStepped:Connect(function(deltaTime)
		recoil = math.max(0, recoil - deltaTime * 10)
		local alive = getAliveCharacter() ~= nil
		local camera = workspace.CurrentCamera
		local wantedParent: Instance? = if alive then camera else nil
		if viewmodel.Parent ~= wantedParent then
			viewmodel.Parent = wantedParent
		end
		if alive then
			local bob = math.sin(os.clock() * 12) * 0.03
			placeViewmodel(
				camera.CFrame * VIEWMODEL_OFFSET * CFrame.new(0, bob, recoil * 0.3) * CFrame.Angles(recoil * 0.12, 0, 0)
			)
		end
		if triggerHeld then
			tryFire()
		end
	end)

	updateHud()
end

return WeaponController
