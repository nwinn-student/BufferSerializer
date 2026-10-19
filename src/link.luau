--!optimize 2
--!strict

local link = {}

type TYPES = "userdata" | "number" | "string" | "vector"
type SERIALIZABLE_TYPES = TYPES | "boolean" | "buffer" | "nil" | "table"

type SerExisting = {
	index: number,
	data: { [any]: number },
	-- round robin
	rr_index: number,
	rr_length: number,
	rr_data: { [number]: any },
}
type DeserExisting = {
	index: number,
	data: { any },
	-- round robin
	rr_index: number,
}

const inflate = require("./inflate")
local serialModules: any
local deserialModules: any

const DUPLICATE_VALUE = 196

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

function link.getSerializer(value: any)
	if not serialModules then
		serialModules = table.freeze({
			["nil"] = require("./nil").serialize,
			boolean = require("./boolean").serialize,
			buffer = require("./buffer").serialize,
			string = require("./string").serialize,
			number = require("./number").serialize,
			vector = require("./vector").serialize,
			table = (require("./table") :: any).serialize,
			userdata = (require("./userdata") :: any).serialize,
		})
	end


	local existingIndex = 1
	const existing: { [any]: number } = { [value] = 0 }
	-- round robin
	const roundRobinCache: { [number]: any } = {}
	local roundRobinLength = 0
	local roundRobinIndex = 61_440

	@native
	local function existingCache(value: any)
		if existingIndex < 61_440 then
			-- cache for rest (only 61_440 values we can cache!!)
			-- for duration of table
			-- value == value checks for nans :>
			existing[value] = existingIndex
			existingIndex += 1
			return
		end
		if roundRobinLength == 4096 then
			if roundRobinIndex == 65_536 then
				roundRobinIndex = 61_440
			end
			-- Cycle time
			existing[value] = roundRobinIndex
			existing[roundRobinCache[roundRobinIndex - 61_439]] = nil
			roundRobinCache[roundRobinIndex - 61_439] = value
			roundRobinIndex += 1
			return
		end
		existing[value] = 61_440 + roundRobinLength
		roundRobinLength += 1
		roundRobinCache[roundRobinLength] = value
	end

	local function perform_cache(value: any, buf: buffer, pos: number)
		local cached = existing[value]
		if cached then
			buf = inflate(buf, pos, 3)
			buffer.writeu8(buf, pos, DUPLICATE_VALUE)
			buffer.writeu16(buf, pos + 1, cached)
			pos += 3
		end
		return buf, pos
	end
	return table.freeze({
		-- So we don't need to add it to serialize?
		-- actually make it a fast/slow path thing instead.
		-- TODO: ^
		cache_lookup_and_add = perform_cache,
		serialize = function(value: any, buf: buffer, pos: number, typeName: string)

			local init_pos = pos

			-- TODO: Needs to pass itself
			buf, pos = serialModules[typeName](value, buf, pos)

			if pos - init_pos > 2 and value == value then
				existingCache(value)
			end

			return buf, pos
		end ,
		append_cache = existingCache,
	})
end

function link.deserializer(buf: buffer, pos: number, valId: number)
	if not deserialModules then
		deserialModules = table.freeze({
			["nil"] = require("./nil").deserialize,
			boolean = require("./boolean").deserialize,
			buffer = require("./buffer").deserialize,
			string = require("./string").deserialize,
			number = require("./number").deserialize,
			vector = require("./vector").deserialize,
			table = (require("./table") :: any).deserialize,
			userdata = (require("./userdata") :: any).deserialize,
		})
	end

	return deserialModules[link.type(valId)](buf, pos, valId)
end

return table.freeze(link)
