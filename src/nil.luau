--!optimize 2
--!strict
local inflate = require("./inflate")

--[[
	Serializes nil values 
		into a single byte for storage
	Deserializes a buffer into a nil value if applicable
]]
return table.freeze({
	serialize = function(value: nil, buf: buffer, pos: number)
		buf = inflate(buf, pos, 1)
		buffer.writeu8(buf, pos, 0)
		return buf, pos + 1
	end,
	deserialize = function(buf: buffer, pos: number, valId: number)
		return nil, pos + 1
	end,
})
