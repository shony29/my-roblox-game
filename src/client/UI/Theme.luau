--!strict
--[[
	Theme
	=====
	Colors, fonts and sizes for every screen. Change things here to
	restyle the whole UI at once.
]]

local Theme = {}

Theme.GameTitle = "SLIME SHOWDOWN"

Theme.Colors = {
	Yolk = Color3.fromRGB(255, 205, 60),
	YolkDark = Color3.fromRGB(230, 160, 20),
	Sky = Color3.fromRGB(110, 200, 255),
	SkyDeep = Color3.fromRGB(60, 140, 230),
	Mint = Color3.fromRGB(90, 220, 140),
	Coral = Color3.fromRGB(255, 100, 100),
	Shell = Color3.fromRGB(255, 250, 240),
	Ink = Color3.fromRGB(35, 40, 60),
	Panel = Color3.fromRGB(30, 35, 55),
	White = Color3.fromRGB(255, 255, 255),
}

Theme.Fonts = {
	Title = Enum.Font.FredokaOne,
	Body = Enum.Font.GothamBold,
}

-- Every screen is designed at this size. ResponsiveScale shrinks or grows
-- it to fit the real screen, so it looks the same on PC and phones.
-- The sci-fi look of the slime bunker (main menu and shop): dark metal
-- panels, glowing neon edges and a techy title font.
Theme.SciFi = {
	Void = Color3.fromRGB(8, 10, 18), -- darkest (text on neon buttons)
	Panel = Color3.fromRGB(16, 20, 32), -- big panels
	PanelLight = Color3.fromRGB(26, 32, 50), -- cards and tabs
	Inset = Color3.fromRGB(11, 14, 24), -- picture wells
	Edge = Color3.fromRGB(60, 72, 104), -- quiet borders
	Grey = Color3.fromRGB(58, 64, 82), -- disabled buttons
	Green = Color3.fromRGB(120, 255, 90), -- slime neon: the main action
	Cyan = Color3.fromRGB(90, 220, 255),
	Purple = Color3.fromRGB(190, 90, 255),
	Yellow = Color3.fromRGB(255, 214, 90),
	Red = Color3.fromRGB(255, 80, 100),
	Text = Color3.fromRGB(228, 236, 255),
	Dim = Color3.fromRGB(140, 154, 190),
}
Theme.SciFiFonts = {
	Title = Enum.Font.Michroma, -- wide, futuristic: titles, tabs, buttons
	Body = Enum.Font.GothamBold, -- clean and easy to read: names, prices
}

Theme.DesignResolution = Vector2.new(1280, 720)

Theme.PanelTransparency = 0.25
Theme.CornerRadius = UDim.new(0, 12)
Theme.Margin = 20

return Theme
