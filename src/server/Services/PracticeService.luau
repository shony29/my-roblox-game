--!strict
--[[
	PracticeService: the practice range (Map/PracticeRangeBuilder).

	  * Go there: step on the glowing PRACTICE RANGE pad in the lobby, or
	    press "Go to the range" in the Tasks panel. You get your guns, a
	    first-person camera and endless spare ammo. Nobody can be hurt here.
	  * Shoot the slime targets and bullseyes: they pop (counting toward the
	    "Pop practice targets" task) and come back a moment later.
	  * Leave: the BACK TO LOBBY pad, or the LEAVE RANGE button.
	  * Fall off, or reset? You're put back on the deck.

	The server decides all of it; the client can only ask to go or leave.
	Player status while here: "Practice" (MatchState.PlayerAttr.Status).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local MatchState = require(Shared.Match.MatchState)
local Net = require(Shared.Net.Net)
local RateLimiter = require(script.Parent.Parent.Components.RateLimiter)
local PracticeRangeBuilder = require(script.Parent.Parent.Map.PracticeRangeBuilder)
local LobbyService = require(script.Parent.LobbyService)
local QuestService = require(script.Parent.QuestService)

local PATTR = MatchState.PlayerAttr
local CHECK_INTERVAL = 0.25
local POP_TIME = 2.5 -- seconds before a popped target comes back
local PAD_RADIUS = 4
local FALL_LIMIT = 60 -- studs below the deck that count as "fell off"
local RESPAWN_DELAY = 2

local PracticeService = {}

local range: PracticeRangeBuilder.Range? = nil
local popped: { [Model]: boolean } = {}
local deadSince: { [Player]: number } = {}
local busy: { [Player]: boolean } = {} -- moving between lobby and range right now
local limiter = RateLimiter.new(2, 3)
local started = false

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function standingOn(player: Player, pad: BasePart): boolean
	local root = rootOf(player)
	if not root then
		return false
	end
	local offset = root.Position - pad.Position
	return Vector2.new(offset.X, offset.Z).Magnitude <= PAD_RADIUS and math.abs(offset.Y) <= 6
end

-- A fresh character on the deck (guns are given by WeaponService on spawn).
local function spawnOnDeck(player: Player)
	local current = range
	if current == nil then
		return
	end
	local target = current.spawnCFrame + Vector3.new(math.random(-6, 6), 0, math.random(-3, 3))
	LobbyService.streamAround(player, target.Position)
	if player.Parent ~= Players or player:GetAttribute(PATTR.Status) ~= "Practice" then
		return
	end
	player:LoadCharacter()
	local character = player.Character
	if character and player:GetAttribute(PATTR.Status) == "Practice" then
		character:PivotTo(target)
	end
end

function PracticeService.enter(player: Player)
	local status = player:GetAttribute(PATTR.Status)
	if range == nil or busy[player] or player.Parent ~= Players or (status ~= "Lobby" and status ~= "Queued") then
		return
	end
	busy[player] = true
	-- (Were they in a queue? QueueService drops anyone who isn't "Queued" any more.)
	player:SetAttribute(PATTR.Status, "Practice")
	LobbyService.useMatchCamera(player)
	spawnOnDeck(player)
	busy[player] = nil
	QuestService.progress(player, "VisitRange")
end

function PracticeService.leave(player: Player)
	if busy[player] or player:GetAttribute(PATTR.Status) ~= "Practice" then
		return
	end
	busy[player] = true
	player:SetAttribute(PATTR.Status, "Lobby")
	LobbyService.spawn(player)
	busy[player] = nil
end

--[[
	Called by WeaponService when a bullet hits a part with the
	"PracticeTarget" attribute. Pops the target if the shooter is at the range.
]]
function PracticeService.hitTarget(player: Player, part: Instance)
	local current = range
	if current == nil or player:GetAttribute(PATTR.Status) ~= "Practice" then
		return
	end
	local target = part:FindFirstAncestorOfClass("Model")
	if target == nil or popped[target] or not target:IsDescendantOf(current.model) then
		return
	end
	popped[target] = true
	local parent = target.Parent
	local color = if part:IsA("BasePart") then part.Color else Color3.new(1, 0.3, 0.4)
	Net.event("TargetPop"):FireAllClients(target:GetPivot().Position, color)
	target.Parent = nil
	QuestService.progress(player, "BreakTargets")
	task.delay(POP_TIME, function()
		popped[target] = nil
		if current.model.Parent then
			target.Parent = parent
		end
	end)
end

local function checkPlayers()
	local current = range
	if current == nil then
		return
	end
	local lobbyPad = LobbyService.getRangePad()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local status = player:GetAttribute(PATTR.Status)
		if busy[player] then
			continue
		end
		if status == "Lobby" and lobbyPad and standingOn(player, lobbyPad) then
			task.spawn(PracticeService.enter, player)
		elseif status == "Practice" then
			local character = player.Character
			local humanoid = character and character:FindFirstChildOfClass("Humanoid")
			local root = rootOf(player)
			if not root or not humanoid or humanoid.Health <= 0 then
				-- Reset (or lost their character): back on the deck shortly.
				local since = deadSince[player] or now
				deadSince[player] = since
				if now - since >= RESPAWN_DELAY then
					deadSince[player] = nil
					busy[player] = true
					task.spawn(function()
						spawnOnDeck(player)
						busy[player] = nil
					end)
				end
			else
				deadSince[player] = nil
				local exitPad = current.exitPad
				if exitPad and standingOn(player, exitPad) then
					task.spawn(PracticeService.leave, player)
				elseif root.Position.Y < current.origin.Y - FALL_LIMIT and character then
					root.AssemblyLinearVelocity = Vector3.zero
					character:PivotTo(current.spawnCFrame)
				end
			end
		end
	end
end

function PracticeService.start()
	if started then
		return
	end
	started = true
	local ok, result = pcall(PracticeRangeBuilder.build)
	if not ok then
		error(`the practice range could not be built: {result}`)
	end
	range = result
	local built = result :: PracticeRangeBuilder.Range
	if #built.problems > 0 then
		local text = table.concat(built.problems, "  |  ")
		ReplicatedStorage:SetAttribute("RangeProblems", string.sub(text, 1, 300))
	end

	Net.event("PracticeEnter").OnServerEvent:Connect(function(player: Player)
		if limiter:allow(player) then
			PracticeService.enter(player)
		end
	end)
	Net.event("PracticeLeave").OnServerEvent:Connect(function(player: Player)
		if limiter:allow(player) then
			PracticeService.leave(player)
		end
	end)
	Players.PlayerRemoving:Connect(function(player: Player)
		deadSince[player] = nil
		busy[player] = nil
	end)
	task.spawn(function()
		while true do
			local okCheck, err = pcall(checkPlayers)
			if not okCheck then
				warn("[PracticeService] check failed:", err)
			end
			task.wait(CHECK_INTERVAL)
		end
	end)
end

return PracticeService
