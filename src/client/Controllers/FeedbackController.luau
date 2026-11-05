--!strict
--[[
	FeedbackController: sounds and the elimination pop-up.

	  * Plays movement sounds (jump, land, dash) for your own slime, and
	    match sounds (countdown ticks, GO, match found, victory/defeat).
	  * When YOU eliminate someone (seen in the server's kill feed), shows a
	    short "ELIMINATED <name>" pop-up with a sound.
	  * Volume = sound volume x category volume x master volume. Categories
	    can be changed with SoundController-style attributes on the player
	    ("VolumeWeapons", "VolumeMaster", ...), ready for a Settings menu.
	Sounds are reused (one Sound object per sound) so nothing piles up.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoundConfig = require(Shared:WaitForChild("Config"):WaitForChild("SoundConfig"))
local MatchState = require(Shared:WaitForChild("Match"):WaitForChild("MatchState"))
local GameContract = require(Shared:WaitForChild("Net"):WaitForChild("GameContract"))

local player = Players.LocalPlayer
local soundCache: { [string]: Sound } = {}

local FeedbackController = {}
local started = false

local function categoryVolume(category: string): number
	local function read(name: string): number
		local value = player:GetAttribute("Volume" .. name)
		return if typeof(value) == "number" then math.clamp(value, 0, 1) else (SoundConfig.Volumes[name] or 1)
	end
	return read("Master") * read(category)
end

function FeedbackController.play(name: string)
	local info = SoundConfig.Sounds[name]
	if not info or info.Id == "" then
		return -- unknown or a silent placeholder
	end
	local sound = soundCache[name]
	if not sound then
		local newSound = Instance.new("Sound")
		newSound.Name = name
		newSound.SoundId = info.Id
		newSound.Parent = SoundService
		soundCache[name] = newSound
		sound = newSound
	end
	sound.Volume = info.Volume * categoryVolume(info.Category)
	sound.PlaybackSpeed = info.Pitch
	SoundService:PlayLocalSound(sound) -- lets the same sound overlap itself
end

local function buildToast(): (string) -> ()
	local gui = Instance.new("ScreenGui")
	gui.Name = "EliminationToast"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 4
	gui.Parent = player:WaitForChild("PlayerGui")
	local text = Instance.new("TextLabel")
	text.AnchorPoint = Vector2.new(0.5, 0.5)
	text.Position = UDim2.fromScale(0.5, 0.68)
	text.Size = UDim2.fromOffset(520, 40)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextSize = 30
	text.TextColor3 = Color3.fromRGB(255, 120, 120)
	text.TextStrokeTransparency = 0.3
	text.TextTransparency = 1
	text.TextStrokeColor3 = Color3.fromRGB(40, 20, 30)
	text.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Parent = text
	local fade: Tween? = nil
	return function(victimName: string)
		text.Text = `ELIMINATED {string.upper(victimName)}`
		text.TextTransparency = 0
		text.TextStrokeTransparency = 0.3
		scale.Scale = 1.3
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		if fade then
			fade:Cancel()
		end
		local newFade = TweenService:Create(text, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.2), { TextTransparency = 1, TextStrokeTransparency = 1 })
		fade = newFade
		newFade:Play()
	end
end

local function watchCharacter(character: Model)
	local found = character:WaitForChild("Humanoid", 10)
	if not found or not found:IsA("Humanoid") then
		return
	end
	local humanoid = found :: Humanoid
	humanoid.StateChanged:Connect(function(_old: Enum.HumanoidStateType, new: Enum.HumanoidStateType)
		if new == Enum.HumanoidStateType.Jumping then
			FeedbackController.play("Jump")
		elseif new == Enum.HumanoidStateType.Landed then
			FeedbackController.play("Land")
		end
	end)
end

function FeedbackController.start()
	if started then
		return
	end
	started = true

	-- Elimination pop-up: the server's kill feed says who eliminated whom.
	local showToast = buildToast()
	GameContract.getRemote(GameContract.RemoteNames.KillFeed).OnClientEvent:Connect(function(killer: unknown, victim: unknown)
		if killer == player.DisplayName and typeof(victim) == "string" then
			showToast(string.sub(victim, 1, 20))
			FeedbackController.play("Elimination")
		end
	end)

	-- Movement sounds for your own slime.
	player.CharacterAdded:Connect(watchCharacter)
	if player.Character then
		task.spawn(watchCharacter, player.Character)
	end
	player:GetAttributeChangedSignal("DashedAt"):Connect(function()
		FeedbackController.play("Dash")
	end)

	-- Match sounds.
	local stateFolder = ReplicatedStorage:WaitForChild(MatchState.FOLDER_NAME)
	local lastTick = -1
	stateFolder:GetAttributeChangedSignal(MatchState.Attr.State):Connect(function()
		if MatchState.toTeam(player:GetAttribute(MatchState.PlayerAttr.Team)) == nil then
			return
		end
		local state = MatchState.toState(stateFolder:GetAttribute(MatchState.Attr.State))
		if state == "MatchFound" then
			FeedbackController.play("MatchFound")
		elseif state == "InMatch" then
			FeedbackController.play("Go")
		elseif state == "MatchResults" then
			local winner = MatchState.toTeam(stateFolder:GetAttribute(MatchState.Attr.MatchWinner))
			local mine = MatchState.toTeam(player:GetAttribute(MatchState.PlayerAttr.Team))
			FeedbackController.play(if winner ~= nil and winner == mine then "Victory" else "Defeat")
		end
		lastTick = -1
	end)
	-- Countdown ticks (3, 2, 1).
	task.spawn(function()
		while true do
			local state = MatchState.toState(stateFolder:GetAttribute(MatchState.Attr.State))
			if state == "Countdown" and MatchState.toTeam(player:GetAttribute(MatchState.PlayerAttr.Team)) then
				local endsAt = stateFolder:GetAttribute(MatchState.Attr.PhaseEndsAt)
				local secondsLeft = if typeof(endsAt) == "number" then math.ceil(endsAt - Workspace:GetServerTimeNow()) else 0
				if secondsLeft > 0 and secondsLeft ~= lastTick then
					lastTick = secondsLeft
					FeedbackController.play("CountdownTick")
				end
			end
			task.wait(0.1)
		end
	end)
end

return FeedbackController
