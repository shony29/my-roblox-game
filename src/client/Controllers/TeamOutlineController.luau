--!strict
--[[
	TeamOutlineController: coloured outlines so you can tell teams apart at
	a glance (Blue vs Red), on players and bots.

	  * Teammates: outlined in your team's colour, visible through walls,
	    so you always know where your team is.
	  * Enemies: outlined in their team's colour, but only where you can
	    actually see them (no seeing enemies through walls).
	  * No outlines in the lobby, or on your own slime.
	Purely visual, made on this screen only.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MatchState = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Match"):WaitForChild("MatchState"))

local OUTLINE_NAME = "TeamOutline"
local REFRESH_INTERVAL = 0.5

local player = Players.LocalPlayer

local TeamOutlineController = {}
local started = false

local function teamOf(character: Instance): MatchState.TeamId?
	local owner = if character:IsA("Model") then Players:GetPlayerFromCharacter(character) else nil
	if owner then
		return MatchState.toTeam(owner:GetAttribute(MatchState.PlayerAttr.Team))
	end
	return MatchState.toTeam(character:GetAttribute("BotTeam"))
end

local function refresh()
	local myTeam = MatchState.toTeam(player:GetAttribute(MatchState.PlayerAttr.Team))
	for _, blob in CollectionService:GetTagged("Blob") do
		local character = blob.Parent
		if not character then
			continue
		end
		local team = if myTeam then teamOf(character) else nil
		local outline = blob:FindFirstChild(OUTLINE_NAME)
		if team == nil or character == player.Character then
			if outline then
				outline:Destroy()
			end
			continue
		end
		local highlight: Highlight
		if outline and outline:IsA("Highlight") then
			highlight = outline
		else
			highlight = Instance.new("Highlight")
			highlight.Name = OUTLINE_NAME
			highlight.FillTransparency = 1 -- outline only
			highlight.OutlineTransparency = 0
			highlight.Adornee = blob -- the visible slime, not the hidden body
			highlight.Parent = blob
		end
		-- Free for all: everyone is an enemy (red, and never seen through walls).
		local freeForAll = ReplicatedStorage:FindFirstChild(MatchState.FOLDER_NAME) ~= nil
			and (ReplicatedStorage :: any)[MatchState.FOLDER_NAME]:GetAttribute(MatchState.Attr.Mode) == "FreeForAll"
		local ally = team == myTeam and not freeForAll
		highlight.OutlineColor = if freeForAll then MatchState.teamInfo("B").Color else MatchState.teamInfo(team).Color
		highlight.DepthMode = if ally
			then Enum.HighlightDepthMode.AlwaysOnTop
			else Enum.HighlightDepthMode.Occluded
	end
end

function TeamOutlineController.start()
	if started then
		return
	end
	started = true
	task.spawn(function()
		while true do
			refresh()
			task.wait(REFRESH_INTERVAL)
		end
	end)
end

return TeamOutlineController
