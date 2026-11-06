--!strict
--[[
	ShopController
	==============
	The shop menu on each player's screen.

	  * Open it with the SHOP button on the main menu, the SHOP button in
	    game (top left, handy on phones), or the B key.
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

local TABS: { { category: Category, title: string } } = {
	{ category = "Color", title = "Colors" },
	{ category = "Hat", title = "Squishies" },
	{ category = "Skin", title = "Skins" },
	{ category = "Weapon", title = "Guns" },
	{ category = "Topping", title = "Toppings" },
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
local hudButton: TextButton
local cards: { Card } = {}
local tabButtons: { [Category]: TextButton } = {}
local pages: { [Category]: ScrollingFrame } = {}
local hatColorSetters: { (Color3) -> () } = {}

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
		elseif isOwned then
			local gun = if isGun then ShopConfig.getWeapon(item.Id) else nil
			local tier = if gun then UpgradeConfig.tier(gunLevels[gun.WeaponId] or 0) else nil
			status.Text = if tier then `Loadout · Lv {tier.Level} {tier.Name}`
				elseif isGun then "In your loadout"
				elseif item.Price <= 0 then "Free"
				else "Owned"
			status.TextColor3 = Sci.Cyan
			button.Text = if isGun then "OWNED" else "EQUIP"
			button.BackgroundColor3 = if isGun then Sci.Green else Sci.Cyan
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
end

local function selectTab(category: Category)
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
		showToast(item.DisplayName .. " is already in your loadout!", true)
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
	if confirmingId ~= item.Id then
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
		return
	end
	confirmingId = nil
	task.spawn(sendRequest, remotes.BuyItem, item)
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
	local rarityText = if item.Robux then string.upper(rarity.Name) else `{string.upper(rarity.Name)}  {rarity.Chance}%`
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
			detailsButton.Activated:Connect(function()
				showGunDetails(item.DisplayName, gun.Blurb, stats)
			end)
		end
	else
		ItemPreview.skin(previewBox, ShopConfig.getSkin(item.Id))
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
	return list
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
	-- How to get smoother 3D pictures (only shows while graphics quality is low).
	UIHelpers.qualityTip(header, UDim2.new(0, 210, 0.5, 0), Vector2.new(0, 0.5), 380)

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
		pages[tab.category] = buildPage(panel, tab.category, itemsIn(tab.category))
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

-- A small SHOP button in the game HUD (phones have no B key).
local function buildHudButton()
	local hudGui = UIHelpers.screenGui("ShopButton", 2, player:WaitForChild("PlayerGui"))
	ResponsiveScale.apply(hudGui)

	local touchOnly = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	hudButton =
		makeButton("ShopButton", if touchOnly then "SHOP" else "SHOP (B)", UDim2.fromOffset(150, 44), Sci.Green)
	hudButton.Position = UDim2.fromOffset(Theme.Margin, 68)
	hudButton.Parent = hudGui
	hudButton.Activated:Connect(function()
		ShopController.open()
	end)

	local function update()
		hudButton.Visible = player:GetAttribute(ATTR.PressedPlay) == true and not isOpen
	end
	player:GetAttributeChangedSignal(ATTR.PressedPlay):Connect(update)
	update()
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
	hudButton.Visible = false
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
	hudButton.Visible = player:GetAttribute(ATTR.PressedPlay) == true
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
	buildHudButton()

	-- Redraw the cards whenever the server changes coins or items.
	for _, attribute in { ATTR.Coins, ATTR.OwnedItems, ATTR.EquippedColor, ATTR.EquippedHat, ATTR.EquippedSkin, "GunLevels" } do
		player:GetAttributeChangedSignal(attribute):Connect(refreshCards)
	end
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
