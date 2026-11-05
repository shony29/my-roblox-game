--!strict
--[[
	AmmoService: balls of slime on the map that refill your ammo.

	Each map lists a few spots (mirrored left/right so neither team has an
	advantage). During a match, walk over a glowing slime ball and the server
	gives each of your guns one more magazine of spare ammo, up to its
	maximum. The ball then vanishes and comes back after RESPAWN_TIME.
	If your ammo is already full, the ball stays for someone who needs it.

	The server checks positions itself (4 times a second), so a client
	can't claim pickups it isn't standing on.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MatchState = require(ReplicatedStorage.Shared.Match.MatchState)
local WeaponService = require(script.Parent.WeaponService)

type Pickup = {
	position: Vector3,
	core: BasePart,
	shell: BasePart,
	readyAt: number, -- os.clock() when it can be picked up again (0 = now)
}

local CHECK_INTERVAL = 0.25
local PICKUP_RADIUS = 4.5
local RESPAWN_TIME = 15
local FLOAT_HEIGHT = 1.8
local SLIME = Color3.fromRGB(120, 255, 100)

local AmmoService = {}

local pickups: { Pickup } = {}
local folder: Folder? = nil
local started = false

local function ball(name: string, diameter: number, color: Color3, material: Enum.Material, transparency: number, position: Vector3): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.one * diameter
	part.Color = color
	part.Material = material
	part.Transparency = transparency
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false -- bullets fly through
	part.CanTouch = false
	part.CastShadow = false
	part.Position = position
	return part
end

local function setVisible(pickup: Pickup, visible: boolean)
	pickup.core.Transparency = if visible then 0.1 else 1
	pickup.shell.Transparency = if visible then 0.6 else 1
	local light = pickup.core:FindFirstChildOfClass("PointLight")
	if light then
		light.Enabled = visible
	end
end

-- Called by MapService whenever a map is built: puts a slime ball on each spot.
function AmmoService.setSpots(spots: { Vector3 })
	if folder then
		folder:Destroy()
	end
	table.clear(pickups)
	local newFolder = Instance.new("Folder")
	newFolder.Name = "AmmoPickups"
	newFolder.Parent = Workspace
	folder = newFolder
	for _, spot in spots do
		local position = spot + Vector3.new(0, FLOAT_HEIGHT, 0)
		local core = ball("SlimeAmmo", 1.4, SLIME, Enum.Material.Neon, 0.1, position)
		local light = Instance.new("PointLight")
		light.Color = SLIME
		light.Range = 10
		light.Brightness = 1.2
		light.Parent = core
		core.Parent = newFolder
		local shell = ball("SlimeAmmoShell", 2.2, SLIME:Lerp(Color3.new(1, 1, 1), 0.4), Enum.Material.Glass, 0.6, position)
		shell.Parent = newFolder
		table.insert(pickups, { position = position, core = core, shell = shell, readyAt = 0 })
	end
end

local function check()
	local now = os.clock()
	for _, pickup in pickups do
		if now < pickup.readyAt then
			continue
		end
		if pickup.readyAt > 0 then
			pickup.readyAt = 0
			setVisible(pickup, true) -- back again
		end
		for _, player in Players:GetPlayers() do
			if player:GetAttribute(MatchState.PlayerAttr.Status) ~= "InMatch" then
				continue
			end
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
				local offset = root.Position - pickup.position
				if Vector2.new(offset.X, offset.Z).Magnitude <= PICKUP_RADIUS and math.abs(offset.Y) <= 5 then
					if WeaponService.refillReserve(player) then
						pickup.readyAt = now + RESPAWN_TIME
						setVisible(pickup, false)
						break
					end
				end
			end
		end
	end
end

function AmmoService.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		while true do
			check()
			task.wait(CHECK_INTERVAL)
		end
	end)
end

return AmmoService
