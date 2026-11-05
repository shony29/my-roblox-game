--!strict
--[[
	DataController
	Keeps the latest copy of *your* progress (coins, owned colors...) that
	the server sends, and tells the HUD and shop when it changes.
	This is display-only: the real numbers live on the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local DataController = {}

local current: Types.PublicData? = nil
local listeners: { (Types.PublicData) -> () } = {}

local function set(data: Types.PublicData)
	current = data
	for _, listener in listeners do
		task.spawn(listener, data)
	end
end

function DataController.get(): Types.PublicData?
	return current
end

-- Calls `listener` now (if data has arrived) and whenever it changes.
function DataController.onChanged(listener: (Types.PublicData) -> ())
	table.insert(listeners, listener)
	if current then
		task.spawn(listener, current)
	end
end

function DataController.start()
	Remotes.event("DataChanged").OnClientEvent:Connect(function(data: Types.PublicData)
		set(data)
	end)
	-- Ask once at startup, in case the server sent our data before we were listening.
	task.spawn(function()
		local data: Types.PublicData? = Remotes.func("GetData"):InvokeServer()
		if data and not current then
			set(data)
		end
	end)
end

return DataController
