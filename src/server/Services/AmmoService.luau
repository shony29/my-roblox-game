--!strict
--[[
	AmmoService: ammo crates on the ground that refill your ammo.

	  * Each map lists spots for crates (mirrored left/right so neither team
	    has an advantage). Walk over a crate during a match and the server
	    gives each of your guns two more magazines of spare ammo, up to its
	    maximum (every life starts with just one spare magazine, so crates
	    matter). Your ammo counter goes up, a "+60 AMMO" pops up, and an
	    empty gun reloads by itself. The crate comes back after RESPAWN_TIME.
	    If you already carry the most you can, it stays for someone else.
	  * Every eliminated player drops a crate where they fell (it disappears
	    after DROP_LIFETIME seconds, or once someone takes it).
	  * A crate is a green box with bullets on top, a glowing ring on the
	    floor and a small "AMMO" label, so it's easy to spot.

	The server checks positions itself (4 times a second), so a client
	can't claim pickups it isn't standing on. Separate maps (the match
	arena, the free-for-all arena) keep their own crates ("groups").
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MatchState = require(ReplicatedStorage.Shared.Match.MatchState)
local Net = require(ReplicatedStorage.Shared.Net.Net)
local WeaponService = require(script.Parent.WeaponService)

type Pickup = {
	position: Vector3,
	model: Model,
	readyAt: number, -- os.clock() when it can be picked up again (0 = now)
	expiresAt: number?, -- dropped crates: when they disappear
}
type Group = { folder: Folder, pickups: { Pickup } }

local CHECK_INTERVAL = 0.25
local PICKUP_RADIUS = 4.5
local RESPAWN_TIME = 15
local DROP_LIFETIME = 20
local MAX_DROPS = 30
local GREEN = Color3.fromRGB(70, 150, 70)
local SLIME = Color3.fromRGB(120, 255, 100)
local BRASS = Color3.fromRGB(230, 185, 80)

local AmmoService = {}

local groups: { [string]: Group } = {}
local started = false

local function piece(model: Model, name: string, size: Vector3, cframe: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = shape or Enum.PartType.Block
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false -- bullets fly through
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = model
	return part
end

-- A green ammo crate with bullets on top, a glowing ring and an AMMO label.
local function buildCrate(position: Vector3, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "AmmoCrate"
	local base = CFrame.new(position)
	piece(model, "Crate", Vector3.new(2.8, 1.4, 1.9), base * CFrame.new(0, 0.7, 0), GREEN, Enum.Material.SmoothPlastic)
	piece(model, "Lid", Vector3.new(2.9, 0.25, 2), base * CFrame.new(0, 1.5, 0), Color3.fromRGB(50, 110, 50), Enum.Material.SmoothPlastic)
	piece(model, "Stripe", Vector3.new(2.9, 0.3, 2), base * CFrame.new(0, 0.75, 0), SLIME, Enum.Material.Neon)
	for i = -1, 1 do
		local bulletBase = base * CFrame.new(i * 0.7, 1.6, 0)
		piece(model, "Casing", Vector3.new(0.9, 0.42, 0.42), bulletBase * CFrame.new(0, 0.45, 0) * CFrame.Angles(0, 0, math.rad(90)), BRASS, Enum.Material.Metal, Enum.PartType.Cylinder)
		piece(model, "Tip", Vector3.one * 0.42, bulletBase * CFrame.new(0, 0.95, 0), Color3.fromRGB(200, 120, 70), Enum.Material.Metal, Enum.PartType.Ball)
	end
	local ring = piece(model, "Ring", Vector3.new(0.1, 5, 5), base * CFrame.new(0, 0.06, 0) * CFrame.Angles(0, 0, math.rad(90)), SLIME, Enum.Material.Neon, Enum.PartType.Cylinder)
	ring.Transparency = 0.55
	local light = Instance.new("PointLight")
	light.Color = SLIME
	light.Range = 9
	light.Brightness = 1
	light.Parent = ring
	-- "AMMO", sized in studs like the game's other floating text.
	local label = Instance.new("BillboardGui")
	label.Name = "AmmoLabel"
	label.Size = UDim2.fromScale(2.6, 0.9)
	label.StudsOffset = Vector3.new(0, 3.2, 0)
	label.MaxDistance = 70
	label.LightInfluence = 0
	label.Parent = model:FindFirstChild("Lid")
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.Michroma
	text.TextScaled = true
	text.TextColor3 = SLIME
	text.TextStrokeTransparency = 0.3
	text.Text = "AMMO"
	text.Parent = label
	model.Parent = parent
	return model
end

local function setVisible(pickup: Pickup, visible: boolean)
	for _, descendant in pickup.model:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Transparency = if not visible then 1 elseif descendant.Name == "Ring" then 0.55 else 0
		elseif descendant:IsA("PointLight") or descendant:IsA("BillboardGui") then
			descendant.Enabled = visible
		end
	end
end

local function groupFor(name: string): Group
	local group = groups[name]
	if group and group.folder.Parent then
		return group
	end
	local folder = Instance.new("Folder")
	folder.Name = `AmmoCrates_{name}`
	folder.Parent = Workspace
	local newGroup: Group = { folder = folder, pickups = {} }
	groups[name] = newGroup
	return newGroup
end

--[[
	Puts a crate on each spot (MapService calls this whenever a map is built).
	`groupName` keeps different arenas apart ("Match" by default).
]]
function AmmoService.setSpots(spots: { Vector3 }, groupName: string?)
	local name = groupName or "Match"
	local old = groups[name]
	if old then
		old.folder:Destroy()
		groups[name] = nil
	end
	local group = groupFor(name)
	for _, spot in spots do
		table.insert(group.pickups, { position = spot, model = buildCrate(spot, group.folder), readyAt = 0 })
	end
end

-- An eliminated player's dropped crate, on the floor where they fell.
function AmmoService.dropAt(position: Vector3)
	-- Find the floor under them (ignoring every player's slime).
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	for _, player in Players:GetPlayers() do
		if player.Character then
			table.insert(ignore, player.Character)
		end
	end
	params.FilterDescendantsInstances = ignore
	local floorHit = Workspace:Raycast(position + Vector3.new(0, 2, 0), Vector3.new(0, -14, 0), params)
	local spot = if floorHit then floorHit.Position else position - Vector3.new(0, 2, 0)
	local group = groupFor("Drops")
	if #group.pickups >= MAX_DROPS then
		local oldest = table.remove(group.pickups, 1)
		if oldest then
			oldest.model:Destroy()
		end
	end
	table.insert(group.pickups, {
		position = spot,
		model = buildCrate(spot, group.folder),
		readyAt = 0,
		expiresAt = os.clock() + DROP_LIFETIME,
	})
end

local function check()
	local now = os.clock()
	for _, group in groups do
		for index = #group.pickups, 1, -1 do
			local pickup = group.pickups[index]
			if pickup.expiresAt and now >= pickup.expiresAt then
				pickup.model:Destroy()
				table.remove(group.pickups, index)
				continue
			end
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
					if Vector2.new(offset.X, offset.Z).Magnitude <= PICKUP_RADIUS and math.abs(offset.Y) <= 6 then
						local refilled, gained = WeaponService.refillReserve(player)
						if refilled then
							Net.event("AmmoPickup"):FireClient(player, gained)
							if pickup.expiresAt then
								-- A dropped crate is used up.
								pickup.model:Destroy()
								table.remove(group.pickups, index)
							else
								pickup.readyAt = now + RESPAWN_TIME
								setVisible(pickup, false)
							end
							break
						end
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
			local ok, err = pcall(check)
			if not ok then
				warn("[AmmoService] check failed:", err)
			end
			task.wait(CHECK_INTERVAL)
		end
	end)
end

return AmmoService
