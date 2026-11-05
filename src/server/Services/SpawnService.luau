--!strict
-- SpawnService: picks a safe spawn point and (re)spawns players there
-- with a short burst of spawn protection.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RoundConfig = require(ReplicatedStorage.Shared.Config.RoundConfig)
local RoundState = require(ReplicatedStorage.Shared.Match.RoundState)

local SpawnService = {}

type RankedSpawn = {
	point: BasePart,
	distance: number,
}

local spawnPoints: { BasePart } = {}
local random = Random.new()

function SpawnService.init(points: { BasePart })
	assert(#points > 0, "SpawnService needs at least one spawn point")
	spawnPoints = points
end

-- Positions of every *other* player who is alive right now.
local function enemyPositions(player: Player): { Vector3 }
	local positions: { Vector3 } = {}
	for _, other in Players:GetPlayers() do
		if other == player then
			continue
		end
		local character = other.Character
		if not character then
			continue
		end
		local root = character:FindFirstChild("HumanoidRootPart")
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if root and root:IsA("BasePart") and humanoid and humanoid.Health > 0 then
			table.insert(positions, root.Position)
		end
	end
	return positions
end

-- Scores each spawn by how far it is from the closest enemy, then picks
-- randomly among the few safest ones.
function SpawnService.chooseSpawn(player: Player): CFrame
	local enemies = enemyPositions(player)

	local ranked: { RankedSpawn } = {}
	for _, point in spawnPoints do
		local nearest = math.huge
		for _, position in enemies do
			nearest = math.min(nearest, (position - point.Position).Magnitude)
		end
		table.insert(ranked, { point = point, distance = nearest })
	end
	table.sort(ranked, function(a: RankedSpawn, b: RankedSpawn): boolean
		return a.distance > b.distance
	end)

	local choices = math.min(RoundConfig.SAFE_SPAWN_CHOICES, #ranked)
	local chosen = ranked[random:NextInteger(1, choices)]
	-- Lift the character above the pad so its feet land on the floor.
	return chosen.point.CFrame + Vector3.new(0, 4, 0)
end

-- A visible bubble for a couple of seconds. A ForceField stops all damage
-- that goes through Humanoid:TakeDamage, which is what blasters should use.
local function giveSpawnProtection(character: Model)
	local forceField = Instance.new("ForceField")
	forceField.Visible = true
	forceField.Parent = character
	character:SetAttribute(RoundState.PROTECTED_ATTR, true)

	task.delay(RoundConfig.SPAWN_PROTECTION, function()
		forceField:Destroy()
		character:SetAttribute(RoundState.PROTECTED_ATTR, false)
	end)
end

-- Gives the player a fresh character at a safe spawn point.
function SpawnService.spawn(player: Player)
	if player.Parent ~= Players then
		return -- they left the game
	end
	local spawnCFrame = SpawnService.chooseSpawn(player)
	player:LoadCharacter() -- waits until the new character exists
	local character = player.Character
	if not character then
		return
	end
	character:PivotTo(spawnCFrame)
	giveSpawnProtection(character)
end

return SpawnService
