--!optimize 2
--!strict
local inflate = require("./inflate")

--[[
	Serializes true/false values 
		into a single byte for storage
	Deserializes a buffer into a boolean value if applicable
]]
return table.freeze({
	serialize = function(value: boolean, buf: buffer, pos: number)
		buf = inflate(buf, pos, 1)

		buffer.writeu8(buf, pos, if value then 1 else 2)
		return buf, pos + 1
	end,
	deserialize = function(buf: buffer, pos: number, valId: number)
		return buffer.readu8(buf, pos) == 1, pos + 1
	end,
})
