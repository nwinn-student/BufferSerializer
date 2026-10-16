--!optimize 2
--!strict
local inflate = require("./inflate")

local EMPTY = 3
local BYTE = 4
local CHAR = 5
local THREE_BYTE = 6
local INT = 7

local EMPTY_BUFFER = buffer.create(0)

return table.freeze({
	serialize = function(value: buffer, buf: buffer, pos: number)
		local len = buffer.len(value)

		if len == 0 then
			buf = inflate(buf, pos, 1)
			buffer.writeu8(buf, pos, EMPTY)
			return buf, pos + 1
		end

		local newSize = if len < 256
			then 2
			elseif len < 65_536 then 3
			elseif len < 16_777_216 then 4
			else 5

		buf = inflate(buf, pos, len + newSize)
		buffer.writeu8(buf, pos, 2 + newSize)

		if len < 256 then
			buffer.writeu8(buf, pos + 1, len)
		elseif len < 65_536 then
			buffer.writeu16(buf, pos + 1, len)
		elseif len < 16_777_216 then
			buffer.writebits(buf, (pos + 1) * 8, (pos + 1) * 8 + 16, len)
		else
			buffer.writeu32(buf, pos + 1, len)
		end

		buffer.copy(buf, pos + newSize, value)
		return buf, pos + newSize + len
	end,

	--[[
		Produces a buffer from the buffer starting at the given position.

		@param buf buffer containing the buffer
		@param pos the starting position of the buffer

		@error Failed to parse buffer
		@error buffer access out of bounds

		@return the buffer and the end buffer position + 1
	]]
	deserialize = function(buf: buffer, pos: number, valId: number)
		if valId == EMPTY then
			return EMPTY_BUFFER, pos + 1
		end

		pos += 1

		local lenSize = valId - EMPTY

		local len: number
		if valId == BYTE then
			len = buffer.readu8(buf, pos)
			pos += lenSize
		elseif valId == CHAR then
			len = buffer.readu16(buf, pos)
			pos += lenSize
		elseif valId == THREE_BYTE then
			len = buffer.readbits(buf, 8 * pos, 24)
			pos += lenSize
		elseif valId == INT then
			len = buffer.readu32(buf, pos)
			pos += lenSize
		else
			error(`Failed to parse buffer using byte: {valId} at position {pos}`)
		end

		local value = buffer.create(len)
		buffer.copy(value, 0, buf, pos, len)
		return value, pos + len
	end,
})
