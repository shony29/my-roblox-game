--!strict
--[[
	Theme
	=====
	Colors, fonts and sizes for every screen. Change things here to
	restyle the whole UI at once.
]]

local Theme = {}

Theme.GameTitle = "JELLY BLITZ"

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
Theme.DesignResolution = Vector2.new(1280, 720)

Theme.PanelTransparency = 0.25
Theme.CornerRadius = UDim.new(0, 12)
Theme.Margin = 20

return Theme
