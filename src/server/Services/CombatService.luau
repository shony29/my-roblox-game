--!strict
--[[
	CombatService
	The server is the referee for all shooting. The client only says
	"I fired from here, in this direction". The server then:
	  1. checks the values are real Vector3s (not NaN, not huge),
	  2. checks the player is alive, has ammo and isn't firing too fast,
	  3. checks the muzzle position is close to their head and not behind a wall,
	  4. does its OWN raycast to find out what was really hit,
	  5. applies damage, and gives coins for eliminations.
	So a cheater can't invent hits, deal extra damage or shoot infinitely.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local PlayerData = require(script.Parent.PlayerData)
local RateLimiter = require(script.Parent.Parent.Util.RateLimiter)

local WEAPON = Config.Weapon

-- Network lag can bunch shots together slightly, so allow shots a little
-- faster than FireInterval. 0.8 = up to 20% faster.
local FIRE_INTERVAL_TOLERANCE = 0.8

type WeaponState = {
	Ammo: number,
	Reloading: boolean,
	LastShotTime: number,
}

local CombatService = {}

local weaponStates: { [Player]: WeaponState } = {}
local lastAttackers: { [Humanoid]: Player } = {} -- who to credit when someone is splatted

local fireRemote = Remotes.event("Fire")
local reloadRemote = Remotes.event("Reload")
local ammoChangedRemote = Remotes.event("AmmoChanged")
local shotFiredRemote = Remotes.event("ShotFired")
local hitConfirmedRemote = Remotes.event("HitConfirmed")
local killFeedRemote = Remotes.event("KillFeed")

local canReload = RateLimiter.new(5, 1)

-- NaN is the only value not equal to itself; huge values would break raycasts.
local function isFiniteVector(v: Vector3): boolean
	for _, n in { v.X, v.Y, v.Z } do
		if n ~= n or math.abs(n) > 1e6 then
			return false
		end
	end
	return true
end

local function sendAmmo(player: Player, state: WeaponState)
	ammoChangedRemote:FireClient(player, state.Ammo, state.Reloading)
end

-- Returns the player's character and head, only if they're alive.
local function getAliveCharacter(player: Player): (Model?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local head = character:FindFirstChild("Head")
	if humanoid and humanoid.Health > 0 and head and head:IsA("BasePart") then
		return character, head
	end
	return nil, nil
end

local function onFire(player: Player, origin: unknown, direction: unknown)
	-- 1. Is the data even the right type?
	if typeof(origin) ~= "Vector3" then
		return
	end
	if typeof(direction) ~= "Vector3" then
		return
	end
	if not isFiniteVector(origin) or not isFiniteVector(direction) then
		return
	end
	local length = direction.Magnitude
	if length < 0.9 or length > 1.1 then
		return -- the client always sends a direction of length 1
	end
	local aim = direction.Unit

	-- 2. Alive, armed, and not firing faster than the weapon allows?
	local character, head = getAliveCharacter(player)
	local state = weaponStates[player]
	if not character or not head or not state then
		return
	end
	if state.Reloading or state.Ammo <= 0 then
		sendAmmo(player, state) -- put the client's ammo counter right
		return
	end
	local now = os.clock()
	if now - state.LastShotTime < WEAPON.FireInterval * FIRE_INTERVAL_TOLERANCE then
		return
	end

	-- 3. Is the muzzle near their head, with no wall in between?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }

	local offset = origin - head.Position
	if offset.Magnitude > WEAPON.MaxOriginDistance then
		return
	end
	if offset.Magnitude > 0.01 and workspace:Raycast(head.Position, offset, params) then
		return -- trying to shoot from the other side of a wall
	end

	-- The shot is legit. Firing ends spawn protection early.
	state.LastShotTime = now
	state.Ammo -= 1
	local forceField = character:FindFirstChildOfClass("ForceField")
	if forceField then
		forceField:Destroy()
	end

	-- 4. The server's own raycast decides what was hit.
	local result = workspace:Raycast(origin, aim * WEAPON.Range, params)
	local hitPosition = if result then result.Position else origin + aim * WEAPON.Range

	-- 5. Damage!
	if result then
		local victimModel = result.Instance:FindFirstAncestorOfClass("Model")
		if victimModel and victimModel ~= character then
			local victimHumanoid = victimModel:FindFirstChildOfClass("Humanoid")
			if victimHumanoid and victimHumanoid.Health > 0 then
				local protected = victimModel:FindFirstChildOfClass("ForceField") ~= nil
				lastAttackers[victimHumanoid] = player
				victimHumanoid:TakeDamage(WEAPON.Damage) -- TakeDamage respects force fields
				if not protected then
					hitConfirmedRemote:FireClient(player, victimHumanoid.Health <= 0)
				end
			end
		end
	end

	-- Let everyone draw the paint tracer (the shooter already drew their own).
	shotFiredRemote:FireAllClients(player, origin, hitPosition)
end

local function onReload(player: Player)
	local state = weaponStates[player]
	if not state or not canReload(player) then
		return
	end
	if state.Reloading or state.Ammo >= WEAPON.MagazineSize then
		sendAmmo(player, state)
		return
	end
	state.Reloading = true
	task.delay(WEAPON.ReloadTime, function()
		-- If they respawned meanwhile, they already have a fresh weapon.
		if weaponStates[player] ~= state then
			return
		end
		state.Ammo = WEAPON.MagazineSize
		state.Reloading = false
		sendAmmo(player, state)
	end)
end

local function onCharacterAdded(player: Player, character: Model)
	-- Every life starts with a full magazine.
	local state: WeaponState = { Ammo = WEAPON.MagazineSize, Reloading = false, LastShotTime = 0 }
	weaponStates[player] = state
	sendAmmo(player, state)

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	humanoid.Died:Once(function()
		local killer = lastAttackers[humanoid]
		lastAttackers[humanoid] = nil

		PlayerData.update(player, function(data)
			data.Deaths += 1
		end)
		if killer and killer ~= player and killer.Parent == Players then
			PlayerData.update(killer, function(data)
				data.Kills += 1
				data.Coins += Config.Rewards.CoinsPerKill
			end)
		end
		killFeedRemote:FireAllClients(killer, player)
	end)

	-- Tidy up if the character disappears without dying (e.g. the player leaves).
	character.Destroying:Once(function()
		lastAttackers[humanoid] = nil
	end)
end

function CombatService.start()
	fireRemote.OnServerEvent:Connect(onFire)
	reloadRemote.OnServerEvent:Connect(onReload)

	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			onCharacterAdded(player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	Players.PlayerRemoving:Connect(function(player)
		weaponStates[player] = nil
	end)
end

return CombatService
