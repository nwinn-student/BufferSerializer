--!optimize 2
--!strict
local inflate = require("./inflate")
local link = require("./link")

type Serialize = (data: any, buf: buffer, pos: number) -> (buffer, number)

type Deserialize = (buf: buffer, pos: number, valId: number) -> (any, number)

local EMPTY = 194
local TABLE = 195
local EQ_EXISTING = 196
local ARRAY = 197
local DICT = 198
local ARRAY_END = 199
local TABLE_END = 200

function tabSerializer(value: { [any]: any }, buf: buffer, pos: number)
	do
		local isEmpty = true
		for _, _ in value do
			isEmpty = false
			break
		end
		if isEmpty then
			buf = inflate(buf, pos, 1)
			buffer.writeu8(buf, pos, EMPTY)
			return buf, pos + 1
		end
	end

	local existingIndex = 1
	local existing: { [any]: number } = { [value] = 0 }
	local roundRobinCache: { [number]: any } = {}
	local roundRobinLength = 0
	local roundRobinIndex = 61440

	local serialTable: (data: { [any]: any }) -> ()

	@native
	local function existingCache(data: any)
		if existingIndex < 61_440 then
			-- cache for rest (only 61_440 values we can cache!!)
			-- for duration of table
			-- data == data checks for nans :>
			existing[data] = existingIndex
			existingIndex += 1
			return
		end
		if roundRobinLength == 4096 then
			if roundRobinIndex == 65_536 then
				roundRobinIndex = 61_440
			end
			-- Cycle time
			existing[data] = roundRobinIndex
			existing[roundRobinCache[roundRobinIndex - 61_439]] = nil
			roundRobinCache[roundRobinIndex - 61_439] = data
			roundRobinIndex += 1
			return
		end
		existing[data] = 61_440 + roundRobinLength
		roundRobinLength += 1
		roundRobinCache[roundRobinLength] = data
	end

	@native
	local function serialCache(data: any, typeName: string)
		if typeName == "table" then
			-- ISSUE: A table cycle may be so deep that it bypasses existing altogether
			-- We will need to ensure the cycle is nonproblematic
			-- Currently: Assumed improbable

			existingCache(data)

			do
				local isEmpty = true
				for _, _ in data :: { [any]: any } do
					isEmpty = false
					break
				end
				if isEmpty then
					buf = inflate(buf, pos, 1)
					buffer.writeu8(buf, pos, EMPTY)
					pos += 1
					return
				end
			end

			serialTable(data)
			return
		end

		local oldPos = pos
		buf, pos = link.serializer(data, buf, pos)

		if pos - oldPos > 2 and data == data then
			existingCache(data)
		end
	end

	@native
	function serialTable(data: { [any]: any })
		local isDict = #data == 0
		buf = inflate(buf, pos, 1)

		pos += 1

		local oldPos = pos
		local endArray = false
		local lastIndex = 1

		for key, element in data do
			-- Array section
			if lastIndex == key then
				lastIndex += 1

				local cached = existing[element]
				if cached then
					buf = inflate(buf, pos, 3)
					buffer.writeu8(buf, pos, EQ_EXISTING)
					buffer.writeu16(buf, pos + 1, cached)
					pos += 3
					continue
				end

				local typeElement = type(element)

				if typeElement == "function" or typeElement == "thread" then
					pos += 1
					continue
				end

				serialCache(element, typeElement)
				continue
			end
			if not endArray and not isDict then
				endArray = true
				buf = inflate(buf, pos, 1)
				buffer.writeu8(buf, pos, ARRAY_END)
				pos += 1
			end

			-- Dictionary section
			local typeKey = type(key)
			if typeKey == "function" or typeKey == "thread" then
				continue
			end

			local typeElement = type(element)
			if typeElement == "function" or typeElement == "thread" then
				continue
			end

			local cached = existing[key]
			if cached then
				buf = inflate(buf, pos, 3)
				buffer.writeu8(buf, pos, EQ_EXISTING)
				buffer.writeu16(buf, pos + 1, cached)
				pos += 3
			else
				-- store key
				serialCache(key, typeKey)
			end

			cached = existing[element]
			if cached then
				buf = inflate(buf, pos, 3)
				-- writebits is not faster
				buffer.writeu8(buf, pos, EQ_EXISTING)
				buffer.writeu16(buf, pos + 1, cached)
				pos += 3
				continue
			end

			-- store element
			serialCache(element, typeElement)
		end

		if isDict then
			buffer.writeu8(buf, oldPos - 1, DICT)
		else
			buffer.writeu8(buf, oldPos - 1, if not endArray then ARRAY else TABLE)
		end
		buf = inflate(buf, pos, 1)
		buffer.writeu8(buf, pos, TABLE_END)
		pos += 1
	end

	serialTable(value)

	table.clear(existing)
	if roundRobinLength > 0 then
		table.clear(roundRobinCache)
	end

	return buf, pos
end

--[[
	Produces a table from the buffer starting at the given position
	 and ending once a matching terminator is found.

	@param buf buffer containing the table
	@param pos the starting position of the table

	@error Failed to parse buffer
	@error Failed to parse string
	@error Failed to parse number
	@error Failed to parse built-in vector constant
	@error Failed to parse vector
	@error Failed to parse userdata
	@error Invalid custom userdata value
	@error Failed to parse table
	@error Failed to parse existing value
	@error Failed to parse nil in a dictionary
	@error Failed to parse future
	@error Failed to parse extension
	@error buffer access out of bounds

	@return the table and the termination position + 1 of the table
]]
function tabDeserializer(buf: buffer, pos: number, valId: number)
	local returnedTab = {}

	if valId == EMPTY then
		return returnedTab, pos + 1
	end

	if valId ~= ARRAY and valId ~= TABLE and valId ~= DICT then
		error(
			`Failed to parse table using byte: {valId} at position {pos} (expected {ARRAY}, {TABLE}, or {DICT})`
		)
	end

	local existingIndex = 1
	local existing: { any } = { [0] = returnedTab }
	local roundRobinIndex = 61_440

	local deserialTable: (data: { [any]: any }) -> { [any]: any }

	@native
	local function existingCache(data: any)
		if existingIndex < 61_440 then
			existing[existingIndex] = data
			existingIndex += 1
			return
		end
		if roundRobinIndex == 65_536 then
			roundRobinIndex = 61_440
		end
		-- Cycle time
		existing[roundRobinIndex] = data
		roundRobinIndex += 1
	end

	@native
	local function deserialCache(valId: number): unknown
		if valId == EMPTY then
			local value = {}
			pos += 1
			existingCache(value)
			return value
		elseif valId == TABLE or valId == ARRAY or valId == DICT then
			local value = {}
			existingCache(value)
			return deserialTable(value, valId)
		elseif valId > EMPTY and valId <= TABLE_END + 1 then
			error(`Failed to parse table using byte: {valId} at position {pos}`)
		end

		local value: any = nil
		local oldPos = pos

		value, pos = link.deserializer(buf, pos, valId)

		if pos - 2 > oldPos then
			existingCache(value)
		end
		return value
	end

	@native
	function deserialTable(data: { [any]: any }, valId: number): { [any]: any }
		pos += 1

		local hasArray = valId == ARRAY or valId == TABLE

		if hasArray then
			local index = 0
			while true do
				local inner_id = buffer.readu8(buf, pos)

				if inner_id == ARRAY_END then
					pos += 1
					break -- if there is no end, it will error!
				end
				if inner_id == TABLE_END then
					pos += 1
					return data -- for ARRAY
				end

				index += 1
				if inner_id == 0 then
					pos += 1
					continue
				end

				local value

				-- check if existing
				if inner_id == EQ_EXISTING then
					local existingId = buffer.readu16(buf, pos + 1)
					value = existing[existingId]
					pos += 3
					if value == nil then
						error(
							`Failed to parse existing value using byte: {existingId} at position {pos}`
						)
					end
					data[index] = value
					continue
				end

				value = deserialCache(inner_id)

				data[index] = value
			end
		end

		while true do
			local inner_id = buffer.readu8(buf, pos)
			if inner_id == TABLE_END then
				pos += 1
				return data
			end

			local key, value

			-- check if existing
			if inner_id == EQ_EXISTING then
				local existingId = buffer.readu16(buf, pos + 1)
				key = existing[existingId]
				if key == nil then
					error(
						`Failed to parse existing value using byte: {existingId} at position {pos}`
					)
				end
				pos += 3
			end

			if not key then
				key = deserialCache(inner_id)
				if key == nil then
					error(`Failed to parse nil in a dictionary at position {pos}`)
				elseif key ~= key then
					error(`Failed to parse NaN in a dictionary at position {pos}`)
				end
			end

			inner_id = buffer.readu8(buf, pos)

			-- check if existing
			if inner_id == EQ_EXISTING then
				local existingId = buffer.readu16(buf, pos + 1)
				value = existing[existingId]
				if value == nil then
					error(
						`Failed to parse existing value using byte: {existingId} at position {pos}`
					)
				end
				pos += 3
				data[key] = value
				continue
			end

			value = deserialCache(inner_id)

			assert(
				value ~= nil,
				`Failed to parse nil in a dictionary at position {pos}`
			)

			data[key] = value
		end
	end

	local data = deserialTable(returnedTab, valId)

	table.clear(existing)

	return data, pos
end

return table.freeze({
	serialize = tabSerializer,
	deserialize = tabDeserializer,
})
