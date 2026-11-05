--!strict
--[[
	ShopController
	A simple shop window (press B, or tap the SHOP button) where you spend
	coins on jelly colors. Clicking a button only *asks* the server; the
	server decides whether the purchase goes through.
]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Types = require(ReplicatedStorage.Shared.Types)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local ShopCatalog = require(ReplicatedStorage.Shared.ShopCatalog)
local DataController = require(script.Parent.DataController)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local FONT = Enum.Font.FredokaOne
local WHITE = Color3.new(1, 1, 1)
local PANEL = Color3.fromRGB(35, 35, 55)
local BUY = Color3.fromRGB(90, 200, 120)
local EQUIP = Color3.fromRGB(90, 150, 255)
local EQUIPPED = Color3.fromRGB(110, 110, 130)

local ShopController = {}

local buyRemote = Remotes.func("BuyColor")
local equipRemote = Remotes.func("EquipColor")

local function create(className: string, props: { [string]: any }): any
	local instance: any = Instance.new(className)
	for key, value in props do
		if key ~= "Parent" then
			instance[key] = value
		end
	end
	instance.Parent = props.Parent
	return instance
end

local function corner(parent: Instance, radius: number)
	create("UICorner", { CornerRadius = UDim.new(0, radius), Parent = parent })
end

------------------------------------------------------------------------
-- Build the window
------------------------------------------------------------------------

local gui: ScreenGui = create("ScreenGui", { Name = "Shop", ResetOnSpawn = false, Parent = playerGui })

local openButton: TextButton = create("TextButton", {
	Position = UDim2.fromOffset(24, 124), -- just below the coin counter
	Size = UDim2.fromOffset(90, 34),
	Text = "SHOP",
	Font = FONT,
	TextSize = 20,
	TextColor3 = WHITE,
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.2,
	Parent = gui,
})
corner(openButton, 8)

local window: Frame = create("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(420, 460),
	BackgroundColor3 = PANEL,
	BackgroundTransparency = 0.05,
	Visible = false,
	Parent = gui,
})
corner(window, 14)
create("UISizeConstraint", { MaxSize = Vector2.new(420, 460), Parent = window })

create("TextLabel", {
	Position = UDim2.fromOffset(20, 12),
	Size = UDim2.new(1, -80, 0, 36),
	BackgroundTransparency = 1,
	Text = "Jelly Shop",
	Font = FONT,
	TextSize = 30,
	TextColor3 = WHITE,
	TextXAlignment = Enum.TextXAlignment.Left,
	Parent = window,
})

-- Modal = true frees the mouse from first-person lock while the shop is open.
local closeButton: TextButton = create("TextButton", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -12, 0, 12),
	Size = UDim2.fromOffset(36, 36),
	Text = "X",
	Font = FONT,
	TextSize = 22,
	TextColor3 = WHITE,
	BackgroundColor3 = Color3.fromRGB(230, 90, 110),
	Modal = true,
	Parent = window,
})
corner(closeButton, 8)

local statusText: TextLabel = create("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -10),
	Size = UDim2.new(1, -40, 0, 24),
	BackgroundTransparency = 1,
	Text = "Earn coins by splatting other jellies!",
	Font = FONT,
	TextSize = 18,
	TextColor3 = Color3.fromRGB(255, 220, 90),
	Parent = window,
})

local list: ScrollingFrame = create("ScrollingFrame", {
	Position = UDim2.fromOffset(16, 60),
	Size = UDim2.new(1, -32, 1, -104),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 6,
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	CanvasSize = UDim2.new(),
	Parent = window,
})
create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })

-- One row per color; we keep the action buttons so we can update their text.
local actionButtons: { [string]: TextButton } = {}
local busy = false

local function refresh(data: Types.PublicData?)
	for _, item in ShopCatalog.Colors do
		local button = actionButtons[item.Id]
		if not data then
			button.Text = "..."
		elseif data.EquippedColor == item.Id then
			button.Text = "Equipped"
			button.BackgroundColor3 = EQUIPPED
		elseif data.OwnedColors[item.Id] then
			button.Text = "Equip"
			button.BackgroundColor3 = EQUIP
		else
			button.Text = `Buy  {item.Price}`
			button.BackgroundColor3 = BUY
		end
	end
end

local function onActionClicked(item: Types.ColorItem)
	local data = DataController.get()
	if busy or not data or data.EquippedColor == item.Id then
		return
	end
	busy = true
	statusText.Text = "..."
	local remote = if data.OwnedColors[item.Id] then equipRemote else buyRemote
	local ok, success, message = pcall(function()
		return remote:InvokeServer(item.Id)
	end)
	if ok then
		statusText.Text = if typeof(message) == "string" then message else ""
		statusText.TextColor3 = if success then Color3.fromRGB(120, 230, 120) else Color3.fromRGB(255, 120, 130)
	else
		statusText.Text = "Couldn't reach the server, please try again."
	end
	busy = false
end

for index, item in ShopCatalog.Colors do
	local row: Frame = create("Frame", {
		Size = UDim2.new(1, -8, 0, 52),
		BackgroundColor3 = Color3.fromRGB(50, 50, 75),
		LayoutOrder = index,
		Parent = list,
	})
	corner(row, 10)

	local swatch: Frame = create("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 10, 0.5, 0),
		Size = UDim2.fromOffset(34, 34),
		BackgroundColor3 = item.Color,
		Parent = row,
	})
	corner(swatch, 8)

	create("TextLabel", {
		Position = UDim2.fromOffset(56, 0),
		Size = UDim2.new(1, -180, 1, 0),
		BackgroundTransparency = 1,
		Text = item.DisplayName,
		Font = FONT,
		TextSize = 22,
		TextColor3 = WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	local button: TextButton = create("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -10, 0.5, 0),
		Size = UDim2.fromOffset(110, 36),
		Text = "...",
		Font = FONT,
		TextSize = 18,
		TextColor3 = WHITE,
		BackgroundColor3 = BUY,
		Parent = row,
	})
	corner(button, 8)
	button.Activated:Connect(function()
		onActionClicked(item)
	end)
	actionButtons[item.Id] = button
end

------------------------------------------------------------------------

function ShopController.toggle()
	window.Visible = not window.Visible
	refresh(DataController.get())
end

function ShopController.isOpen(): boolean
	return window.Visible
end

function ShopController.start()
	DataController.onChanged(refresh)
	openButton.Activated:Connect(ShopController.toggle)
	closeButton.Activated:Connect(ShopController.toggle)
	ContextActionService:BindAction("ToggleShop", function(_, state: Enum.UserInputState)
		if state == Enum.UserInputState.Begin then
			ShopController.toggle()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.KeyCode.B)
	refresh(nil)
end

return ShopController
