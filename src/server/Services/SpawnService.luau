--!strict
--[[
	SpawnService: gives players a fresh character at a good spawn point.

	  * Team A spawns on the west half of the map (X < 0), team B on the east
	    half (X > 0), so teams start apart. Without a team, any pad is used.
	  * Among the allowed pads, it prefers the ones farthest from enemies,
	    picking randomly among the safest few so spawns aren't predictable.
	  * A small random nudge stops teammates stacking on the same pad.
	  * A short, visible spawn-protection bubble (ForceField). Weapon damage
	    goes through Humanoid:TakeDamage, which a ForceField blocks.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpawnConfig = require(ReplicatedStorage.Shared.Config.SpawnConfig)
local MatchState = require(ReplicatedStorage.Shared.Match.MatchState)

type TeamId = MatchState.TeamId

type RankedSpawn = {
	point: BasePart,
	distance: number,
}

local SpawnService = {}

local spawnPoints: { BasePart } = {}
local random = Random.new()

function SpawnService.init(points: { BasePart })
	assert(#points > 0, "SpawnService needs at least one spawn point")
	spawnPoints = points
end

local function isOnTeamSide(point: BasePart, team: TeamId?): boolean
	if team == "A" then
		return point.Position.X < 0
	elseif team == "B" then
		return point.Position.X > 0
	end
	return true
end

-- Positions of every living player who is NOT on `team` (and isn't `player`).
local function enemyPositions(player: Player, team: TeamId?): { Vector3 }
	local positions: { Vector3 } = {}
	for _, other in Players:GetPlayers() do
		if other == player or (team ~= nil and MatchState.toTeam(other:GetAttribute(MatchState.PlayerAttr.Team)) == team) then
			continue
		end
		local character = other.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			table.insert(positions, root.Position)
		end
	end
	return positions
end

function SpawnService.chooseSpawn(player: Player, team: TeamId?): CFrame
	local allowed: { BasePart } = {}
	for _, point in spawnPoints do
		if isOnTeamSide(point, team) then
			table.insert(allowed, point)
		end
	end
	if #allowed == 0 then
		allowed = spawnPoints
	end

	local enemies = enemyPositions(player, team)
	local ranked: { RankedSpawn } = {}
	for _, point in allowed do
		local nearest = math.huge
		for _, position in enemies do
			nearest = math.min(nearest, (position - point.Position).Magnitude)
		end
		table.insert(ranked, { point = point, distance = nearest })
	end
	table.sort(ranked, function(a: RankedSpawn, b: RankedSpawn): boolean
		return a.distance > b.distance
	end)

	local chosen = ranked[random:NextInteger(1, math.min(SpawnConfig.SAFE_SPAWN_CHOICES, #ranked))]
	local spread = SpawnConfig.SPAWN_SPREAD
	local nudge = Vector3.new(random:NextNumber(-spread, spread), 4, random:NextNumber(-spread, spread))
	-- Keep the pad's facing (pads face the middle of the map), lifted so feet land on the floor.
	return chosen.point.CFrame + nudge
end

local function giveSpawnProtection(character: Model)
	local forceField = Instance.new("ForceField")
	forceField.Visible = true
	forceField.Parent = character
	character:SetAttribute(MatchState.PROTECTED_ATTR, true)
	task.delay(SpawnConfig.SPAWN_PROTECTION, function()
		forceField:Destroy()
		character:SetAttribute(MatchState.PROTECTED_ATTR, false)
	end)
end

--[[
	Gives the player a fresh character (full health; WeaponService refills
	ammo on every new character) at a spawn point for `team`.
	Yields until the character exists. Returns it, or nil if they left.
]]
function SpawnService.spawn(player: Player, team: TeamId?): Model?
	if player.Parent ~= Players then
		return nil
	end
	local spawnCFrame = SpawnService.chooseSpawn(player, team)
	player:LoadCharacter()
	local character = player.Character
	if not character or player.Parent ~= Players then
		return nil
	end
	character:PivotTo(spawnCFrame)
	giveSpawnProtection(character)
	return character
end

return SpawnService
