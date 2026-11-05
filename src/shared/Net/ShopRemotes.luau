--!strict
--[[
	ShopRemotes: the shop's two remotes (listed in Shared/Net/Net.luau).
	The client can only ASK; the server decides.

	  BuyItem    client -> server  (itemId)  returns (ok, message)
	  EquipItem  client -> server  (itemId)  returns (ok, message)

	What the player owns and wears is shared through attributes on the
	Player (see Shared/Net/GameContract).
]]

local Net = require(script.Parent:WaitForChild("Net"))

export type Remotes = {
	BuyItem: RemoteFunction,
	EquipItem: RemoteFunction,
}

local cached: Remotes? = nil

local ShopRemotes = {}

function ShopRemotes.get(): Remotes
	if cached then
		return cached
	end
	local remotes: Remotes = {
		BuyItem = Net.func("ShopBuyItem"),
		EquipItem = Net.func("ShopEquipItem"),
	}
	cached = remotes
	return remotes
end

return ShopRemotes
