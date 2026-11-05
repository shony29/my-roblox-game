--!strict
--[[
	WeaponController: runs on each player's own computer.

	It listens to your keys and mouse, asks the server to shoot, and shows
	the effects straight away so shooting feels instant. The server still
	decides what really got hit, then sends back a "hit confirm" for the
	hitmarker and sound.

	Controls:
	  Left mouse  shoot (hold for the automatic rifle)
	  1 / 2 / 3   swap weapon
	  R           reload
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local SharedWeapons = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Weapons")
local WeaponConfig = require(SharedWeapons:WaitForChild("WeaponConfig"))
local WeaponMath = require(SharedWeapons:WaitForChild("WeaponMath"))
local WeaponRemotes = require(SharedWeapons:WaitForChild("WeaponRemotes"))
local HitGroups = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Combat"):WaitForChild("HitGroups"))
local Effects = require(script.Parent.Effects)
local Hud = require(script.Parent.Hud)

type WeaponStats = WeaponConfig.WeaponStats

local SLOT_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
}

local localPlayer = Players.LocalPlayer
local remotes = WeaponRemotes.get()
local rng = Random.new()

-- Our own guess of the weapon state. The server sends the real numbers
-- (see remotes.State), and those always win.
local equipped = WeaponConfig.Order[1]
local ammo: { [string]: number } = {}
local reloading = false
local lastFireTime = 0
local equipTime = 0
local triggerHeld = false

for id, stats in WeaponConfig.Weapons do
	ammo[id] = stats.MagazineSize
end

local function getAliveCharacter(): (Model?, BasePart?)
	local character = localPlayer.Character
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local head = character:FindFirstChild("Head")
	if not humanoid or humanoid.Health <= 0 or not head or not head:IsA("BasePart") then
		return nil, nil
	end
	return character, head :: BasePart
end

-- Where the gun's tip is. Falls back to the head if the gun isn't there yet.
local function getMuzzlePosition(character: Model, fallback: Vector3): Vector3
	local gun = character:FindFirstChild("EquippedGun")
	if gun then
		local muzzle = gun:FindFirstChild("Muzzle", true)
		if muzzle and muzzle:IsA("Attachment") then
			return muzzle.WorldPosition
		end
	end
	return fallback
end

local function refreshHud()
	Hud.setEquipped(equipped)
	Hud.setAmmo(equipped, ammo[equipped] or 0, reloading)
end

local function requestReload()
	local stats = WeaponConfig.get(equipped)
	if not stats or reloading or (ammo[equipped] or 0) >= stats.MagazineSize then
		return
	end
	remotes.Reload:FireServer()
end

local function equip(weaponId: string)
	if weaponId == equipped or not WeaponConfig.get(weaponId) then
		return
	end
	equipped = weaponId
	equipTime = os.clock()
	reloading = false
	remotes.Equip:FireServer(weaponId)
	refreshHud()
end

-- Finds the 3D point under the mouse, ignoring ourselves and our effects.
local function getAimPoint(character: Model, range: number): Vector3
	local camera = workspace.CurrentCamera
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)

	local params = HitGroups.weaponRayParams({ character, Effects.folder })

	local result = workspace:Raycast(ray.Origin, ray.Direction * range, params)
	if result then
		return result.Position
	end
	return ray.Origin + ray.Direction * range
end

local function tryFire()
	local stats = WeaponConfig.get(equipped)
	local character, head = getAliveCharacter()
	if not stats or not character or not head then
		return
	end

	local now = os.clock()
	if now - lastFireTime < 1 / stats.FireRate or now - equipTime < WeaponConfig.SwapTime then
		return
	end
	if reloading then
		return
	end
	if (ammo[equipped] or 0) <= 0 then
		requestReload()
		return
	end

	lastFireTime = now
	ammo[equipped] -= 1

	-- Shots start from the head and fly toward whatever the mouse points at.
	-- This works in first person and third person.
	local origin = head.Position
	local direction = getAimPoint(character, stats.MaxRange) - origin
	if direction.Magnitude < 0.001 then
		return
	end
	remotes.Fire:FireServer(equipped, origin, direction.Unit)

	-- Show the shot right away (our best guess; the server has the final say).
	local muzzle = getMuzzlePosition(character, origin)
	Effects.muzzleFlash(muzzle, stats.TracerColor)
	Effects.playSound(stats.FireSoundId, 0.6, 1)

	local params = HitGroups.weaponRayParams({ character, Effects.folder })
	for _ = 1, stats.Pellets do
		local pelletDirection = WeaponMath.applySpread(direction, stats.Spread, rng)
		local result = workspace:Raycast(origin, pelletDirection * stats.MaxRange, params)
		local endPoint = if result then result.Position else origin + pelletDirection * stats.MaxRange
		Effects.tracer(muzzle, endPoint, stats.TracerColor, stats.TracerWidth)
		if result then
			Effects.impact(endPoint)
		end
	end

	refreshHud()
end

-- Server says: here is your real ammo.
local function onState(weaponIdRaw: unknown, ammoRaw: unknown, reloadingRaw: unknown)
	if typeof(weaponIdRaw) ~= "string" or typeof(ammoRaw) ~= "number" or typeof(reloadingRaw) ~= "boolean" then
		return
	end
	local weaponId = weaponIdRaw :: string
	local serverAmmo = ammoRaw :: number
	local serverReloading = reloadingRaw :: boolean
	if weaponId == equipped and not reloading and not serverReloading then
		-- Mid-burst, the server's number can be a few shots behind ours,
		-- so only let it lower our count, never raise it.
		ammo[weaponId] = math.min(ammo[weaponId] or serverAmmo, serverAmmo)
	else
		ammo[weaponId] = serverAmmo
	end
	-- Ignore reload news for a weapon we already swapped away from.
	if weaponId == equipped then
		reloading = serverReloading
	end
	refreshHud()
end

-- Server says: your shot hit someone.
local function onHitConfirm(_damage: unknown, killedRaw: unknown, headshotRaw: unknown)
	local killed = killedRaw == true
	local headshot = headshotRaw == true
	Hud.showHitmarker(UserInputService:GetMouseLocation(), killed, headshot)
	local pitch = if killed then 1.35 elseif headshot then 1.15 else 1
	Effects.playSound(WeaponConfig.HitSoundId, if killed then 0.9 else 0.7, pitch)
end

-- Server says: someone else fired. Draw their tracers.
local function onShotFx(shooterRaw: unknown, weaponIdRaw: unknown, originRaw: unknown, endPointsRaw: unknown)
	if typeof(shooterRaw) ~= "Instance" or typeof(weaponIdRaw) ~= "string" or typeof(originRaw) ~= "Vector3" then
		return
	end
	if typeof(endPointsRaw) ~= "table" then
		return
	end
	local stats = WeaponConfig.get(weaponIdRaw :: string)
	if not stats then
		return
	end
	local origin = originRaw :: Vector3
	local shooter = shooterRaw :: Instance
	local start = origin
	if shooter:IsA("Player") then
		local shooterCharacter = shooter.Character
		if shooterCharacter then
			start = getMuzzlePosition(shooterCharacter, origin)
		end
	end

	Effects.muzzleFlash(start, stats.TracerColor)
	Effects.playSoundAt(stats.FireSoundId, start, 0.5)
	for _, point in endPointsRaw :: { any } do
		if typeof(point) == "Vector3" then
			Effects.tracer(start, point, stats.TracerColor, stats.TracerWidth)
		end
	end
end

local function onCharacterAdded()
	-- New life: full ammo, same weapon as before.
	for id, stats in WeaponConfig.Weapons do
		ammo[id] = stats.MagazineSize
	end
	reloading = false
	equipTime = os.clock()
	triggerHeld = false
	refreshHud()
end

local WeaponController = {}

function WeaponController.start()
	remotes.State.OnClientEvent:Connect(onState)
	remotes.HitConfirm.OnClientEvent:Connect(onHitConfirm)
	remotes.ShotFx.OnClientEvent:Connect(onShotFx)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		-- gameProcessed is true when typing in chat or clicking a button.
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			triggerHeld = true
			tryFire()
			return
		end
		local slot = SLOT_KEYS[input.KeyCode]
		if slot then
			local weaponId = WeaponConfig.Order[slot]
			if weaponId then
				equip(weaponId)
			end
		elseif input.KeyCode == Enum.KeyCode.R then
			requestReload()
		end
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			triggerHeld = false
		end
	end)

	-- Every frame: keep firing while the trigger is held on an automatic weapon.
	RunService.RenderStepped:Connect(function()
		if not triggerHeld then
			return
		end
		local stats = WeaponConfig.get(equipped)
		if stats and stats.Automatic then
			tryFire()
		end
	end)

	localPlayer.CharacterAdded:Connect(onCharacterAdded)
	refreshHud()
end

return WeaponController
