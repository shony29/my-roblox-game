--!strict
--[[
	ShopController
	==============
	The shop menu on each player's screen.

	  * Open it with the SHOP button on the main menu or in the lobby
	    (left side), or the B key.
	  * Tabs for Colors, Hats and Skins. Each card shows the item, its price,
	    and whether you own it or are wearing it.
	  * Your coins are shown at the top.

	This script decides nothing important. It only ASKS the server to buy or
	equip an item, then shows the answer. What you own, what you wear and
	your coins all come from attributes the server sets on your Player.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ShopConfig = require(Shared:WaitForChild("Config"):WaitForChild("ShopConfig"))
local WeaponConfig = require(Shared:WaitForChild("Config"):WaitForChild("WeaponConfig"))
local UpgradeConfig = require(Shared:WaitForChild("Config"):WaitForChild("UpgradeConfig"))
local ShopRemotes = require(Shared:WaitForChild("Net"):WaitForChild("ShopRemotes"))
local GameContract = require(Shared:WaitForChild("Net"):WaitForChild("GameContract"))

local UIFolder = script.Parent.Parent:WaitForChild("UI")
local Theme = require(UIFolder:WaitForChild("Theme"))
local UIHelpers = require(UIFolder:WaitForChild("UIHelpers"))
local ResponsiveScale = require(UIFolder:WaitForChild("ResponsiveScale"))
local ItemPreview = require(UIFolder:WaitForChild("ItemPreview"))
local RobuxShopConfig = require(Shared:WaitForChild("Config"):WaitForChild("RobuxShopConfig"))

type Category = ShopConfig.Category
type ShopItem = ShopConfig.ShopItem

type Card = {
	item: ShopItem,
	status: TextLabel,
	button: TextButton,
}

local player = Players.LocalPlayer
local Colors = Theme.Colors
local Sci = Theme.SciFi -- the bunker's sci-fi look: dark panels, neon edges
local SCI_FONT = Theme.SciFiFonts.Title
local BODY_FONT = Theme.SciFiFonts.Body
local ATTR = GameContract.PlayerAttributes

local OPEN_KEY = Enum.KeyCode.B
local CONFIRM_SECONDS = 3 -- how long "Tap again to buy" waits for the second tap
local PANEL_SIZE = Vector2.new(880, 540)
local GREY = Theme.SciFi.Grey

-- "Robux" is the ROBUX tab: coin packs and bundles (Config/RobuxShopConfig).
local TABS: { { category: string, title: string } } = {
	{ category = "Color", title = "Colors" },
	{ category = "Hat", title = "Squishies" },
	{ category = "Skin", title = "Skins" },
	{ category = "Weapon", title = "Guns" },
	{ category = "Topping", title = "Toppings" },
	{ category = "Robux", title = "Robux" },
}

local ShopController = {}

local started = false
local isOpen = false
local busy = false -- true while waiting for the server's answer
local confirmingId: string? = nil
local confirmToken = 0
local toastToken = 0

local shopGui: ScreenGui
local panel: Frame
local panelScale: UIScale
local overlay: TextButton
local toast: TextLabel
local cards: { Card } = {}
local tabButtons: { [string]: TextButton } = {}
local pages: { [string]: ScrollingFrame } = {}
local refreshRobuxCards: () -> () = function() end
local hatColorSetters: { (Color3) -> () } = {}
local skinPreviews: { { box: Frame, skin: ShopConfig.SkinItem } } = {}

-- Reading what the server told us ------------------------------------------

local function ownedIds(): { [string]: boolean }
	local set: { [string]: boolean } = {}
	local raw = player:GetAttribute(ATTR.OwnedItems)
	if typeof(raw) == "string" then
		for _, id in string.split(raw, ",") do
			set[id] = true
		end
	end
	return set
end

local function equippedId(category: Category): string
	local attribute = if category == "Color"
		then ATTR.EquippedColor
		elseif category == "Hat" then ATTR.EquippedHat
		elseif category == "Topping" then ATTR.EquippedTopping
		else ATTR.EquippedSkin
	local value = player:GetAttribute(attribute)
	return if typeof(value) == "string" then value else ShopConfig.defaultFor(category)
end

local function coins(): number
	return UIHelpers.numberAttribute(player, ATTR.Coins)
end

-- Small helpers -------------------------------------------------------------

local function makeButton(name: string, text: string, size: UDim2, color: Color3): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.Text = text
	button.Font = SCI_FONT
	button.TextSize = 18
	button.TextColor3 = Sci.Void
	button.BackgroundColor3 = color
	button.AutoButtonColor = false
	button.Size = size
	UIHelpers.corner(button, UDim.new(0, 10))
	local edge = UIHelpers.stroke(button, Color3.new(1, 1, 1), 1.5)
	edge.Transparency = 0.65

	-- A little bounce when you hover or press.
	local scale = Instance.new("UIScale")
	scale.Parent = button
	button.MouseEnter:Connect(function()
		UIHelpers.tween(scale, 0.12, { Scale = 1.05 }, Enum.EasingStyle.Back)
	end)
	button.MouseLeave:Connect(function()
		UIHelpers.tween(scale, 0.12, { Scale = 1 })
	end)
	button.Activated:Connect(function()
		scale.Scale = 0.92
		UIHelpers.tween(scale, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
	end)
	return button
end

local function showToast(text: string, good: boolean)
	toastToken += 1
	local myToken = toastToken
	toast.Text = text
	toast.TextColor3 = if good then Sci.Green else Sci.Red
	toast.TextTransparency = 0
	toast.TextSize = 26
	UIHelpers.tween(toast, 0.25, { TextSize = 22 }, Enum.EasingStyle.Back)
	task.delay(3, function()
		if toastToken == myToken then
			UIHelpers.tween(toast, 0.4, { TextTransparency = 1 })
		end
	end)
end

-- Updating the cards ---------------------------------------------------------

local MONTH_NAMES = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" }

local function refreshCards()
	local owned = ownedIds()
	local myCoins = coins()
	local month = ShopConfig.currentMonth()
	local gunLevels = UpgradeConfig.parse(player:GetAttribute("GunLevels"))
	for _, card in cards do
		local item = card.item
		local isGun = item.Category == "Weapon" -- guns are owned (in your loadout), not worn
		local isEquipped = not isGun and equippedId(item.Category) == item.Id
		local isOwned = item.Price <= 0 or owned[item.Id] == true
		local status, button = card.status, card.button
		-- Monthly themed items only show during their month (or once you own them).
		local cardFrame = button.Parent
		if cardFrame and cardFrame:IsA("GuiObject") then
			cardFrame.Visible = isOwned or ShopConfig.isOnSale(item, month)
		end

		if isEquipped then
			status.Text = "Equipped"
			status.TextColor3 = Sci.Green
			button.Text = "WEARING"
			button.BackgroundColor3 = Sci.Green
		elseif isOwned and isGun then
			-- Guns you own can be upgraded; every level costs more than the last.
			local gun = ShopConfig.getWeapon(item.Id)
			local level = if gun then gunLevels[gun.WeaponId] or 0 else 0
			local tier = UpgradeConfig.tier(level)
			if level >= UpgradeConfig.MAX_LEVEL then
				status.Text = `Max level · {if tier then tier.Name else ""}`
				status.TextColor3 = Sci.Purple
				button.Text = "MAXED"
				button.BackgroundColor3 = GREY
			else
				local cost = UpgradeConfig.cost(item.Price, level + 1)
				status.Text = if tier then `Lv {level} {tier.Name} · next {cost} coins` else `Upgrade: {cost} coins`
				status.TextColor3 = Sci.Cyan
				if confirmingId == item.Id then
					button.Text = "CONFIRM"
					button.BackgroundColor3 = Sci.Yellow
				else
					button.Text = "UPGRADE"
					button.BackgroundColor3 = if myCoins >= cost then Sci.Green else GREY
				end
			end
		elseif isOwned then
			status.Text = if item.Price <= 0 then "Free" else "Owned"
			status.TextColor3 = Sci.Cyan
			button.Text = "EQUIP"
			button.BackgroundColor3 = Sci.Cyan
		elseif item.Robux then
			local onSale = (item.ProductId or 0) > 0
			status.Text = `R$ {item.Robux} · {MONTH_NAMES[item.Month or month]} only`
			status.TextColor3 = Sci.Purple
			button.Text = if onSale then "BUY R$" else "SOON"
			button.BackgroundColor3 = if onSale then Sci.Purple else GREY
		else
			status.Text = tostring(item.Price) .. " coins"
			status.TextColor3 = Sci.Yellow
			if confirmingId == item.Id then
				button.Text = "TAP TO BUY"
				button.BackgroundColor3 = Sci.Yellow
			else
				button.Text = "BUY"
				button.BackgroundColor3 = if myCoins >= item.Price then Sci.Green else GREY
			end
		end
		button.TextColor3 = if button.BackgroundColor3 == GREY then Sci.Dim else Sci.Void
		button.AutoButtonColor = false
		button.Active = not busy
	end
	refreshRobuxCards()
end

local function selectTab(category: string)
	for _, tab in TABS do
		local active = tab.category == category
		tabButtons[tab.category].BackgroundColor3 = if active then Sci.Cyan else Sci.PanelLight
		tabButtons[tab.category].TextColor3 = if active then Sci.Void else Sci.Dim
		pages[tab.category].Visible = active
	end
end

-- Talking to the server ---------------------------------------------------------

local function sendRequest(remote: RemoteFunction, item: ShopItem)
	busy = true
	refreshCards()
	local ok, success, message = pcall(function()
		return remote:InvokeServer(item.Id)
	end)
	busy = false
	if ok and typeof(message) == "string" then
		showToast(message, success == true)
	else
		showToast("Something went wrong. Please try again!", false)
	end
	refreshCards()
end

-- Spending coins takes two taps, so a stray tap on a phone never spends
-- coins. Returns true on the first tap (the button then asks to confirm).
local function isFirstTap(item: ShopItem): boolean
	if confirmingId == item.Id then
		confirmingId = nil
		return false
	end
	confirmingId = item.Id
	confirmToken += 1
	local myToken = confirmToken
	refreshCards()
	task.delay(CONFIRM_SECONDS, function()
		if confirmToken == myToken then
			confirmingId = nil
			refreshCards()
		end
	end)
	return true
end

local function onCardPressed(item: ShopItem)
	if busy then
		return
	end
	local remotes = ShopRemotes.get()
	if equippedId(item.Category) == item.Id then
		showToast("You're already wearing " .. item.DisplayName .. "!", true)
		return
	end
	if item.Category == "Weapon" and (item.Price <= 0 or ownedIds()[item.Id]) then
		-- A gun you own: buy its next upgrade level.
		local gun = ShopConfig.getWeapon(item.Id)
		local level = if gun then UpgradeConfig.parse(player:GetAttribute("GunLevels"))[gun.WeaponId] or 0 else 0
		if level >= UpgradeConfig.MAX_LEVEL then
			showToast(item.DisplayName .. " is fully upgraded!", true)
			return
		end
		local missing = UpgradeConfig.cost(item.Price, level + 1) - coins()
		if missing > 0 then
			showToast(`You need {missing} more coins to upgrade {item.DisplayName}.`, false)
			return
		end
		if not isFirstTap(item) then
			task.spawn(sendRequest, remotes.UpgradeGun, item)
		end
		return
	end
	if item.Price <= 0 or ownedIds()[item.Id] then
		task.spawn(sendRequest, remotes.EquipItem, item)
		return
	end
	if item.Robux then
		-- Monthly themed items are bought with Robux through Roblox's own window;
		-- the server grants them when Roblox confirms the purchase (RobuxService).
		if (item.ProductId or 0) <= 0 then
			showToast(item.DisplayName .. " isn't on sale yet.", false)
		else
			MarketplaceService:PromptProductPurchase(player, item.ProductId :: number)
		end
		return
	end
	local missing = item.Price - coins()
	if missing > 0 then
		showToast("You need " .. tostring(missing) .. " more coins for " .. item.DisplayName .. ".", false)
		return
	end
	-- Buying takes two taps, so a stray tap on a phone never spends coins.
	if not isFirstTap(item) then
		task.spawn(sendRequest, remotes.BuyItem, item)
	end
end

-- Building the menu ---------------------------------------------------------------

-- Gun details ---------------------------------------------------------------
-- Clicking a gun's picture in the Guns tab opens this window: a big 3D view
-- of the gun, what it's good at, and its numbers as bars.

type DetailsUi = { backdrop: TextButton, preview: Frame, title: TextLabel, blurb: TextLabel, rows: { [string]: { fill: Frame, value: TextLabel } } }
local details: DetailsUi? = nil
local STAT_ROWS = { "Damage", "Fire rate", "Magazine", "Reload", "Range" }

local function buildDetails(): DetailsUi
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "GunDetails"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.ZIndex = 20
	backdrop.Modal = true -- frees the mouse in first person
	backdrop.Visible = false
	backdrop.Parent = shopGui
	backdrop.Activated:Connect(function()
		backdrop.Visible = false
	end)

	local panel = UIHelpers.frame("Panel", UDim2.fromOffset(560, 420), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	panel.BackgroundColor3 = Sci.Panel
	panel.BackgroundTransparency = 0
	panel.Active = true -- clicks on the window don't close it
	UIHelpers.corner(panel, UDim.new(0, 18))
	UIHelpers.stroke(panel, Sci.Cyan, 2)
	panel.Parent = backdrop

	local title = UIHelpers.label("Title", "", 24, SCI_FONT)
	title.Position = UDim2.fromOffset(20, 12)
	title.Size = UDim2.new(1, -90, 0, 40)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Sci.Green
	title.Parent = panel

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 12)
	close.Size = UDim2.fromOffset(42, 42)
	close.BackgroundColor3 = Sci.Red
	close.Font = SCI_FONT
	close.TextSize = 20
	close.TextColor3 = Sci.Text
	close.Text = "X"
	UIHelpers.corner(close, UDim.new(0, 10))
	close.Parent = panel
	close.Activated:Connect(function()
		backdrop.Visible = false
	end)

	local preview = Instance.new("Frame")
	preview.Name = "Preview"
	preview.Position = UDim2.fromOffset(20, 62)
	preview.Size = UDim2.new(1, -40, 0, 150)
	preview.BackgroundColor3 = Sci.Inset
	preview.BorderSizePixel = 0
	UIHelpers.corner(preview, UDim.new(0, 14))
	preview.Parent = panel

	local blurb = UIHelpers.label("Blurb", "", 18, BODY_FONT)
	blurb.Position = UDim2.fromOffset(20, 218)
	blurb.Size = UDim2.new(1, -40, 0, 28)
	blurb.TextColor3 = Sci.Cyan
	blurb.Parent = panel

	local rows: { [string]: { fill: Frame, value: TextLabel } } = {}
	for index, name in STAT_ROWS do
		local y = 252 + (index - 1) * 32
		local label = UIHelpers.label(name, string.upper(name), 13, SCI_FONT)
		label.Position = UDim2.fromOffset(24, y)
		label.Size = UDim2.fromOffset(120, 26)
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.TextColor3 = Sci.Dim
		label.Parent = panel
		local track = UIHelpers.frame("Track", UDim2.fromOffset(250, 14), UDim2.fromOffset(150, y + 6), nil)
		track.BackgroundColor3 = Sci.Inset
		track.BackgroundTransparency = 0
		UIHelpers.corner(track, UDim.new(1, 0))
		track.Parent = panel
		local fill = UIHelpers.frame("Fill", UDim2.fromScale(0, 1), UDim2.new(), nil)
		fill.BackgroundColor3 = Sci.Green
		fill.BackgroundTransparency = 0
		UIHelpers.corner(fill, UDim.new(1, 0))
		fill.Parent = track
		local value = UIHelpers.label("Value", "", 16, BODY_FONT)
		value.Position = UDim2.fromOffset(410, y)
		value.Size = UDim2.fromOffset(130, 26)
		value.TextXAlignment = Enum.TextXAlignment.Left
		value.TextColor3 = Sci.Text
		value.Parent = panel
		rows[name] = { fill = fill, value = value }
	end
	return { backdrop = backdrop, preview = preview, title = title, blurb = blurb, rows = rows }
end

local function showGunDetails(displayName: string, blurb: string, stats: WeaponConfig.WeaponStats)
	local ui = details or buildDetails()
	details = ui
	ui.title.Text = displayName
	ui.blurb.Text = blurb
	for _, child in ui.preview:GetChildren() do
		if child:IsA("ViewportFrame") then
			child:Destroy()
		end
	end
	ItemPreview.weapon(ui.preview, stats)

	local damage = stats.Damage * stats.Pellets
	local values: { [string]: { fraction: number, text: string } } = {
		Damage = { fraction = damage / 100, text = if stats.Pellets > 1 then `{stats.Damage} x{stats.Pellets}` else tostring(stats.Damage) },
		["Fire rate"] = { fraction = stats.FireRate / 12, text = `{stats.FireRate} / s` },
		Magazine = { fraction = stats.MagazineSize / 40, text = tostring(stats.MagazineSize) },
		Reload = { fraction = 1 - math.clamp((stats.ReloadTime - 0.8) / 2.5, 0, 0.9), text = `{stats.ReloadTime} s` },
		Range = { fraction = stats.MaxRange / 600, text = `{stats.MaxRange} studs` },
	}
	for name, row in ui.rows do
		local info = values[name]
		row.fill.Size = UDim2.fromScale(math.clamp(info.fraction, 0.05, 1), 1)
		row.value.Text = info.text
	end
	ui.backdrop.Visible = true
end

-- The gun you're holding (skin pictures show the skin on it).
local function equippedWeapon(): string?
	local value = player:GetAttribute("EquippedWeapon")
	return if typeof(value) == "string" then value else nil
end

-- Makes a card's picture clickable, with a small "i" badge in its corner.
local function addInfoButton(previewBox: Frame, onClick: () -> ())
	local detailsButton = Instance.new("TextButton")
	detailsButton.Name = "Details"
	detailsButton.Size = UDim2.fromScale(1, 1)
	detailsButton.BackgroundTransparency = 1
	detailsButton.Text = ""
	detailsButton.ZIndex = 4
	detailsButton.Parent = previewBox
	local badge = UIHelpers.label("InfoBadge", "i", 16, Theme.Fonts.Title)
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, -6, 0, 6)
	badge.Size = UDim2.fromOffset(24, 24)
	badge.BackgroundColor3 = Sci.Cyan
	badge.BackgroundTransparency = 0
	badge.TextColor3 = Sci.Void
	badge.ZIndex = 5
	UIHelpers.corner(badge, UDim.new(1, 0))
	badge.Parent = previewBox
	detailsButton.Activated:Connect(onClick)
end

-- Skin on every gun --------------------------------------------------------------
-- Clicking a skin's picture opens this window: the skin painted on every
-- gun, so you can see how it fits each gun's own shape before buying.

type SkinWindow = { backdrop: TextButton, title: TextLabel, grid: Frame }
local skinWindow: SkinWindow? = nil

local function buildSkinWindow(): SkinWindow
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "SkinOnEveryGun"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.4
	backdrop.AutoButtonColor = false
	backdrop.Text = ""
	backdrop.ZIndex = 20
	backdrop.Modal = true -- frees the mouse in first person
	backdrop.Visible = false
	backdrop.Parent = shopGui
	backdrop.Activated:Connect(function()
		backdrop.Visible = false
	end)

	local window = UIHelpers.frame("Panel", UDim2.fromOffset(760, 474), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
	window.BackgroundColor3 = Sci.Panel
	window.BackgroundTransparency = 0
	window.Active = true -- clicks on the window don't close it
	UIHelpers.corner(window, UDim.new(0, 18))
	UIHelpers.stroke(window, Sci.Cyan, 2)
	window.Parent = backdrop

	local title = UIHelpers.label("Title", "", 22, SCI_FONT)
	title.Position = UDim2.fromOffset(20, 12)
	title.Size = UDim2.new(1, -90, 0, 34)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Sci.Green
	title.Parent = window
	local subtitle = UIHelpers.label("Subtitle", "How this skin looks on every gun", 15, BODY_FONT)
	subtitle.Position = UDim2.fromOffset(20, 46)
	subtitle.Size = UDim2.new(1, -90, 0, 22)
	subtitle.TextXAlignment = Enum.TextXAlignment.Left
	subtitle.TextColor3 = Sci.Dim
	subtitle.Parent = window

	local close = Instance.new("TextButton")
	close.Name = "Close"
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -14, 0, 12)
	close.Size = UDim2.fromOffset(42, 42)
	close.BackgroundColor3 = Sci.Red
	close.Font = SCI_FONT
	close.TextSize = 20
	close.TextColor3 = Sci.Text
	close.Text = "X"
	UIHelpers.corner(close, UDim.new(0, 10))
	close.Parent = window
	close.Activated:Connect(function()
		backdrop.Visible = false
	end)

	local grid = UIHelpers.frame("Guns", UDim2.new(1, -40, 1, -96), UDim2.fromOffset(20, 80), nil)
	grid.BackgroundTransparency = 1
	grid.Parent = window
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(172, 180)
	layout.CellPadding = UDim2.fromOffset(8, 10)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid
	return { backdrop = backdrop, title = title, grid = grid }
end

local function showSkinOnEveryGun(displayName: string, skin: ShopConfig.SkinItem)
	local ui = skinWindow or buildSkinWindow()
	skinWindow = ui
	ui.title.Text = string.upper(displayName)
	for _, child in ui.grid:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for index, weaponId in WeaponConfig.Order do
		local stats = WeaponConfig.get(weaponId)
		if stats then
			local tile = Instance.new("Frame")
			tile.Name = weaponId
			tile.LayoutOrder = index
			tile.BackgroundColor3 = Sci.Inset
			tile.BorderSizePixel = 0
			UIHelpers.corner(tile, UDim.new(0, 12))
			UIHelpers.stroke(tile, Sci.Edge, 1.5)
			tile.Parent = ui.grid
			local picture = Instance.new("Frame")
			picture.Name = "Picture"
			picture.Position = UDim2.fromOffset(4, 4)
			picture.Size = UDim2.new(1, -8, 1, -38)
			picture.BackgroundTransparency = 1
			picture.Parent = tile
			ItemPreview.skin(picture, skin, weaponId)
			local name = UIHelpers.label("GunName", stats.DisplayName, 14, BODY_FONT)
			name.AnchorPoint = Vector2.new(0, 1)
			name.Position = UDim2.new(0, 6, 1, -8)
			name.Size = UDim2.new(1, -12, 0, 22)
			name.TextColor3 = Sci.Text
			name.TextScaled = true
			local limit = Instance.new("UITextSizeConstraint")
			limit.MaxTextSize = 14
			limit.Parent = name
			name.Parent = tile
		end
	end
	ui.backdrop.Visible = true
end

-- Skin pictures follow the gun you're holding.
local function redrawSkinPreviews()
	for _, entry in skinPreviews do
		for _, child in entry.box:GetChildren() do
			if child:IsA("ViewportFrame") then
				child:Destroy()
			end
		end
		ItemPreview.skin(entry.box, entry.skin, equippedWeapon())
	end
end

local function buildCard(page: ScrollingFrame, item: ShopItem, order: number)
	local card = Instance.new("Frame")
	card.Name = item.Id
	card.LayoutOrder = order
	card.BackgroundColor3 = Sci.PanelLight
	card.BorderSizePixel = 0
	UIHelpers.corner(card, UDim.new(0, 14))
	UIHelpers.stroke(card, ShopConfig.rarityOf(item).Color, 2.5)
	card.Parent = page

	local previewBox = Instance.new("Frame")
	previewBox.Name = "PreviewBox"
	previewBox.Position = UDim2.fromOffset(10, 10)
	previewBox.Size = UDim2.new(1, -20, 0, 100)
	previewBox.BackgroundColor3 = Sci.Inset
	previewBox.BorderSizePixel = 0
	UIHelpers.corner(previewBox, UDim.new(0, 10))
	previewBox.Parent = card
	-- A soft glow in the rarity colour rising from the bottom of the picture.
	local glowFade = Instance.new("UIGradient")
	glowFade.Rotation = -90
	glowFade.Color = ColorSequence.new(Sci.Inset:Lerp(ShopConfig.rarityOf(item).Color, 0.35), Sci.Inset)
	glowFade.Parent = previewBox

	-- Rarity tag (COMMON / UNCOMMON / RARE / EPIC / LEGENDARY) in its colour.
	local rarity = ShopConfig.rarityOf(item)
	-- (The % is the Daily Squishy's chance of that rarity, so it only shows
	-- on items the Daily Squishy can give: not free or Robux items.)
	local rarityText = if item.Robux or item.Price <= 0 then string.upper(rarity.Name) else `{string.upper(rarity.Name)}  {rarity.Chance}%`
	local rarityTag = UIHelpers.label("Rarity", rarityText, 11, SCI_FONT)
	rarityTag.Size = UDim2.fromOffset(110, 18)
	rarityTag.Position = UDim2.fromOffset(16, 12)
	rarityTag.TextXAlignment = Enum.TextXAlignment.Left
	rarityTag.TextColor3 = rarity.Color
	rarityTag.ZIndex = 3
	UIHelpers.textStroke(rarityTag, 1.5)
	rarityTag.Parent = card

	if item.Category == "Color" then
		ItemPreview.color(previewBox, ShopConfig.getColor(item.Id))
	elseif item.Category == "Hat" then
		local blobColor = ShopConfig.getColor(equippedId("Color")).Color
		table.insert(hatColorSetters, ItemPreview.hat(previewBox, ShopConfig.getHat(item.Id), blobColor))
	elseif item.Category == "Topping" then
		-- Toppings: a frozen moment of the burst (Effects pictures).
		ItemPreview.topping(previewBox, ShopConfig.getTopping(item.Id))
	elseif item.Category == "Weapon" then
		-- Guns: each gun's own 3D design. Click the picture for its details.
		local gun = ShopConfig.getWeapon(item.Id)
		local stats = if gun then WeaponConfig.get(gun.WeaponId) else nil
		if gun and stats then
			ItemPreview.weapon(previewBox, stats)
			addInfoButton(previewBox, function()
				showGunDetails(item.DisplayName, gun.Blurb, stats)
			end)
		end
	else
		-- Skins: shown on the gun you're holding. Click the picture to see the
		-- skin on every gun (it fits each gun's own shape).
		local skin = ShopConfig.getSkin(item.Id)
		ItemPreview.skin(previewBox, skin, equippedWeapon())
		table.insert(skinPreviews, { box = previewBox, skin = skin })
		addInfoButton(previewBox, function()
			showSkinOnEveryGun(item.DisplayName, skin)
		end)
	end

	local name = UIHelpers.label("ItemName", item.DisplayName, 20, BODY_FONT)
	name.Position = UDim2.fromOffset(8, 113)
	name.Size = UDim2.new(1, -16, 0, 22)
	name.TextColor3 = Sci.Text
	name.TextScaled = true
	local sizeLimit = Instance.new("UITextSizeConstraint")
	sizeLimit.MaxTextSize = 20
	sizeLimit.Parent = name
	name.Parent = card

	local status = UIHelpers.label("Status", "", 15, BODY_FONT)
	status.Position = UDim2.fromOffset(8, 136)
	status.Size = UDim2.new(1, -16, 0, 17)
	-- Long lines ("R$ 79 · November only") shrink to fit inside the card.
	status.TextScaled = true
	local statusLimit = Instance.new("UITextSizeConstraint")
	statusLimit.MaxTextSize = 15
	statusLimit.Parent = status
	status.Parent = card

	local button = makeButton("Action", "BUY", UDim2.new(1, -20, 0, 36), Sci.Green)
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -9)
	button.TextSize = 16
	button.Parent = card
	button.Activated:Connect(function()
		onCardPressed(item)
	end)

	table.insert(cards, { item = item, status = status, button = button })
end

local function buildPage(parent: Instance, category: Category, items: { ShopItem }): ScrollingFrame
	local page = Instance.new("ScrollingFrame")
	page.Name = category .. "Page"
	page.Position = UDim2.fromOffset(20, 140)
	page.Size = UDim2.new(1, -40, 1, -196)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 10
	page.ScrollBarImageColor3 = Sci.Cyan
	page.ScrollingDirection = Enum.ScrollingDirection.Y
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.CanvasSize = UDim2.new()
	page.Visible = false
	page.Parent = parent

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 6)
	padding.Parent = page

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(150, 206)
	grid.CellPadding = UDim2.fromOffset(14, 14)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = page

	for index, item in items do
		buildCard(page, item, index)
	end
	return page
end

local function itemsIn(category: Category): { ShopItem }
	local ids: { string } = {}
	if category == "Color" then
		for _, entry in ShopConfig.Colors do
			table.insert(ids, entry.Id)
		end
	elseif category == "Hat" then
		for _, entry in ShopConfig.Hats do
			table.insert(ids, entry.Id)
		end
	elseif category == "Weapon" then
		for _, entry in ShopConfig.Weapons do
			table.insert(ids, entry.Id)
		end
	elseif category == "Topping" then
		for _, entry in ShopConfig.Toppings do
			table.insert(ids, entry.Id)
		end
	else
		for _, entry in ShopConfig.Skins do
			table.insert(ids, entry.Id)
		end
	end
	local list: { ShopItem } = {}
	for _, id in ids do
		local item = ShopConfig.getItem(id)
		if item then
			table.insert(list, item)
		end
	end
	-- Organised by rarity: Common first, Legendary last.
	return ShopConfig.sortByRarity(list)
end

-- The ROBUX tab ----------------------------------------------------------------
-- Coin packs and bundles, bought through Roblox's own purchase window. The
-- server (RobuxService) adds the coins and items once Roblox confirms.

-- A little pile of drawn coins (more coins for bigger packs).
local function drawCoins(parent: GuiObject, count: number)
	for i = 1, count do
		local column = (i - 1) % 3
		local row = (i - 1) // 3
		local coin = UIHelpers.frame("Coin", UDim2.fromOffset(34, 34), UDim2.new(0.5, (column - 1) * 24 + row * 10, 0.62, -row * 16), Vector2.new(0.5, 0.5))
		coin.BackgroundColor3 = Sci.Yellow
		coin.BackgroundTransparency = 0
		coin.ZIndex = 2 + row
		UIHelpers.corner(coin, UDim.new(1, 0))
		UIHelpers.stroke(coin, Color3.fromRGB(200, 140, 30), 2)
		local inner = UIHelpers.frame("Inner", UDim2.fromScale(0.56, 0.56), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
		inner.BackgroundColor3 = Color3.fromRGB(255, 236, 150)
		inner.BackgroundTransparency = 0
		inner.ZIndex = coin.ZIndex
		UIHelpers.corner(inner, UDim.new(1, 0))
		inner.Parent = coin
		coin.Parent = parent
	end
end

local function promptProduct(id: string, displayName: string)
	local productId = RobuxShopConfig.productId(id)
	if productId <= 0 then
		showToast(displayName .. " isn't on sale yet.", false)
		return
	end
	MarketplaceService:PromptProductPurchase(player, productId)
end

local function sectionTitle(parent: Instance, text: string, order: number)
	local title = UIHelpers.label("Section", text, 16, SCI_FONT)
	title.LayoutOrder = order
	title.Size = UDim2.new(1, -12, 0, 30)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Sci.Purple
	title.Parent = parent
end

local function robuxButton(parent: GuiObject, text: string): TextButton
	local button = makeButton("Buy", text, UDim2.new(1, -20, 0, 36), Sci.Purple)
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -9)
	button.TextSize = 15
	button.TextColor3 = Sci.Void
	button.Parent = parent
	return button
end

local function buildRobuxPage(parent: Instance): ScrollingFrame
	local page = Instance.new("ScrollingFrame")
	page.Name = "RobuxPage"
	page.Position = UDim2.fromOffset(20, 140)
	page.Size = UDim2.new(1, -40, 1, -196)
	page.BackgroundTransparency = 1
	page.BorderSizePixel = 0
	page.ScrollBarThickness = 10
	page.ScrollBarImageColor3 = Sci.Purple
	page.ScrollingDirection = Enum.ScrollingDirection.Y
	page.AutomaticCanvasSize = Enum.AutomaticSize.Y
	page.CanvasSize = UDim2.new()
	page.Visible = false
	page.Parent = parent
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 6)
	padding.Parent = page
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 10)
	layout.Parent = page

	-- Coin packs.
	sectionTitle(page, "COIN PACKS", 1)
	local packRow = UIHelpers.frame("CoinPacks", UDim2.new(1, -12, 0, 206), UDim2.new(), nil)
	packRow.BackgroundTransparency = 1
	packRow.LayoutOrder = 2
	packRow.Parent = page
	local packLayout = Instance.new("UIListLayout")
	packLayout.FillDirection = Enum.FillDirection.Horizontal
	packLayout.Padding = UDim.new(0, 14)
	packLayout.SortOrder = Enum.SortOrder.LayoutOrder
	packLayout.Parent = packRow
	for index, pack in RobuxShopConfig.CoinPacks do
		local card = UIHelpers.frame(pack.Id, UDim2.fromOffset(150, 206), UDim2.new(), nil)
		card.LayoutOrder = index
		card.BackgroundColor3 = Sci.PanelLight
		card.BackgroundTransparency = 0
		UIHelpers.corner(card, UDim.new(0, 14))
		UIHelpers.stroke(card, Sci.Yellow, 2)
		card.Parent = packRow
		local picture = UIHelpers.frame("Picture", UDim2.new(1, -20, 0, 96), UDim2.fromOffset(10, 10), nil)
		picture.BackgroundColor3 = Sci.Inset
		picture.BackgroundTransparency = 0
		UIHelpers.corner(picture, UDim.new(0, 10))
		picture.Parent = card
		drawCoins(picture, index + 2)
		if pack.Badge then
			local badge = UIHelpers.label("Badge", pack.Badge, 10, SCI_FONT)
			badge.Position = UDim2.fromOffset(6, 6)
			badge.Size = UDim2.fromOffset(104, 18)
			badge.BackgroundColor3 = Sci.Green
			badge.BackgroundTransparency = 0
			badge.TextColor3 = Sci.Void
			badge.ZIndex = 6
			UIHelpers.corner(badge, UDim.new(0, 6))
			badge.Parent = picture
		end
		local amount = UIHelpers.label("Amount", `{pack.Coins} COINS`, 15, SCI_FONT)
		amount.Position = UDim2.fromOffset(8, 112)
		amount.Size = UDim2.new(1, -16, 0, 22)
		amount.TextColor3 = Sci.Yellow
		amount.Parent = card
		local name = UIHelpers.label("PackName", pack.DisplayName, 14, BODY_FONT)
		name.Position = UDim2.fromOffset(8, 136)
		name.Size = UDim2.new(1, -16, 0, 18)
		name.TextColor3 = Sci.Dim
		name.Parent = card
		local button = robuxButton(card, if RobuxShopConfig.productId(pack.Id) > 0 then `R$ {pack.Robux}` else "SOON")
		if RobuxShopConfig.productId(pack.Id) <= 0 then
			button.BackgroundColor3 = GREY
			button.TextColor3 = Sci.Dim
		end
		button.Activated:Connect(function()
			promptProduct(pack.Id, pack.DisplayName)
		end)
	end

	-- Bundles (always this month's themed items).
	sectionTitle(page, "BUNDLES", 3)
	local bundleRow = UIHelpers.frame("Bundles", UDim2.new(1, -12, 0, 206), UDim2.new(), nil)
	bundleRow.BackgroundTransparency = 1
	bundleRow.LayoutOrder = 4
	bundleRow.Parent = page
	local bundleLayout = Instance.new("UIListLayout")
	bundleLayout.FillDirection = Enum.FillDirection.Horizontal
	bundleLayout.Padding = UDim.new(0, 14)
	bundleLayout.SortOrder = Enum.SortOrder.LayoutOrder
	bundleLayout.Parent = bundleRow

	local month = ShopConfig.currentMonth()
	local theme = RobuxShopConfig.themeFor(month)
	local bundleStatus: { { bundle: RobuxShopConfig.Bundle, status: TextLabel } } = {}
	for index, bundle in RobuxShopConfig.Bundles do
		local itemIds, coins, worth = RobuxShopConfig.bundleContents(bundle, month)
		local card = UIHelpers.frame(bundle.Id, UDim2.fromOffset(400, 206), UDim2.new(), nil)
		card.LayoutOrder = index
		card.BackgroundColor3 = Sci.PanelLight
		card.BackgroundTransparency = 0
		UIHelpers.corner(card, UDim.new(0, 14))
		UIHelpers.stroke(card, ShopConfig.Rarities[#ShopConfig.Rarities].Color, 2.5)
		card.Parent = bundleRow

		-- Little pictures of what's inside.
		local strip = UIHelpers.frame("Contents", UDim2.new(1, -20, 0, 92), UDim2.fromOffset(10, 10), nil)
		strip.BackgroundColor3 = Sci.Inset
		strip.BackgroundTransparency = 0
		UIHelpers.corner(strip, UDim.new(0, 10))
		strip.Parent = card
		local stripLayout = Instance.new("UIListLayout")
		stripLayout.FillDirection = Enum.FillDirection.Horizontal
		stripLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
		stripLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		stripLayout.Padding = UDim.new(0, 6)
		stripLayout.Parent = strip
		local blobColor = ShopConfig.getColor(equippedId("Color")).Color
		for order, itemId in itemIds do
			local box = UIHelpers.frame("Item", UDim2.fromOffset(84, 84), UDim2.new(), nil)
			box.LayoutOrder = order
			box.BackgroundTransparency = 1
			box.Parent = strip
			local item = ShopConfig.getItem(itemId)
			if item and item.Category == "Color" then
				ItemPreview.color(box, ShopConfig.getColor(itemId))
			elseif item and item.Category == "Hat" then
				ItemPreview.hat(box, ShopConfig.getHat(itemId), blobColor)
			elseif item and item.Category == "Skin" then
				ItemPreview.skin(box, ShopConfig.getSkin(itemId), equippedWeapon())
			elseif item and item.Category == "Topping" then
				ItemPreview.topping(box, ShopConfig.getTopping(itemId))
			end
		end
		if coins > 0 then
			local coinBox = UIHelpers.frame("Coins", UDim2.fromOffset(110, 84), UDim2.new(), nil)
			coinBox.LayoutOrder = 0
			coinBox.BackgroundTransparency = 1
			coinBox.Parent = strip
			drawCoins(coinBox, 5)
			local coinText = UIHelpers.label("Amount", `{coins} COINS`, 11, SCI_FONT)
			coinText.Position = UDim2.fromOffset(0, 0)
			coinText.Size = UDim2.new(1, 0, 0, 16)
			coinText.TextColor3 = Sci.Yellow
			coinText.ZIndex = 8
			coinText.Parent = coinBox
		end

		local saving = if worth > 0 then math.floor((1 - bundle.Robux / worth) * 100 + 0.5) else 0
		local title = UIHelpers.label("BundleName", string.upper(bundle.DisplayName), 15, SCI_FONT)
		title.Position = UDim2.fromOffset(12, 108)
		title.Size = UDim2.new(0.62, 0, 0, 22)
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextColor3 = Sci.Text
		title.Parent = card
		local save = UIHelpers.label("Save", `SAVE {saving}%`, 12, SCI_FONT)
		save.AnchorPoint = Vector2.new(1, 0)
		save.Position = UDim2.new(1, -12, 0, 108)
		save.Size = UDim2.fromOffset(110, 22)
		save.BackgroundColor3 = Sci.Green
		save.BackgroundTransparency = 0
		save.TextColor3 = Sci.Void
		UIHelpers.corner(save, UDim.new(0, 6))
		save.Parent = card
		local status = UIHelpers.label("Status", "", 14, BODY_FONT)
		status.Position = UDim2.fromOffset(12, 134)
		status.Size = UDim2.new(1, -24, 0, 18)
		status.TextXAlignment = Enum.TextXAlignment.Left
		status.RichText = true
		status.TextColor3 = Sci.Dim
		status.Text = if theme then `{theme.Name} · was <s>R$ {worth}</s>` else "Back next month!"
		status.Parent = card
		table.insert(bundleStatus, { bundle = bundle, status = status })

		local onSale = RobuxShopConfig.productId(bundle.Id) > 0 and theme ~= nil
		local button = robuxButton(card, if onSale then `R$ {bundle.Robux}` else "SOON")
		if not onSale then
			button.BackgroundColor3 = GREY
			button.TextColor3 = Sci.Dim
		end
		button.Activated:Connect(function()
			promptProduct(bundle.Id, bundle.DisplayName)
		end)
	end

	-- Shows how many of a bundle's items you already own.
	refreshRobuxCards = function()
		local owned = ownedIds()
		for _, entry in bundleStatus do
			local itemIds, _, worth = RobuxShopConfig.bundleContents(entry.bundle, month)
			local have = 0
			for _, itemId in itemIds do
				if owned[itemId] then
					have += 1
				end
			end
			local text = if theme then `{theme.Name} · was <s>R$ {worth}</s>` else "Back next month!"
			if have > 0 then
				text ..= `  ·  you own {have} of {#itemIds}`
			end
			entry.status.Text = text
		end
	end
	return page
end

local function buildCoinPill(parent: Instance)
	local pill = UIHelpers.frame("Coins", UDim2.fromOffset(190, 50), UDim2.new(1, -86, 0, 14), Vector2.new(1, 0))
	pill.BackgroundColor3 = Sci.Inset
	pill.BackgroundTransparency = 0
	UIHelpers.corner(pill, UDim.new(1, 0))
	UIHelpers.stroke(pill, Sci.Yellow, 2)
	pill.Parent = parent

	local coin = Instance.new("Frame")
	coin.Name = "CoinIcon"
	coin.AnchorPoint = Vector2.new(0, 0.5)
	coin.Position = UDim2.new(0, 10, 0.5, 0)
	coin.Size = UDim2.fromOffset(32, 32)
	coin.BackgroundColor3 = Colors.Yolk
	UIHelpers.corner(coin, UDim.new(1, 0))
	UIHelpers.stroke(coin, Colors.YolkDark, 3)
	coin.Parent = pill

	local value = UIHelpers.label("Value", "0", 22, SCI_FONT)
	value.Position = UDim2.fromOffset(48, 0)
	value.Size = UDim2.new(1, -60, 1, 0)
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.TextColor3 = Sci.Yellow
	value.Parent = pill

	local function update()
		value.Text = tostring(coins())
	end
	player:GetAttributeChangedSignal(ATTR.Coins):Connect(update)
	update()
end

local function buildMenu()
	shopGui = UIHelpers.screenGui("Shop", 20, player:WaitForChild("PlayerGui"))
	ResponsiveScale.apply(shopGui)
	shopGui.Enabled = false

	-- A dim layer behind the panel. It is a button so clicks on it never
	-- reach the game (no accidental shots while shopping).
	overlay = Instance.new("TextButton")
	overlay.Name = "Dim"
	overlay.Text = ""
	overlay.AutoButtonColor = false
	-- Modal frees the mouse cursor (first person locks it) while the shop is open.
	overlay.Modal = true
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Sci.Void
	overlay.BackgroundTransparency = 0.35
	overlay.BorderSizePixel = 0
	overlay.Parent = shopGui

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 18)
	panel.Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y)
	panel.BackgroundColor3 = Sci.Panel
	panel.BorderSizePixel = 0
	panel.Active = true
	UIHelpers.corner(panel, UDim.new(0, 18))
	local panelGlow = UIHelpers.stroke(panel, Sci.Cyan, 2)
	panelGlow.Transparency = 0.25
	panel.Parent = shopGui
	panelScale = Instance.new("UIScale")
	panelScale.Parent = panel

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 78)
	header.BackgroundColor3 = Sci.PanelLight
	header.BorderSizePixel = 0
	UIHelpers.corner(header, UDim.new(0, 18))
	header.Parent = panel
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Sci.PanelLight, Sci.Panel)
	gradient.Parent = header
	-- A neon line under the header.
	local line = Instance.new("Frame")
	line.Name = "NeonLine"
	line.AnchorPoint = Vector2.new(0.5, 1)
	line.Position = UDim2.new(0.5, 0, 1, 0)
	line.Size = UDim2.new(1, -36, 0, 2)
	line.BackgroundColor3 = Sci.Cyan
	line.BorderSizePixel = 0
	line.Parent = header

	local title = UIHelpers.label("Title", "SHOP", 38, SCI_FONT)
	title.Position = UDim2.fromOffset(28, 4)
	title.Size = UDim2.new(0, 300, 0, 70)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = Sci.Green
	local titleGlow = Instance.new("UIStroke")
	titleGlow.Color = Sci.Green
	titleGlow.Thickness = 1.5
	titleGlow.Transparency = 0.6
	titleGlow.Parent = title
	title.Parent = header

	buildCoinPill(header)

	local close = makeButton("Close", "X", UDim2.fromOffset(54, 54), Sci.Red)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -16, 0, 12)
	close.TextSize = 24
	close.TextColor3 = Sci.Text
	-- Modal frees the mouse if the camera has locked it (first person).
	close.Modal = true
	close.Parent = header
	close.Activated:Connect(function()
		ShopController.close()
	end)

	-- Tabs
	local tabRow = Instance.new("Frame")
	tabRow.Name = "Tabs"
	tabRow.Position = UDim2.fromOffset(20, 88)
	tabRow.Size = UDim2.new(1, -40, 0, 46)
	tabRow.BackgroundTransparency = 1
	tabRow.Parent = panel
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 12)
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabRow

	for index, tab in TABS do
		local button = makeButton(tab.title .. "Tab", string.upper(tab.title), UDim2.new(1 / #TABS, -10, 1, 0), Sci.PanelLight)
		button.LayoutOrder = index
		button.TextColor3 = Sci.Dim
		button.TextSize = 15
		-- No text outline on the tabs, so the dark text stays crisp.
		for _, child in button:GetChildren() do
			if child:IsA("UIStroke") and child.ApplyStrokeMode == Enum.ApplyStrokeMode.Contextual then
				child:Destroy()
			end
		end
		button.Parent = tabRow
		button.Activated:Connect(function()
			selectTab(tab.category)
		end)
		tabButtons[tab.category] = button
		pages[tab.category] = if tab.category == "Robux"
			then buildRobuxPage(panel)
			else buildPage(panel, tab.category :: Category, itemsIn(tab.category :: Category))
	end

	toast = UIHelpers.label("Message", "", 20, BODY_FONT)
	toast.AnchorPoint = Vector2.new(0.5, 1)
	toast.Position = UDim2.new(0.5, 0, 1, -12)
	toast.Size = UDim2.new(1, -40, 0, 34)
	toast.TextTransparency = 1
	toast.Parent = panel

	selectTab("Color")
	refreshCards()
end

-- Public -----------------------------------------------------------------------

function ShopController.open()
	ShopController.start()
	if isOpen then
		return
	end
	isOpen = true
	confirmingId = nil
	refreshCards()
	shopGui.Enabled = true
	panelScale.Scale = 0.85
	UIHelpers.tween(panelScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	overlay.BackgroundTransparency = 1
	UIHelpers.tween(overlay, 0.25, { BackgroundTransparency = 0.45 })
end

-- Opens the shop on one tab: "Color", "Hat", "Skin", "Weapon" or "Topping".
function ShopController.openTab(category: string)
	ShopController.open()
	for _, tab in TABS do
		if tab.category == category then
			selectTab(tab.category)
		end
	end
end

function ShopController.close()
	if not started or not isOpen then
		return
	end
	isOpen = false
	confirmingId = nil
	shopGui.Enabled = false
end

function ShopController.toggle()
	if isOpen then
		ShopController.close()
	else
		ShopController.open()
	end
end

function ShopController.start()
	if started then
		return
	end
	started = true

	buildMenu()

	-- Redraw the cards whenever the server changes coins or items.
	for _, attribute in { ATTR.Coins, ATTR.OwnedItems, ATTR.EquippedColor, ATTR.EquippedHat, ATTR.EquippedSkin, ATTR.EquippedTopping, "GunLevels" } do
		player:GetAttributeChangedSignal(attribute):Connect(refreshCards)
	end
	-- Skin pictures show the skin on the gun you're holding.
	player:GetAttributeChangedSignal("EquippedWeapon"):Connect(redrawSkinPreviews)
	-- Hat previews wear your current blob color.
	player:GetAttributeChangedSignal(ATTR.EquippedColor):Connect(function()
		local color = ShopConfig.getColor(equippedId("Color")).Color
		for _, setColor in hatColorSetters do
			setColor(color)
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		-- gameProcessed is true while typing in chat, so B there does nothing.
		if gameProcessed then
			return
		end
		if input.KeyCode == OPEN_KEY then
			ShopController.toggle()
		end
	end)
end

return ShopController
