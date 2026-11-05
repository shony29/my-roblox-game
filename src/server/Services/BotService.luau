--!strict
--[[
	BotService: practice opponents (and teammates) run by the server.

	A bot is a real slime: the same rig, blob and gun as a player. Every
	0.1 s each bot:
	  * picks the nearest living enemy (players or bots on the other team),
	  * if it can see them: strafes while keeping a medium distance, turns to
	    face them and shoots after a short reaction delay, with some spread,
	  * otherwise walks toward them, and jumps if it gets stuck.
	Bots only act while MatchService says a round is running (setActive),
	never hurt teammates, and deal less damage than players so they're
	beatable. Shots use the same "what can bullets hit" rules as players.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local WeaponConfig = require(Shared.Config.WeaponConfig)
local WeaponMath = require(Shared.Combat.WeaponMath)
local HitGroups = require(Shared.Combat.HitGroups)
local WeaponRemotes = require(Shared.Net.WeaponRemotes)
local MatchState = require(Shared.Match.MatchState)
local Components = script.Parent.Parent.Components
local SlimeRig = require(Components.SlimeRig)
local BlobCharacter = require(Components.BlobCharacter)
local GunModel = require(Components.GunModel)

type TeamId = MatchState.TeamId

type Bot = {
	model: Model,
	humanoid: Humanoid,
	root: BasePart,
	head: BasePart,
	team: TeamId,
	name: string,
	nextShotAt: number,
	reactAt: number,
	sawTargetLast: boolean,
	strafe: number,
	nextStrafeSwap: number,
	lastPosition: Vector3,
}

local THINK_INTERVAL = 0.1
local WEAPON_ID = "Rifle"
local FIRE_RATE = 4 -- shots per second (players' rifle: 10)
local DAMAGE_SCALE = 0.6 -- bots hit softer than players
local REACTION_TIME = 0.45 -- seconds before shooting a newly seen enemy
local BASE_SPREAD = 4 -- degrees
local SPREAD_PER_STUD = 0.04
local PREFERRED_DISTANCE = 24
local NAMES = { "Bloop", "Gloop", "Wobble", "Jiggles", "Squish", "Mochi", "Jelly", "Puddle" }

local BotService = {}

local bots: { [Model]: Bot } = {}
local active = false
local random = Random.new()
local nameIndex = 0

-- MatchService turns bots on only while a round is running.
function BotService.setActive(value: boolean)
	active = value
end

function BotService.teamOf(model: Instance): TeamId?
	return MatchState.toTeam(model:GetAttribute("BotTeam"))
end

local function teamOfCharacter(model: Model): TeamId?
	local player = Players:GetPlayerFromCharacter(model)
	if player then
		return MatchState.toTeam(player:GetAttribute(MatchState.PlayerAttr.Team))
	end
	return BotService.teamOf(model)
end

local function aliveHumanoid(model: Model): Humanoid?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	return if humanoid and humanoid.Health > 0 then humanoid else nil
end

-- Where to aim on a slime: the middle of its hitbox ("Body"), else its root.
local function aimPoint(model: Model): Vector3?
	local blob = model:FindFirstChild("Blob")
	local hitbox = blob and blob:FindFirstChild("Body")
	if hitbox and hitbox:IsA("BasePart") then
		return hitbox.Position
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root.Position else nil
end

local function enemiesOf(bot: Bot): { Model }
	local list: { Model } = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local team = MatchState.toTeam(player:GetAttribute(MatchState.PlayerAttr.Team))
		if character and team and team ~= bot.team and aliveHumanoid(character) then
			table.insert(list, character)
		end
	end
	for model, other in bots do
		if other.team ~= bot.team and aliveHumanoid(model) then
			table.insert(list, model)
		end
	end
	return list
end

local function canSee(bot: Bot, target: Model, point: Vector3): boolean
	local result = Workspace:Raycast(bot.head.Position, point - bot.head.Position, HitGroups.weaponRayParams({ bot.model }))
	return result ~= nil and result.Instance:IsDescendantOf(target)
end

local function findHumanoid(part: Instance): Humanoid?
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return humanoid
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return nil
end

local function shoot(bot: Bot, point: Vector3)
	local stats = WeaponConfig.get(WEAPON_ID)
	if not stats then
		return
	end
	local origin = bot.head.Position
	local distance = (point - origin).Magnitude
	local direction = WeaponMath.applySpread(point - origin, BASE_SPREAD + distance * SPREAD_PER_STUD, random)
	local result = Workspace:Raycast(origin, direction * stats.MaxRange, HitGroups.weaponRayParams({ bot.model }))
	local endPoint = if result then result.Position else origin + direction * stats.MaxRange
	if result then
		local humanoid = findHumanoid(result.Instance)
		local victim = humanoid and humanoid.Parent
		if humanoid and humanoid.Health > 0 and victim and victim:IsA("Model") and teamOfCharacter(victim) ~= bot.team then
			humanoid:SetAttribute("LastHitBy", bot.name) -- for the kill feed
			humanoid:TakeDamage(WeaponMath.damageAtDistance(stats, result.Distance) * DAMAGE_SCALE)
		end
	end
	local gun = bot.model:FindFirstChild(GunModel.NAME)
	local muzzle = gun and gun:FindFirstChild("Muzzle", true)
	local start = if muzzle and muzzle:IsA("Attachment") then muzzle.WorldPosition else origin
	WeaponRemotes.get().ShotFx:FireAllClients(bot.model, WEAPON_ID, start, { endPoint })
end

local function think(bot: Bot, now: number)
	if not active or bot.root.Anchored then
		bot.humanoid:Move(Vector3.zero)
		return
	end
	-- Nearest enemy, preferring one we can see.
	local best: Model?, bestPoint: Vector3?, bestDistance, bestVisible = nil, nil, math.huge, false
	for _, enemy in enemiesOf(bot) do
		local point = aimPoint(enemy)
		if point then
			local distance = (point - bot.root.Position).Magnitude
			local visible = canSee(bot, enemy, point)
			if (visible and not bestVisible) or (visible == bestVisible and distance < bestDistance) then
				best, bestPoint, bestDistance, bestVisible = enemy, point, distance, visible
			end
		end
	end
	if not best or not bestPoint then
		bot.humanoid:Move(Vector3.zero)
		return
	end

	local flatToTarget = Vector3.new(bestPoint.X - bot.root.Position.X, 0, bestPoint.Z - bot.root.Position.Z)
	local forward = if flatToTarget.Magnitude > 0.1 then flatToTarget.Unit else bot.root.CFrame.LookVector
	if bestVisible then
		-- Face the target, strafe, and hold a medium distance.
		bot.root.CFrame = CFrame.lookAt(bot.root.Position, bot.root.Position + forward)
		if now >= bot.nextStrafeSwap then
			bot.strafe = if random:NextNumber() < 0.5 then -1 else 1
			bot.nextStrafeSwap = now + random:NextNumber(0.8, 1.8)
		end
		local side = forward:Cross(Vector3.yAxis) * bot.strafe
		local approach = if bestDistance > PREFERRED_DISTANCE + 8 then 1 elseif bestDistance < PREFERRED_DISTANCE - 10 then -1 else 0
		bot.humanoid:Move((side + forward * approach).Unit)
		if not bot.sawTargetLast then
			bot.reactAt = now + REACTION_TIME
		end
		if now >= bot.reactAt and now >= bot.nextShotAt then
			bot.nextShotAt = now + 1 / FIRE_RATE
			shoot(bot, bestPoint)
		end
	else
		bot.humanoid:Move(forward)
	end
	bot.sawTargetLast = bestVisible

	-- Stuck against something? Hop.
	if (bot.root.Position - bot.lastPosition).Magnitude < 0.3 and bot.humanoid.MoveDirection.Magnitude > 0 then
		bot.humanoid.Jump = true
	end
	bot.lastPosition = bot.root.Position
end

--[[
	Creates a bot for `team` at `cframe` and returns its character model.
	It stays still until setActive(true) and its root is unanchored.
]]
function BotService.spawn(team: TeamId, cframe: CFrame): Model
	nameIndex += 1
	local name = "Bot " .. NAMES[((nameIndex - 1) % #NAMES) + 1]
	local model = SlimeRig.build()
	model.Name = name
	model:SetAttribute("BotTeam", team)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayName = name
	humanoid.AutoRotate = false -- the bot turns itself to face its target
	model:PivotTo(cframe)
	model.Parent = Workspace
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
	local head = model:FindFirstChild("Head") :: BasePart
	pcall(function()
		root:SetNetworkOwner(nil) -- the server moves bots
	end)
	BlobCharacter.apply(model, MatchState.teamInfo(team).Color:Lerp(BlobCharacter.randomColor(), 0.35))
	local stats = WeaponConfig.get(WEAPON_ID)
	if stats then
		GunModel.attach(model, stats)
	end
	bots[model] = {
		model = model,
		humanoid = humanoid,
		root = root,
		head = head,
		team = team,
		name = name,
		nextShotAt = 0,
		reactAt = 0,
		sawTargetLast = false,
		strafe = 1,
		nextStrafeSwap = 0,
		lastPosition = root.Position,
	}
	humanoid.Died:Once(function()
		bots[model] = nil
	end)
	return model
end

-- After the countdown unanchors a bot, give its physics back to the server.
function BotService.release(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and not root.Anchored then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
end

function BotService.removeAll()
	for model in bots do
		model:Destroy()
	end
	table.clear(bots)
end

local started = false

function BotService.start()
	if started then
		return
	end
	started = true
	local timer = 0
	RunService.Heartbeat:Connect(function(dt: number)
		timer += dt
		if timer < THINK_INTERVAL then
			return
		end
		timer = 0
		local now = os.clock()
		for model, bot in bots do
			if model.Parent and bot.humanoid.Health > 0 then
				think(bot, now)
			end
		end
	end)
end

return BotService
