--!strict
--[[
	WeaponService: the referee. It runs only on the server.

	The client can only say "I want to shoot, aiming in this direction".
	Before anything gets hurt, the server checks:
	  1. The message has the right kinds of values (no junk, no NaN numbers).
	  2. The player is alive and is holding that weapon.
	  3. Enough time passed since their last shot (fire rate).
	  4. They have ammo and aren't reloading.
	  5. The shot starts close to their head, with no wall in between.
	Then the server fires its OWN raycast (an invisible laser) to see what
	the bullet really hits. That raycast stops at the first wall, which is the
	line-of-sight check, and is limited to the weapon's MaxRange, which is the
	distance check. Damage numbers come only from WeaponConfig, never from the client.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local WeaponConfig = require(Shared:WaitForChild("Config"):WaitForChild("WeaponConfig"))
local WeaponMath = require(Shared:WaitForChild("Combat"):WaitForChild("WeaponMath"))
local WeaponRemotes = require(Shared:WaitForChild("Net"):WaitForChild("WeaponRemotes"))
local HitGroups = require(Shared:WaitForChild("Combat"):WaitForChild("HitGroups"))
local GunModel = require(script.Parent.Parent.Components.GunModel)

type WeaponStats = WeaponConfig.WeaponStats

type PlayerState = {
	equipped: string,
	ammo: { [string]: number },
	reserve: { [string]: number }, -- spare bullets per weapon
	reloading: boolean,
	-- Each reload gets a number. Swapping weapons bumps it, so an old reload
	-- that finishes later knows it was cancelled.
	reloadToken: number,
	lastFireTime: number,
	equipTime: number,
	-- Spam protection for the Equip and Reload messages.
	lastEquipRequest: number,
	lastReloadRequest: number,
}

type HitInfo = {
	damage: number,
	headshot: boolean,
}

-- Ignore Equip / Reload messages that arrive faster than this (seconds).
local REQUEST_COOLDOWN = 0.1

local remotes = WeaponRemotes.get()
local rng = Random.new()
local states: { [Player]: PlayerState } = {}

local function fullAmmo(): { [string]: number }
	local ammo = {}
	for id, stats in WeaponConfig.Weapons do
		ammo[id] = stats.MagazineSize
	end
	return ammo
end

local function fullReserve(): { [string]: number }
	local reserve = {}
	for id, stats in WeaponConfig.Weapons do
		reserve[id] = stats.ReserveAmmo
	end
	return reserve
end

local function sendState(player: Player, state: PlayerState)
	local ammo = state.ammo[state.equipped] or 0
	local reserve = state.reserve[state.equipped] or 0
	remotes.State:FireClient(player, state.equipped, ammo, state.reloading, reserve)

	-- The game's main HUD (UI team) reads these two attributes on the character
	-- to show the ammo counter. Names agreed in Shared/Data/GameContract.
	local character = player.Character
	local stats = WeaponConfig.get(state.equipped)
	if character and stats then
		character:SetAttribute("Ammo", ammo)
		character:SetAttribute("MaxAmmo", stats.MagazineSize)
		character:SetAttribute("ReserveAmmo", reserve)
	end
end

local function getAliveCharacter(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local head = character:FindFirstChild("Head")
	if not humanoid or humanoid.Health <= 0 or not head or not head:IsA("BasePart") then
		return nil, nil, nil
	end
	return character, humanoid, head :: BasePart
end

-- Is this hit a headshot? A normal "Head" part counts, and so does the top
-- of a blob body (players are blobs, see Movement/BlobCharacter).
local function isHeadshot(hitPart: BasePart, hitPosition: Vector3): boolean
	if hitPart.Name == "Head" then
		return true
	end
	if hitPart.Name == "Body" and hitPart:GetAttribute("IsBlobPart") then
		local localY = hitPart.CFrame:PointToObjectSpace(hitPosition).Y
		return localY > hitPart.Size.Y * HitGroups.BLOB_HEADSHOT_FRACTION
	end
	return false
end

-- Walks up from the part a bullet hit to find the Humanoid it belongs to.
-- Works for players and for test dummies (any Model with a Humanoid).
local function findHumanoid(hitPart: BasePart, hitPosition: Vector3): (Humanoid?, boolean)
	local model = hitPart:FindFirstAncestorOfClass("Model")
	while model do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return humanoid, isHeadshot(hitPart, hitPosition)
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil, false
end

local function canDamage(shooter: Player, humanoid: Humanoid): boolean
	if humanoid.Health <= 0 then
		return false
	end
	local victim: Player? = nil
	local parent = humanoid.Parent
	if parent and parent:IsA("Model") then
		victim = Players:GetPlayerFromCharacter(parent)
	end
	if victim == shooter then
		return false
	end
	-- If the game uses Teams, don't hurt teammates.
	if victim and shooter.Team and victim.Team == shooter.Team and not shooter.Neutral then
		return false
	end
	return true
end

-- The classic Roblox "creator" tag: lets a future scoreboard know who got the kill.
local function tagCreator(humanoid: Humanoid, shooter: Player)
	local old = humanoid:FindFirstChild("creator")
	if old then
		old:Destroy()
	end
	local tag = Instance.new("ObjectValue")
	tag.Name = "creator"
	tag.Value = shooter
	tag.Parent = humanoid
	task.delay(2, function()
		if tag.Parent then
			tag:Destroy()
		end
	end)
end

local function startReload(player: Player, state: PlayerState)
	local stats = WeaponConfig.get(state.equipped)
	if not stats or state.reloading then
		return
	end
	if (state.ammo[stats.Id] or 0) >= stats.MagazineSize or (state.reserve[stats.Id] or 0) <= 0 then
		return -- already full, or no spare bullets left
	end
	state.reloading = true
	state.reloadToken += 1
	local token = state.reloadToken
	sendState(player, state)

	task.delay(stats.ReloadTime, function()
		-- Only finish if nothing changed meanwhile (no swap, didn't leave).
		if states[player] ~= state or state.reloadToken ~= token then
			return
		end
		-- Move bullets from the reserve into the magazine.
		local current = state.ammo[stats.Id] or 0
		local taken = math.min(stats.MagazineSize - current, state.reserve[stats.Id] or 0)
		state.ammo[stats.Id] = current + taken
		state.reserve[stats.Id] = (state.reserve[stats.Id] or 0) - taken
		state.reloading = false
		sendState(player, state)
	end)
end

local function onFire(player: Player, weaponIdRaw: unknown, originRaw: unknown, directionRaw: unknown)
	-- 1. Check the kinds of values. Anything odd gets ignored.
	if typeof(weaponIdRaw) ~= "string" or typeof(originRaw) ~= "Vector3" or typeof(directionRaw) ~= "Vector3" then
		return
	end
	local weaponId = weaponIdRaw :: string
	local origin = originRaw :: Vector3
	local direction = directionRaw :: Vector3
	if not WeaponMath.isFiniteVector(origin) or not WeaponMath.isFiniteVector(direction) then
		return
	end
	if direction.Magnitude < 0.001 then
		return
	end

	-- 2. Alive and holding this weapon?
	local state = states[player]
	if not state or state.equipped ~= weaponId then
		return
	end
	local stats = WeaponConfig.get(weaponId)
	if not stats then
		return
	end
	local character, _, head = getAliveCharacter(player)
	if not character or not head then
		return
	end

	-- 3. Fire rate (and a short pause right after swapping).
	local now = os.clock()
	local minGap = (1 / stats.FireRate) * WeaponConfig.FireRateTolerance
	if now - state.lastFireTime < minGap then
		return
	end
	if now - state.equipTime < WeaponConfig.SwapTime * WeaponConfig.FireRateTolerance then
		return
	end

	-- 4. Ammo.
	local ammo = state.ammo[weaponId] or 0
	if state.reloading or ammo <= 0 then
		return
	end

	-- 5. The shot must start near the head, and not from behind a wall.
	local toOrigin = origin - head.Position
	if toOrigin.Magnitude > WeaponConfig.MaxOriginOffset then
		return
	end
	local params = HitGroups.weaponRayParams({ character })
	if toOrigin.Magnitude > 0.05 and workspace:Raycast(head.Position, toOrigin, params) then
		return
	end

	-- All checks passed: spend a bullet.
	state.lastFireTime = now
	state.ammo[weaponId] = ammo - 1

	-- The server's own raycasts decide what gets hit.
	local endPoints: { Vector3 } = {}
	local hits: { [Humanoid]: HitInfo } = {}
	for _ = 1, stats.Pellets do
		local pelletDirection = WeaponMath.applySpread(direction, stats.Spread, rng)
		local result = workspace:Raycast(origin, pelletDirection * stats.MaxRange, params)
		if result then
			table.insert(endPoints, result.Position)
			local humanoid, isHead = findHumanoid(result.Instance, result.Position)
			if humanoid and canDamage(player, humanoid) then
				local damage = WeaponMath.damageAtDistance(stats, result.Distance)
				if isHead then
					damage *= stats.HeadshotMultiplier
				end
				local info = hits[humanoid]
				if info then
					info.damage += damage
					info.headshot = info.headshot or isHead
				else
					hits[humanoid] = { damage = damage, headshot = isHead }
				end
			end
		else
			table.insert(endPoints, origin + pelletDirection * stats.MaxRange)
		end
	end

	for humanoid, info in hits do
		tagCreator(humanoid, player)
		-- TakeDamage respects spawn ForceFields.
		humanoid:TakeDamage(info.damage)
		local killed = humanoid.Health <= 0
		remotes.HitConfirm:FireClient(player, math.round(info.damage), killed, info.headshot)
	end

	-- Tell everyone else to draw the tracers. The shooter already drew their own.
	for _, other in Players:GetPlayers() do
		if other ~= player then
			remotes.ShotFx:FireClient(other, player, weaponId, origin, endPoints)
		end
	end

	if state.ammo[weaponId] <= 0 then
		startReload(player, state)
	else
		sendState(player, state)
	end
end

local function onEquip(player: Player, weaponIdRaw: unknown)
	if typeof(weaponIdRaw) ~= "string" then
		return
	end
	local weaponId = weaponIdRaw :: string
	local stats = WeaponConfig.get(weaponId)
	local state = states[player]
	if not stats or not state or state.equipped == weaponId then
		return
	end
	-- Each swap rebuilds the gun model, so don't let a cheater spam it.
	local now = os.clock()
	if now - state.lastEquipRequest < REQUEST_COOLDOWN then
		return
	end
	state.lastEquipRequest = now

	state.equipped = weaponId
	state.equipTime = os.clock()
	-- Swapping cancels a reload in progress.
	state.reloading = false
	state.reloadToken += 1
	player:SetAttribute("EquippedWeapon", weaponId)

	local character = player.Character
	if character then
		GunModel.attach(character, stats)
	end
	sendState(player, state)
end

local function onReload(player: Player)
	local state = states[player]
	if not state then
		return
	end
	local now = os.clock()
	if now - state.lastReloadRequest < REQUEST_COOLDOWN then
		return
	end
	state.lastReloadRequest = now
	startReload(player, state)
end

local function onCharacterAdded(player: Player, character: Model)
	local state = states[player]
	if not state then
		return
	end
	-- Fresh life, full ammo.
	state.ammo = fullAmmo()
	state.reserve = fullReserve()
	state.reloading = false
	state.reloadToken += 1
	state.equipTime = os.clock()

	local stats = WeaponConfig.get(state.equipped)
	if stats then
		-- Wait (up to 5 seconds) for the hand to exist before attaching the gun.
		local waited = 0
		while
			waited < 5
			and character.Parent
			and not character:FindFirstChild("RightHand")
			and not character:FindFirstChild("Right Arm")
		do
			waited += task.wait(0.1)
		end
		if character.Parent and player.Character == character then
			GunModel.attach(character, stats)
		end
	end
	sendState(player, state)
end

local function onPlayerAdded(player: Player)
	states[player] = {
		equipped = WeaponConfig.Order[1],
		ammo = fullAmmo(),
		reserve = fullReserve(),
		reloading = false,
		reloadToken = 0,
		lastFireTime = 0,
		equipTime = 0,
		lastEquipRequest = 0,
		lastReloadRequest = 0,
	}
	player:SetAttribute("EquippedWeapon", WeaponConfig.Order[1])

	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
	if player.Character then
		task.spawn(onCharacterAdded, player, player.Character)
	end
end

local WeaponService = {}

function WeaponService.start()
	HitGroups.setup()
	remotes.Fire.OnServerEvent:Connect(onFire)
	remotes.Equip.OnServerEvent:Connect(onEquip)
	remotes.Reload.OnServerEvent:Connect(onReload)

	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		states[player] = nil
	end)
end

return WeaponService
