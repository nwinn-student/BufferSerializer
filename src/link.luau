--!optimize 2
--!strict

local link = {}

type TYPES = "userdata" | "number" | "string" | "vector"
type SERIALIZABLE_TYPES = TYPES | "boolean" | "buffer" | "nil" | "table"

local serialModules: any
local deserialModules: any

--[[
	Returns the type of reference id

	@param refId the byte containing the type and location of the id paired to a value
]]
@native
function link.type(refId: number): SERIALIZABLE_TYPES
	return if refId == 0
		then "nil"
		elseif refId <= 2 then "boolean"
		elseif refId <= 7 then "buffer"
		elseif refId <= 96 then "string"
		elseif refId <= 141 then "number"
		elseif refId <= 193 then "vector"
		elseif refId <= 201 then "table"
		elseif refId <= 215 then "userdata"
		else "nil" -- add more if statements if needed for future
end

function link.serializer(value: any, buf: buffer, pos: number)
	if not serialModules then
		serialModules = table.freeze({
			["nil"] = require("./nil").serialize,
			boolean = require("./boolean").serialize,
			buffer = require("./buffer").serialize,
			string = require("./string").serialize,
			number = require("./number").serialize,
			vector = require("./vector").serialize,
			table = require("./table").serialize,
			userdata = require("./userdata").serialize,
		})
	end

	return serialModules[type(value)](value, buf, pos)
end

function link.deserializer(buf: buffer, pos: number, valId: number)
	deserialModules = table.freeze({
		["nil"] = require("./nil").deserialize,
		boolean = require("./boolean").deserialize,
		buffer = require("./buffer").deserialize,
		string = require("./string").deserialize,
		number = require("./number").deserialize,
		vector = require("./vector").deserialize,
		table = require("./table").deserialize,
		userdata = require("./userdata").deserialize,
	})

	return deserialModules[link.type(valId)](buf, pos)
end

return table.freeze(link)
