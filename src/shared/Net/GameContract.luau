--!strict
--[[
	GameContract
	============
	One place that lists the names the server and the UI agree on:
	attribute names, remote event names, and the round timer.

	How information reaches the UI:
	  * Lifetime stats and round stats are ATTRIBUTES on each Player.
	    The server sets them; they copy to every client automatically.
	    (If a client changes them, the change stays on that client only.)
	  * Ammo is read from attributes on the character, or on the Tool
	    the player is holding:  Ammo  and  MaxAmmo  (numbers).
	  * The round timer is the  RoundEndsAt  attribute on ReplicatedStorage,
	    measured with workspace:GetServerTimeNow(). Leave it unset (nil)
	    to hide the timer.
	  * The kill feed uses the KillFeed RemoteEvent (server -> clients).
	  * The Play button fires the PlayPressed RemoteEvent (client -> server).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameContract = {}

GameContract.PlayerAttributes = {
	-- Saved, lifetime
	LifetimeEliminations = "LifetimeEliminations",
	Wins = "Wins",
	Coins = "Coins",
	DataLoaded = "DataLoaded",
	-- This round only
	RoundEliminations = "RoundEliminations",
	RoundDeaths = "RoundDeaths",
	-- Set to true once the player presses Play on the main menu
	PressedPlay = "PressedPlay",
	-- Shop (saved). OwnedItems is a comma-separated list of item Ids.
	OwnedItems = "OwnedItems",
	EquippedColor = "EquippedColor",
	EquippedHat = "EquippedHat",
	EquippedSkin = "EquippedSkin",
}

GameContract.WeaponAttributes = {
	Ammo = "Ammo",
	MaxAmmo = "MaxAmmo",
}

GameContract.RoundEndsAtAttribute = "RoundEndsAt"

GameContract.RemoteNames = {
	KillFeed = "KillFeed",
	PlayPressed = "PlayPressed",
}

local REMOTES_FOLDER_NAME = "GameRemotes"

local function getRemotesFolder(): Instance
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild(REMOTES_FOLDER_NAME)
		if existing then
			return existing
		end
		local folder = Instance.new("Folder")
		folder.Name = REMOTES_FOLDER_NAME
		folder.Parent = ReplicatedStorage
		return folder
	end
	return ReplicatedStorage:WaitForChild(REMOTES_FOLDER_NAME)
end

--[[
	On the server: finds or creates the RemoteEvent.
	On the client: waits for the server to create it.
]]
function GameContract.getRemote(name: string): RemoteEvent
	local folder = getRemotesFolder()
	if RunService:IsServer() then
		local existing = folder:FindFirstChild(name)
		if existing and existing:IsA("RemoteEvent") then
			return existing
		end
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
		return remote
	end
	return folder:WaitForChild(name) :: RemoteEvent
end

--[[
	Server only. Starts the round timer counting down from `seconds`.
	Pass nil to hide the timer (for example between rounds).
]]
function GameContract.setRoundTimeRemaining(seconds: number?)
	assert(RunService:IsServer(), "setRoundTimeRemaining must be called on the server")
	if seconds == nil then
		ReplicatedStorage:SetAttribute(GameContract.RoundEndsAtAttribute, nil)
	else
		ReplicatedStorage:SetAttribute(GameContract.RoundEndsAtAttribute, workspace:GetServerTimeNow() + seconds)
	end
end

-- Seconds left in the round, or nil when no round timer is running.
function GameContract.getRoundTimeRemaining(): number?
	local endsAt = ReplicatedStorage:GetAttribute(GameContract.RoundEndsAtAttribute)
	if typeof(endsAt) ~= "number" then
		return nil
	end
	return math.max(0, endsAt - workspace:GetServerTimeNow())
end

return GameContract
