--!optimize 2
--!strict
local inflate = require("./inflate")

local ZERO = 97
local ONE = 98
local BYTE = 99
local CHAR = 100
local THREE_BYTE = 101
local INT = 102
local FLOAT = 103
local DOUBLE = 104
local NAN = 105

local MIN_BYTE = -2 ^ 7
local MAX_BYTE = 2 ^ 7 - 1

local MIN_CHAR = -2 ^ 15
local MAX_CHAR = 2 ^ 15 - 1

local MIN_THREE = -2 ^ 23
local MAX_THREE = 2 ^ 23 - 1

local MIN_INT = -2 ^ 31
local MAX_INT = 2 ^ 31 - 1

local MAX_FLOAT = 2 ^ 127

local vecX = vector.create(1, 0)

@native
local function numSerializer(value: number, buf: buffer, pos: number)
	if value == 0 or value == 1 or value ~= value then
		buf = inflate(buf, pos, 1)

		buffer.writeu8(
			buf,
			pos,
			if value == 0 then ZERO elseif value == 1 then ONE else NAN
		)

		return buf, pos + 1
	end

	-- Floating points
	if value % 1 ~= 0 or value > MAX_INT or value < MIN_INT then
		if MAX_FLOAT < value or value < -MAX_FLOAT then
			buf = inflate(buf, pos, 9)
			buffer.writeu8(buf, pos, DOUBLE)
			buffer.writef64(buf, pos + 1, value)
			return buf, pos + 9
		end

		-- Ensures that the output WILL be the same as the input
		-- even if it results in a slower path
		if (vecX * value).x == value then
			buf = inflate(buf, pos, 5)
			buffer.writeu8(buf, pos, FLOAT)
			buffer.writef32(buf, pos + 1, value)
			return buf, pos + 5
		end

		buf = inflate(buf, pos, 9)
		buffer.writeu8(buf, pos, DOUBLE)
		buffer.writef64(buf, pos + 1, value)
		return buf, pos + 9
	end

	local newSize = if MAX_BYTE >= value and value >= MIN_BYTE
		then 2
		elseif MAX_CHAR >= value and value >= MIN_CHAR then 3
		elseif MAX_THREE >= value and value >= MIN_THREE then 4
		else 5

	buf = inflate(buf, pos, newSize)
	buffer.writeu8(buf, pos, ZERO + newSize)

	if newSize == 2 then
		buffer.writei8(buf, pos + 1, value)
	elseif newSize == 3 then
		buffer.writei16(buf, pos + 1, value)
	elseif newSize == 4 then
		buffer.writebits(buf, (pos + 1) * 8, 24, value)
	else
		buffer.writei32(buf, pos + 1, value)
	end
	return buf, pos + newSize
end

--[[
	Produces a number from the buffer starting at the given position.

	@param buf buffer containing the number
	@param pos the starting position of the number

	@error Failed to parse number
	@error buffer access out of bounds

	@return the number and the end number position + 1
]]
@native
local function numDeserializer(buf: buffer, pos: number, valId: number)
	if valId == ZERO then
		return 0, pos + 1
	elseif valId == ONE then
		return 1, pos + 1
	elseif valId == NAN then
		return 0 / 0, pos + 1
	end

	if valId == BYTE then
		return buffer.readi8(buf, pos + 1), pos + 2
	elseif valId == CHAR then
		return buffer.readi16(buf, pos + 1), pos + 3
	elseif valId == THREE_BYTE then
		local val = buffer.readbits(buf, (pos + 1) * 8, 24)
		if val >= 2 ^ 23 then
			return (-2 ^ 24) + val, pos + 4
		end
		return val, pos + 4
	elseif valId == INT then
		return buffer.readi32(buf, pos + 1), pos + 5
	elseif valId == FLOAT then
		return buffer.readf32(buf, pos + 1), pos + 5
	elseif valId == DOUBLE then
		return buffer.readf64(buf, pos + 1), pos + 9
	else
		error(`Failed to parse number using byte: {valId} at position {pos}`)
	end
end

local Number = {
	serialize = numSerializer,
	deserialize = numDeserializer,
}

return table.freeze(Number)
