--!strict
--[[
	Icons
	=====
	Small sci-fi icons drawn from plain shapes (no emoji and no images), so
	they look the same on every device and never turn into empty squares:
	  shop      a shopping bag
	  tasks     a clipboard with a checklist
	  weapons   a crosshair
	  gear      settings
	  calendar  the tasks button at the top right
	  bell      notifications
	Each one fills a square `holder` frame and grows or shrinks with it.
	`background` is the colour behind the icon (used for the holes).
]]

local Icons = {}

-- One flat shape of an icon. Positions and sizes are fractions of the holder.
local function piece(holder: GuiObject, name: string, color: Color3, x: number, y: number, w: number, h: number, round: number?, rotation: number?): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(x, y)
	frame.Size = UDim2.fromScale(w, h)
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.Rotation = rotation or 0
	frame.ZIndex = holder.ZIndex + 1
	if round then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(round, 0)
		corner.Parent = frame
	end
	frame.Parent = holder
	return frame
end

-- An outline only: a ring, or a rounded box drawn with a line.
local function outline(holder: GuiObject, name: string, color: Color3, x: number, y: number, w: number, h: number, round: number, thickness: number): Frame
	local frame = piece(holder, name, color, x, y, w, h, round)
	frame.BackgroundTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = frame
	return frame
end

local function raise(frame: Frame, by: number): Frame
	frame.ZIndex += by
	return frame
end

function Icons.shop(holder: GuiObject, color: Color3, _background: Color3)
	outline(holder, "Handle", color, 0.5, 0.34, 0.4, 0.46, 1, 2.5) -- its lower half hides behind the bag
	raise(piece(holder, "Bag", color, 0.5, 0.65, 0.76, 0.56, 0.22), 2)
end

function Icons.tasks(holder: GuiObject, color: Color3, _background: Color3)
	outline(holder, "Board", color, 0.5, 0.56, 0.68, 0.8, 0.18, 2.5)
	piece(holder, "Clip", color, 0.5, 0.15, 0.38, 0.14, 0.4)
	for _, y in { 0.42, 0.58, 0.74 } do
		piece(holder, "Tick", color, 0.33, y, 0.09, 0.09, 1)
		piece(holder, "Line", color, 0.58, y, 0.3, 0.07, 1)
	end
end

function Icons.weapons(holder: GuiObject, color: Color3, _background: Color3)
	outline(holder, "Ring", color, 0.5, 0.5, 0.6, 0.6, 1, 2.5)
	piece(holder, "Top", color, 0.5, 0.11, 0.09, 0.22, 1)
	piece(holder, "Bottom", color, 0.5, 0.89, 0.09, 0.22, 1)
	piece(holder, "Left", color, 0.11, 0.5, 0.22, 0.09, 1)
	piece(holder, "Right", color, 0.89, 0.5, 0.22, 0.09, 1)
	piece(holder, "Dot", color, 0.5, 0.5, 0.14, 0.14, 1)
end

function Icons.gear(holder: GuiObject, color: Color3, background: Color3)
	for i = 0, 7 do
		local angle = i * 45
		local x = 0.5 + math.cos(math.rad(angle)) * 0.36
		local y = 0.5 + math.sin(math.rad(angle)) * 0.36
		piece(holder, "Tooth", color, x, y, 0.2, 0.2, 0.18, angle)
	end
	piece(holder, "Wheel", color, 0.5, 0.5, 0.66, 0.66, 1)
	raise(piece(holder, "Hole", background, 0.5, 0.5, 0.26, 0.26, 1), 1)
end

function Icons.calendar(holder: GuiObject, color: Color3, background: Color3)
	piece(holder, "Body", color, 0.5, 0.56, 0.82, 0.72, 0.16)
	raise(piece(holder, "Page", background, 0.5, 0.65, 0.66, 0.42, 0.12), 1)
	for row = 0, 1 do
		for column = 0, 2 do
			raise(piece(holder, "Day", color, 0.31 + column * 0.19, 0.56 + row * 0.18, 0.11, 0.11, 0.3), 2)
		end
	end
	for _, x in { 0.32, 0.68 } do
		raise(piece(holder, "Ring", color, x, 0.17, 0.1, 0.22, 1), 1)
	end
end

function Icons.bell(holder: GuiObject, color: Color3, _background: Color3)
	piece(holder, "Knob", color, 0.5, 0.13, 0.14, 0.14, 1)
	piece(holder, "Dome", color, 0.5, 0.45, 0.56, 0.6, 0.5)
	piece(holder, "Skirt", color, 0.5, 0.66, 0.7, 0.2, 0.25)
	piece(holder, "Rim", color, 0.5, 0.76, 0.86, 0.1, 1)
	piece(holder, "Clapper", color, 0.5, 0.88, 0.2, 0.16, 1)
end

-- A square, see-through holder for an icon, placed inside `parent`.
function Icons.holder(parent: GuiObject, size: UDim2, position: UDim2, anchor: Vector2): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Icon"
	holder.AnchorPoint = anchor
	holder.Position = position
	holder.Size = size
	holder.BackgroundTransparency = 1
	holder.ZIndex = parent.ZIndex + 1
	holder.Parent = parent
	return holder
end

return Icons
