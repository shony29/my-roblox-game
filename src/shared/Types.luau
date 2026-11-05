--!strict
--[[
	Types
	Shared "shapes" of data. Writing them down once lets the type checker
	catch mistakes like misspelling `Coins` as `Coin`.
]]

-- What we save in the DataStore for each player.
export type PlayerData = {
	Version: number, -- bump when the save format changes, so old saves can be upgraded
	Coins: number,
	Kills: number,
	Deaths: number,
	OwnedColors: { [string]: boolean }, -- e.g. { Lime = true, Grape = true }
	EquippedColor: string,
}

-- What the server sends to a player's own client about their progress.
export type PublicData = {
	Coins: number,
	Kills: number,
	Deaths: number,
	OwnedColors: { [string]: boolean },
	EquippedColor: string,
	SavingEnabled: boolean, -- false if loading failed (e.g. Studio without API access)
}

-- One color you can buy for your jelly in the shop.
export type ColorItem = {
	Id: string,
	DisplayName: string,
	Color: Color3,
	Price: number,
}

return {}
