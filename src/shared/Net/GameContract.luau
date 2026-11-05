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
	    All remotes are listed in Shared/Net/Net.luau.
	  * The Play button fires the PlayPressed RemoteEvent (client -> server).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = require(script.Parent:WaitForChild("Net"))

local GameContract = {}

GameContract.PlayerAttributes = {
	-- Saved, lifetime
	LifetimeEliminations = "LifetimeEliminations",
	Wins = "Wins",
	Coins = "Coins",
	XP = "XP", -- total experience (saved); level comes from Data/Progression
	DailyReadyAt = "DailyReadyAt", -- unix time when the next Daily Squishy can be opened
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
	EquippedTopping = "EquippedTopping",
}

GameContract.WeaponAttributes = {
	Ammo = "Ammo",
	MaxAmmo = "MaxAmmo",
	ReserveAmmo = "ReserveAmmo",
}

GameContract.RoundEndsAtAttribute = "RoundEndsAt"

GameContract.RemoteNames = {
	KillFeed = "KillFeed",
	PlayPressed = "PlayPressed",
}

--[[
	Returns one of the game's RemoteEvents (KillFeed, PlayPressed).
	They are created by the central list in Shared/Net/Net.luau.
]]
function GameContract.getRemote(name: string): RemoteEvent
	return Net.event(name :: Net.EventName)
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
