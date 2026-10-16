--!optimize 2
local bufferSerial = require("@BufferSerializer")

--[[
	Note: The below example at any point in time may fail to
	 function due to external reliance.

	Specification for userdata:
	 [0] = BrickColor (2 + number bytes (3-5))
	 [1] = Color3 (2 + R / G / B bytes (5))
	 [2] = EnumItem (2 + number + number bytes (4-8))
	 [3] = CFrame (2 + vector + vector bytes (4-28))
	 [4] = Ray (2 + vector + vector bytes (4-28))
	 [5] = Instance (2 + tabSize bytes (16+?))
	 [6] = Enum (2 + number bytes (4-6)) (max number is char??)
	 [7] = UDim (2 + number + number (4-12)) (max number is float)
	 [8] = UDim2 (2 + number + number + number + number) (max number is float)
	 [9] = Vector2 (2 + number + number bytes (4-12)) (max number is float)
	 [10] = NumberSequence (2 + table (8+)) (table is { NumberSequenceKeypoint })
	 [11] = ColorSequence (2 + table (10+)) (table is { ColorSequenceKeypoint })
	 [12] = NumberRange (2 + number + number ())
	 [13] = Rect (2 + number + number + number + number (6-22)) (max number is float)
	 [14] = Font (2 + string + number + number (5-?)) (max number is char?)
	 [15] = NumberSequenceKeypoint (2 + number + number + number (5-?))
	 [16] = ColorSequenceKeypoint (2 + (R / G / B) + number (6-?))
	 -- add more as needed
]]

-- the only dependancy, Instances are not as simple to support
-- Location: https://github.com/Gem-API/Rose
local rose = require("./extern/rose")

local BRICKCOLOR = 0
local COLOR3 = 1
local ENUMITEM = 2
local CFRAME = 3
local RAY = 4
local INSTANCE = 5
local ENUM = 6
local UDIM = 7
local UDIM2 = 8
local VECTOR2 = 9 -- Vector3 is a vector, NOT a userdata
local NUMBER_SEQUENCE = 10
local COLOR_SEQUENCE = 11
local NUMBER_RANGE = 12
local RECT = 13
local FONT = 14
local NUMBER_SEQUENCE_KEYPOINT = 15
local COLOR_SEQUENCE_KEYPOINT = 16

local EnumList = Enum:GetEnums()

local function ColorToNumber(value: Color3): number
	return tonumber(value:ToHex(), 16) or 0
end

local function NumberToColor(value: number): Color3
	local r, g, b
	r = bit32.extract(value, 16, 8)
	g = bit32.extract(value, 8, 8)
	b = bit32.extract(value, 0, 8)
	return Color3.fromRGB(r, g, b)
end

@native
local function userdataWriter(value: any, serializer: (value: any) -> ())
	local userType = typeof(value)
	if userType == "BrickColor" then
		serializer(BRICKCOLOR)
		serializer(value.Number)
	elseif userType == "Color3" then
		serializer(COLOR3)
		serializer(ColorToNumber(value))
	elseif userType == "EnumItem" then
		serializer(ENUMITEM)
		serializer(table.find(EnumList, value.EnumType))
		serializer(value.Value)
	elseif userType == "CFrame" then
		serializer(CFRAME)
		serializer(value.Position)

		local x, y, z = value:ToEulerAnglesXYZ()
		serializer(vector.create(x, y, z))
	elseif userType == "Ray" then
		serializer(RAY)
		serializer(value.Origin)
		serializer(value.Direction)
	elseif userType == "Instance" then
		serializer(INSTANCE)
		serializer(rose.serialize(value))
	elseif userType == "Enum" then
		serializer(ENUM)
		serializer(table.find(EnumList, value))
	elseif userType == "UDim" then
		serializer(UDIM)
		serializer(value.Scale)
		serializer(value.Offset)
	elseif userType == "UDim2" then
		serializer(UDIM2)
		serializer(value.X.Scale)
		serializer(value.X.Offset)
		serializer(value.Y.Scale)
		serializer(value.Y.Offset)
	elseif userType == "Vector2" then
		serializer(VECTOR2)
		serializer(value.X)
		serializer(value.Y)
	elseif userType == "NumberSequence" then
		serializer(NUMBER_SEQUENCE)
		serializer(value.Keypoints)
	elseif userType == "NumberSequenceKeypoint" then
		serializer(NUMBER_SEQUENCE_KEYPOINT)
		serializer(value.Time)
		serializer(value.Value)
		serializer(value.Envelope)
	elseif userType == "ColorSequence" then
		serializer(COLOR_SEQUENCE)
		serializer(value.Keypoints)
	elseif userType == "ColorSequenceKeypoint" then
		serializer(COLOR_SEQUENCE_KEYPOINT)
		serializer(ColorToNumber(value))
		serializer(value.Time)
	elseif userType == "NumberRange" then
		serializer(NUMBER_RANGE)
		serializer(value.Min)
		serializer(value.Max)
	elseif userType == "Rect" then
		serializer(RECT)
		serializer(value.Min.X)
		serializer(value.Min.Y)
		serializer(value.Max.X)
		serializer(value.Max.Y)
	elseif userType == "Font" then
		serializer(FONT)
		serializer(value.Family)
		serializer(value.Weight.Value)
		serializer(value.Style.Value)
	end
end

@native
local function userdataReader(id: number?, ...: any): any
	local obj

	local args = { ... }

	if id == BRICKCOLOR then
		obj = BrickColor.new(args[1])
	elseif id == COLOR3 then
		obj = NumberToColor(args[1])
	elseif id == ENUMITEM then
		local enumVal, valNum = args[1], args[2]

		obj = EnumList[enumVal]:FromValue(valNum)
	elseif id == CFRAME then
		local posVector, eulerVector = args[1], args[2]

		obj = CFrame.fromEulerAngles(eulerVector.x, eulerVector.y, eulerVector.z)
			+ posVector
	elseif id == RAY then
		obj = Ray.new(args[1], args[2])
	elseif id == INSTANCE then
		-- the parent is nil!
		obj = rose.deserialize(args[1])
	elseif id == ENUM then
		obj = EnumList[args[1]]
	elseif id == UDIM then
		local scale, offset = args[1], args[2]

		obj = UDim.new(scale, offset)
	elseif id == UDIM2 then
		local xScale, xOffset, yScale, yOffset =
			args[1], args[2], args[3], args[4]

		obj = UDim2.new(xScale, xOffset, yScale, yOffset)
	elseif id == VECTOR2 then
		local x, y = args[1], args[2]

		obj = Vector2.new(x, y)
	elseif id == NUMBER_SEQUENCE then
		obj = NumberSequence.new(args[1])
	elseif id == NUMBER_SEQUENCE_KEYPOINT then
		local time, value, envelope = args[1], args[2], args[3]

		obj = NumberSequenceKeypoint.new(time, value, envelope)
	elseif id == COLOR_SEQUENCE then
		obj = ColorSequence.new(args[1])
	elseif id == COLOR_SEQUENCE_KEYPOINT then
		local color, time = NumberToColor(args[1]), args[2]

		obj = ColorSequenceKeypoint.new(time, color)
	elseif id == NUMBER_RANGE then
		local min, max = args[1], args[2]

		obj = NumberRange.new(min, max)
	elseif id == RECT then
		local minX, minY, maxX, maxY = args[1], args[2], args[3], args[4]

		obj = Rect.new(minX, minY, maxX, maxY)
	elseif id == FONT then
		local family, weightId, styleId = args[1], args[2], args[3]

		obj = Font.new(
			family,
			Enum.FontWeight:FromValue(weightId),
			Enum.FontStyle:FromValue(styleId)
		)
	end

	return obj
end

bufferSerial.supportUserdata({
	serialize = userdataWriter,
	deserialize = userdataReader,
})

return bufferSerial
