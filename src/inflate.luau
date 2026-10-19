--!optimize 2
--!strict

local function inflateInternal(data: buffer, size: number)
	if size <= buffer.len(data) then
		return data
	end

	local newBuffer = buffer.create(size)

	buffer.copy(newBuffer, 0, data)

	return newBuffer
end

--[[
	Inflates the buffer size to be at least the new position.

	- Uses a doubling approach to inflate.
]]
local function inflate(data: buffer, pos: number, len: number)
	local bits = bit32.countlz(pos + len)

	if bit32.countlz(pos) == bits then
		return data
	end

	return inflateInternal(data, 2 ^ (32 - bits))
end

return inflate
