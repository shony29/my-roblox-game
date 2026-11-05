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
local ATTR = GameContract.PlayerAttributes

local OPEN_KEY = Enum.KeyCode.B
local CONFIRM_SECONDS = 3 -- how long "Tap again to buy" waits for the second tap
local PANEL_SIZE = Vector2.new(880, 540)
local GREY = Color3.fromRGB(175, 178, 190)

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
	button.Font = Theme.Fonts.Title
	button.TextSize = 22
	button.TextColor3 = Colors.White
	button.BackgroundColor3 = color
	button.AutoButtonColor = false
	button.Size = size
	UIHelpers.corner(button, UDim.new(0, 14))
	UIHelpers.stroke(button, Colors.Ink, 3)
	UIHelpers.textStroke(button, 2)

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
	toast.TextColor3 = if good then Colors.Mint else Colors.Coral
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
			status.TextColor3 = Colors.Mint
			button.Text = "WEARING"
			button.BackgroundColor3 = Colors.Mint
		elseif isOwned then
			status.Text = if isGun then "In your loadout" elseif item.Price <= 0 then "Free" else "Owned"
			status.TextColor3 = Colors.SkyDeep
			button.Text = if isGun then "OWNED" else "EQUIP"
			button.BackgroundColor3 = if isGun then Colors.Mint else Colors.SkyDeep
		elseif item.Robux then
			local onSale = (item.ProductId or 0) > 0
			status.Text = `R$ {item.Robux} · {MONTH_NAMES[item.Month or month]} only`
			status.TextColor3 = Colors.SkyDeep
			button.Text = if onSale then "BUY R$" else "SOON"
			button.BackgroundColor3 = if onSale then Colors.Sky else GREY
		else
			status.Text = tostring(item.Price) .. " coins"
			status.TextColor3 = Colors.YolkDark
			if confirmingId == item.Id then
				button.Text = "TAP TO BUY"
				button.BackgroundColor3 = Colors.Coral
			else
				button.Text = "BUY"
				button.BackgroundColor3 = if myCoins >= item.Price then Colors.Yolk else GREY
			end
		end
		button.AutoButtonColor = false
		button.Active = not busy
	end
end

local function selectTab(category: Category)
	for _, tab in TABS do
		local active = tab.category == category
		tabButtons[tab.category].BackgroundColor3 = if active then Colors.Yolk else Colors.White
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

local function buildCard(page: ScrollingFrame, item: ShopItem, order: number)
	local card = Instance.new("Frame")
	card.Name = item.Id
	card.LayoutOrder = order
	card.BackgroundColor3 = Colors.White
	card.BorderSizePixel = 0
	UIHelpers.corner(card, UDim.new(0, 18))
	UIHelpers.stroke(card, Colors.Ink, 3)
	card.Parent = page

	local previewBox = Instance.new("Frame")
	previewBox.Name = "PreviewBox"
	previewBox.Position = UDim2.fromOffset(10, 10)
	previewBox.Size = UDim2.new(1, -20, 0, 100)
	previewBox.BackgroundColor3 = Colors.Sky:Lerp(Colors.White, 0.7)
	previewBox.BorderSizePixel = 0
	UIHelpers.corner(previewBox, UDim.new(0, 14))
	previewBox.Parent = card

	-- Rarity tag (COMMON / UNCOMMON / RARE / EPIC / LEGENDARY) in its colour.
	local rarity = ShopConfig.rarityOf(item)
	local rarityTag = UIHelpers.label("Rarity", string.upper(rarity.Name), 13, Theme.Fonts.Title)
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
		-- Toppings: the charms, or a sprinkle of the topping's colours.
		local topping = ShopConfig.getTopping(item.Id)
		if topping.Charms then
			local charms = UIHelpers.label("Charms", table.concat(topping.Charms, " "), 26)
			charms.TextWrapped = true
			charms.Parent = previewBox
		else
			local random = Random.new(#item.Id)
			for i = 1, 14 do
				local color = topping.Colors[(i % #topping.Colors) + 1]
				local size = if topping.Style == "Sprinkles" then UDim2.fromOffset(5, 16) elseif topping.Style == "Glitter" then UDim2.fromOffset(7, 7) else UDim2.fromOffset(14, 14)
				local bit = UIHelpers.frame("Bit", size, UDim2.fromScale(random:NextNumber(0.1, 0.9), random:NextNumber(0.15, 0.85)), Vector2.new(0.5, 0.5))
				bit.BackgroundColor3 = color
				bit.BackgroundTransparency = 0
				bit.Rotation = random:NextNumber(0, 180)
				if topping.Style ~= "Glitter" then
					UIHelpers.corner(bit, UDim.new(1, 0))
				end
				bit.Parent = previewBox
			end
		end
	elseif item.Category == "Weapon" then
		-- Guns: what it's good at and its key numbers.
		local gun = ShopConfig.getWeapon(item.Id)
		local stats = if gun then WeaponConfig.get(gun.WeaponId) else nil
		if gun and stats then
			local damage = if stats.Pellets > 1 then `{stats.Damage} x{stats.Pellets}` else tostring(stats.Damage)
			local info = UIHelpers.label("GunInfo", `{gun.Blurb}\nDamage {damage} · {stats.FireRate}/s\nMagazine {stats.MagazineSize}`, 16, Theme.Fonts.Title)
			info.TextColor3 = Colors.Ink
			info.Parent = previewBox
		end
	else
		ItemPreview.skin(previewBox, ShopConfig.getSkin(item.Id))
	end

	local name = UIHelpers.label("ItemName", item.DisplayName, 20, Theme.Fonts.Title)
	name.Position = UDim2.fromOffset(6, 114)
	name.Size = UDim2.new(1, -12, 0, 24)
	name.TextColor3 = Colors.Ink
	name.TextScaled = true
	local sizeLimit = Instance.new("UITextSizeConstraint")
	sizeLimit.MaxTextSize = 20
	sizeLimit.Parent = name
	name.Parent = card

	local status = UIHelpers.label("Status", "", 17)
	status.Position = UDim2.fromOffset(6, 138)
	status.Size = UDim2.new(1, -12, 0, 20)
	status.Parent = card

	local button = makeButton("Action", "BUY", UDim2.new(1, -20, 0, 40), Colors.Yolk)
	button.AnchorPoint = Vector2.new(0.5, 1)
	button.Position = UDim2.new(0.5, 0, 1, -10)
	button.TextSize = 20
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
	page.ScrollBarImageColor3 = Colors.Ink
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
	pill.BackgroundColor3 = Colors.White
	pill.BackgroundTransparency = 0
	UIHelpers.corner(pill, UDim.new(1, 0))
	UIHelpers.stroke(pill, Colors.Ink, 3)
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

	local value = UIHelpers.label("Value", "0", 28, Theme.Fonts.Title)
	value.Position = UDim2.fromOffset(48, 0)
	value.Size = UDim2.new(1, -60, 1, 0)
	value.TextXAlignment = Enum.TextXAlignment.Left
	value.TextColor3 = Colors.YolkDark
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
	overlay.BackgroundColor3 = Colors.Ink
	overlay.BackgroundTransparency = 0.45
	overlay.BorderSizePixel = 0
	overlay.Parent = shopGui

	panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.new(0.5, 0, 0.5, 18)
	panel.Size = UDim2.fromOffset(PANEL_SIZE.X, PANEL_SIZE.Y)
	panel.BackgroundColor3 = Colors.Shell
	panel.BorderSizePixel = 0
	panel.Active = true
	UIHelpers.corner(panel, UDim.new(0, 26))
	UIHelpers.stroke(panel, Colors.Ink, 4)
	panel.Parent = shopGui
	panelScale = Instance.new("UIScale")
	panelScale.Parent = panel

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 78)
	header.BackgroundColor3 = Colors.Sky
	header.BorderSizePixel = 0
	UIHelpers.corner(header, UDim.new(0, 26))
	header.Parent = panel
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(Colors.Sky, Colors.SkyDeep)
	gradient.Parent = header

	local title = UIHelpers.label("Title", "SHOP", 48, Theme.Fonts.Title)
	title.Position = UDim2.fromOffset(28, 4)
	title.Size = UDim2.new(0, 300, 0, 70)
	title.TextXAlignment = Enum.TextXAlignment.Left
	UIHelpers.textStroke(title, 3)
	title.Parent = header

	buildCoinPill(header)

	local close = makeButton("Close", "X", UDim2.fromOffset(54, 54), Colors.Coral)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -16, 0, 12)
	close.TextSize = 30
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
		local button = makeButton(tab.title .. "Tab", tab.title, UDim2.fromOffset(170, 46), Colors.White)
		button.LayoutOrder = index
		button.TextColor3 = Colors.Ink
		button.TextSize = 24
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

	toast = UIHelpers.label("Message", "", 22, Theme.Fonts.Title)
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
		makeButton("ShopButton", if touchOnly then "SHOP" else "SHOP (B)", UDim2.fromOffset(150, 44), Colors.Yolk)
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
	for _, attribute in { ATTR.Coins, ATTR.OwnedItems, ATTR.EquippedColor, ATTR.EquippedHat, ATTR.EquippedSkin } do
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
