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

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared:WaitForChild("Config"):WaitForChild("WeaponConfig"))
local WeaponMath = require(Shared:WaitForChild("Combat"):WaitForChild("WeaponMath"))
local WeaponRemotes = require(Shared:WaitForChild("Net"):WaitForChild("WeaponRemotes"))
local HitGroups = require(Shared:WaitForChild("Combat"):WaitForChild("HitGroups"))
local ClientFolder = script.Parent.Parent
local Effects = require(ClientFolder:WaitForChild("Effects"):WaitForChild("WeaponEffects"))
local ToppingEffects = require(ClientFolder:WaitForChild("Effects"):WaitForChild("ToppingEffects"))
local Hud = require(ClientFolder:WaitForChild("UI"):WaitForChild("WeaponHud"))
local ViewmodelController = require(script.Parent:WaitForChild("ViewmodelController"))
local CameraController = require(script.Parent:WaitForChild("CameraController"))
local ShopConfig = require(Shared:WaitForChild("Config"):WaitForChild("ShopConfig"))
local Net = require(Shared:WaitForChild("Net"):WaitForChild("Net"))

-- Your loadout: the guns you own, in WeaponConfig.Order. The server checks
-- this too; this list is only for the keys, mouse wheel and slot bar.
local function loadout(): { string }
	local owned: { [string]: boolean } = {}
	local ownedText = Players.LocalPlayer:GetAttribute("OwnedItems")
	if typeof(ownedText) == "string" then
		for _, id in string.split(ownedText, ",") do
			owned[id] = true
		end
	end
	local list: { string } = {}
	for _, weaponId in WeaponConfig.Order do
		local itemId = ShopConfig.weaponItemId(weaponId)
		if ShopConfig.isFree(itemId) or owned[itemId] then
			table.insert(list, weaponId)
		end
	end
	return list
end

local function inMatch(): boolean
	local status = Players.LocalPlayer:GetAttribute("MatchStatus")
	return status == "InMatch" or status == "Practice" -- matches and the practice range
end

type WeaponStats = WeaponConfig.WeaponStats

local SLOT_KEYS: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.Four] = 4,
	[Enum.KeyCode.Five] = 5,
	[Enum.KeyCode.Six] = 6,
	[Enum.KeyCode.Seven] = 7,
	[Enum.KeyCode.Eight] = 8,
}

local localPlayer = Players.LocalPlayer
local remotes = WeaponRemotes.get()
local rng = Random.new()

-- Our own guess of the weapon state. The server sends the real numbers
-- (see remotes.State), and those always win.
local equipped = WeaponConfig.Order[1]
local ammo: { [string]: number } = {}
local reserve: { [string]: number } = {}
local reloading = false
local lastFireTime = 0
local equipTime = 0
local triggerHeld = false
local lastDryFireAt = 0
local lastHitPosition: Vector3? = nil -- where our last local shot hit someone (damage numbers)
local lastHitAt = 0

for id, stats in WeaponConfig.Weapons do
	ammo[id] = stats.MagazineSize
	reserve[id] = stats.ReserveAmmo
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

-- A shooter's topping and slime colour, for the topping bits that fly out
-- of their gun (Effects/ToppingEffects.shot).
local function toppingOf(shooter: Player): (string?, Color3)
	local topping = shooter:GetAttribute("EquippedTopping")
	local color = shooter:GetAttribute("BlobColor")
	return if typeof(topping) == "string" then topping else nil,
		if typeof(color) == "Color3" then color else Color3.fromRGB(120, 230, 160)
end

-- How many topping bits fly with each bullet (fewer for shotguns and on Low graphics).
local function toppingBits(pellets: number): number
	if localPlayer:GetAttribute("GraphicsQuality") == "Low" then
		return 1
	end
	return if pellets > 1 then 1 else 3
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
	Hud.setAmmo(equipped, ammo[equipped] or 0, reloading, reserve[equipped] or 0)
	ViewmodelController.setReloading(reloading)
end

local function requestReload()
	local stats = WeaponConfig.get(equipped)
	if not stats or reloading or (ammo[equipped] or 0) >= stats.MagazineSize or (reserve[equipped] or 0) <= 0 then
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
	-- First person (and touch screens): shots go to the screen centre, where the
	-- crosshair is. Third person in the lobby: where the mouse points.
	local firstPerson = (camera.CFrame.Position - camera.Focus.Position).Magnitude < 1
	local touchOnly = UserInputService.TouchEnabled and not UserInputService.MouseEnabled
	local point = if firstPerson or touchOnly then camera.ViewportSize / 2 else UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(point.X, point.Y)

	local params = HitGroups.weaponRayParams({ character, Effects.folder })

	local result = workspace:Raycast(ray.Origin, ray.Direction * range, params)
	if result then
		return result.Position
	end
	return ray.Origin + ray.Direction * range
end

local function tryFire()
	if not inMatch() then
		return -- no shooting in the lobby
	end
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
		if (reserve[equipped] or 0) <= 0 and now - lastDryFireAt > 0.3 then
			lastDryFireAt = now
			ViewmodelController.kick(0.15) -- a little "click" twitch: no bullets left
		end
		requestReload()
		return
	end

	lastFireTime = now
	-- A burst gun spends a bullet per round (the server fires the rounds).
	ammo[equipped] = math.max((ammo[equipped] or 0) - (stats.Burst or 1), 0)
	-- Movement reads this to pause sprinting briefly after a shot (this device only).
	localPlayer:SetAttribute("LastShotAt", now)

	-- Shots start from the head and fly toward whatever the mouse points at.
	-- This works in first person and third person.
	local origin = head.Position
	local direction = getAimPoint(character, stats.MaxRange) - origin
	if direction.Magnitude < 0.001 then
		return
	end
	remotes.Fire:FireServer(equipped, origin, direction.Unit)
	-- Recoil: the view kicks up (after aiming this shot) and recovers by itself.
	CameraController.kick(stats.RecoilKick)
	ViewmodelController.kick(stats.RecoilKick)

	-- Show the shot right away (our best guess; the server has the final say).
	-- The flash and tracers start at the tip of the gun you can see, never
	-- at your face (in first person your real gun sits right at the camera).
	local camera = workspace.CurrentCamera
	local firstPerson = camera ~= nil and (camera.CFrame.Position - camera.Focus.Position).Magnitude < 1
	local muzzle = ViewmodelController.getMuzzlePosition()
		or (if firstPerson and camera then (camera.CFrame * CFrame.new(1.1, -0.9, -3.2)).Position else nil)
		or getMuzzlePosition(character, origin)
	Effects.muzzleFlash(muzzle, stats.TracerColor, if firstPerson then 0.55 else 1)
	Effects.playSound(stats.FireSoundId, 0.6, 1)

	local params = HitGroups.weaponRayParams({ character, Effects.folder })
	local myTopping, mySlimeColor = toppingOf(localPlayer)
	local function drawRound()
		for _ = 1, stats.Pellets do
			local pelletDirection = WeaponMath.applySpread(direction, stats.Spread, rng)
			local result = workspace:Raycast(origin, pelletDirection * stats.MaxRange, params)
			local endPoint = if result then result.Position else origin + pelletDirection * stats.MaxRange
			if result then
				local model = result.Instance:FindFirstAncestorOfClass("Model")
				if model and model:FindFirstChildOfClass("Humanoid") then
					lastHitPosition, lastHitAt = result.Position, os.clock()
				end
			end
			local splash = stats.Splash
			if splash then
				-- Launcher: a glowing glob flies, then splashes where it lands.
				Effects.projectile(muzzle, endPoint, stats.ProjectileSpeed or 120, stats.TracerColor, splash.Radius)
			else
				Effects.tracer(muzzle, endPoint, stats.TracerColor, stats.TracerWidth)
				if result then
					Effects.impact(endPoint)
				end
			end
			-- Your topping flies out of the gun with the shot.
			ToppingEffects.shot(muzzle, endPoint, myTopping, mySlimeColor, toppingBits(stats.Pellets))
		end
	end
	drawRound()
	for round = 2, stats.Burst or 1 do
		task.delay((round - 1) * (stats.BurstInterval or 0.07), drawRound)
	end

	refreshHud()
end

-- Server says: here is your real ammo.
local function onState(weaponIdRaw: unknown, ammoRaw: unknown, reloadingRaw: unknown, reserveRaw: unknown)
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
	if typeof(reserveRaw) == "number" then
		reserve[weaponId] = reserveRaw
	end
	-- Ignore reload news for a weapon we already swapped away from.
	if weaponId == equipped then
		reloading = serverReloading
	end
	refreshHud()
end

-- Server says: your shot hit someone.
-- A damage number that pops up where you hit someone, rises and fades.
-- (Sized in studs like the game's other floating text.)
local function damageNumber(position: Vector3, amount: number, headshot: boolean, killed: boolean)
	local holder = Instance.new("Attachment")
	holder.Position = position -- Terrain sits at the world origin
	holder.Parent = workspace.Terrain
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromScale(3.2, 1.6)
	billboard.StudsOffset = Vector3.new(math.random(-6, 6) / 10, 1, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 250
	billboard.Parent = holder
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.LuckiestGuy
	label.TextScaled = true
	label.TextColor3 = if killed then Color3.fromRGB(255, 70, 90)
		elseif headshot then Color3.fromRGB(255, 215, 70)
		else Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.2
	label.Text = tostring(amount)
	label.Parent = billboard
	local tweenService = game:GetService("TweenService")
	tweenService:Create(billboard, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = billboard.StudsOffset + Vector3.new(0, 2.2, 0) }):Play()
	task.delay(0.35, function()
		tweenService:Create(label, TweenInfo.new(0.35), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	task.delay(0.75, function()
		holder:Destroy()
	end)
end

-- "ELIMINATED <name>" at the bottom of the screen when you knock someone out.
local eliminatedLabel: TextLabel? = nil
local eliminatedToken = 0
local function showEliminated(victimName: string)
	local label = eliminatedLabel
	if not label then
		local gui = Instance.new("ScreenGui")
		gui.Name = "EliminatedBanner"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 6
		gui.Parent = localPlayer:WaitForChild("PlayerGui")
		local newLabel = Instance.new("TextLabel")
		newLabel.Name = "Eliminated"
		newLabel.AnchorPoint = Vector2.new(0.5, 1)
		newLabel.Position = UDim2.new(0.5, 0, 1, -170)
		newLabel.Size = UDim2.fromOffset(520, 40)
		newLabel.BackgroundTransparency = 1
		newLabel.Font = Enum.Font.GothamBold
		newLabel.TextSize = 26
		newLabel.RichText = true
		newLabel.TextColor3 = Color3.fromRGB(235, 240, 255)
		newLabel.TextStrokeTransparency = 0.4
		newLabel.Parent = gui
		eliminatedLabel = newLabel
		label = newLabel
	end
	local shown = label :: TextLabel
	shown.Text = `ELIMINATED <font color="#FF5A6E">{victimName}</font>`
	shown.TextTransparency = 0
	shown.TextStrokeTransparency = 0.4
	eliminatedToken += 1
	local myToken = eliminatedToken
	task.delay(1.6, function()
		if eliminatedToken == myToken then
			game:GetService("TweenService"):Create(shown, TweenInfo.new(0.3), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

local function onHitConfirm(damageRaw: unknown, killedRaw: unknown, headshotRaw: unknown)
	local killed = killedRaw == true
	local headshot = headshotRaw == true
	local hitPosition = lastHitPosition
	if typeof(damageRaw) == "number" and damageRaw > 0 and hitPosition and os.clock() - lastHitAt < 0.8 then
		damageNumber(hitPosition, math.round(damageRaw), headshot, killed)
	end
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
	local topping: string?, slimeColor = nil, Color3.fromRGB(120, 230, 160)
	if shooter:IsA("Player") then
		local shooterCharacter = shooter.Character
		if shooterCharacter then
			start = getMuzzlePosition(shooterCharacter, origin)
		end
		topping, slimeColor = toppingOf(shooter)
	end
	local endCount = 0
	for _ in endPointsRaw :: { any } do
		endCount += 1
	end

	Effects.muzzleFlash(start, stats.TracerColor)
	Effects.playSoundAt(stats.FireSoundId, start, 0.5)
	for _, point in endPointsRaw :: { any } do
		if typeof(point) == "Vector3" then
			local splash = stats.Splash
			if splash then
				Effects.projectile(start, point, stats.ProjectileSpeed or 120, stats.TracerColor, splash.Radius)
			else
				Effects.tracer(start, point, stats.TracerColor, stats.TracerWidth)
			end
			-- Their topping flies out of their gun too.
			ToppingEffects.shot(start, point, topping, slimeColor, if endCount > 1 then 1 else 2)
		end
	end
end

local function onCharacterAdded()
	-- New life: full ammo, same weapon as before.
	for id, stats in WeaponConfig.Weapons do
		ammo[id] = stats.MagazineSize
		reserve[id] = stats.ReserveAmmo
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
	-- Your eliminations get a big "ELIMINATED <name>" (the kill feed tells everyone).
	Net.event("KillFeed").OnClientEvent:Connect(function(killerName: unknown, victimName: unknown)
		if killerName == localPlayer.DisplayName and typeof(victimName) == "string" then
			showEliminated(string.sub(victimName, 1, 24))
		end
	end)
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
			local weaponId = loadout()[slot]
			if weaponId then
				equip(weaponId)
			end
		elseif input.KeyCode == Enum.KeyCode.R then
			requestReload()
		end
	end)

	-- Mouse wheel (and gamepad Y) cycles through the weapons.
	local function cycle(step: number)
		if os.clock() - equipTime < WeaponConfig.SwapTime then
			return -- one swap at a time, so a fast wheel spin doesn't spam the server
		end
		local guns = loadout()
		if #guns == 0 then
			return
		end
		local index = table.find(guns, equipped) or 1
		equip(guns[((index - 1 + step) % #guns) + 1])
	end
	UserInputService.InputChanged:Connect(function(input: InputObject, gameProcessed: boolean)
		if not gameProcessed and input.UserInputType == Enum.UserInputType.MouseWheel then
			cycle(if input.Position.Z > 0 then -1 else 1)
		end
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if not gameProcessed and input.KeyCode == Enum.KeyCode.ButtonY then
			cycle(1)
		end
	end)

	-- Phones and tablets: on-screen Fire (hold), Reload and Swap buttons.
	if UserInputService.TouchEnabled then
		ContextActionService:BindAction("SlimeFire", function(_name: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
			if inputState == Enum.UserInputState.Begin then
				triggerHeld = true
				tryFire()
			elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
				triggerHeld = false
			end
			return Enum.ContextActionResult.Sink
		end, true)
		ContextActionService:SetTitle("SlimeFire", "Fire")
		ContextActionService:BindAction("SlimeReload", function(_name: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
			if inputState == Enum.UserInputState.Begin then
				requestReload()
			end
			return Enum.ContextActionResult.Sink
		end, true)
		ContextActionService:SetTitle("SlimeReload", "Reload")
		ContextActionService:BindAction("SlimeSwap", function(_name: string, inputState: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
			if inputState == Enum.UserInputState.Begin then
				cycle(1)
			end
			return Enum.ContextActionResult.Sink
		end, true)
		ContextActionService:SetTitle("SlimeSwap", "Swap")
	end

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

	-- Slot bar shows your loadout; the weapon HUD only shows in matches.
	local function syncLoadout()
		local guns = loadout()
		Hud.setLoadout(guns)
		if not table.find(guns, equipped) and guns[1] then
			equipped = guns[1]
		end
		refreshHud()
	end
	localPlayer:GetAttributeChangedSignal("OwnedItems"):Connect(syncLoadout)
	localPlayer:GetAttributeChangedSignal("MatchStatus"):Connect(function()
		Hud.setVisible(inMatch())
		triggerHeld = false
	end)
	syncLoadout()
	Hud.setVisible(inMatch())
	refreshHud()
end

return WeaponController
