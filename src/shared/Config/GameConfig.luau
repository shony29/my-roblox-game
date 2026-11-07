--!strict
--[[
	GameConfig: game-wide settings that don't belong to one system.
	Read by both the server and the client.
]]

local GameConfig = table.freeze({
	GameName = "Slime Showdown",
	-- Shown in the corner of the main menu. Bump it with every update, so
	-- you can tell at a glance that Studio has the newest code.
	Version = "0.9.5",

	-- Print extra "[debug]" lines in the Output window while developing.
	DebugLogging = false,

	-- How long a client waits for something the server creates (a remote,
	-- a folder) before giving up with a clear error, in seconds. Avoids
	-- waiting forever if something is misnamed.
	ClientWaitTimeout = 30,
})

return GameConfig
