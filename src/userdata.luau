--!optimize 2
--!strict
local inflate = require("./inflate")
local link = require("./link")

local STRUCTEND = 200
local CUSTOM = 202
local UNSUPPORTED = 203

type Support = {
	serialize: (value: any, serializer: (value: any) -> ()) -> (),
	deserialize: (...any) -> (),
}

local supports = {
	serializers = {},
	deserializers = {},
}

local function writeUnsupported(buf: buffer, pos: number)
	buf = inflate(buf, pos, 1)
	buffer.writeu8(buf, pos, UNSUPPORTED)
	return buf, pos + 1
end

function userSerializer(
	value: any,
	buf: buffer,
	pos: number,
	serializer: (
		value: any,
		buf: buffer,
		pos: number,
		typeName: string
	) -> (buffer, number)
)
	if #supports.serializers == 0 then
		return writeUnsupported(buf, pos)
	end

	local end_buf: buffer, end_pos: number
	local isSupported: boolean = false

	buf = inflate(buf, pos, 2)
	buffer.writeu8(buf, pos, CUSTOM)

	local temp_buf, temp_pos = buf, pos + 1
	local function serializationFunc(value: any)
		assert(not isSupported)
		temp_buf, temp_pos = serializer(value, temp_buf, temp_pos, type(value))
		isSupported = true
	end

	-- this is faster than functions that call functions (since we would need to wrap each)
	for _, serializer in supports.serializers do
		serializer(value, serializationFunc)
		if isSupported then
			end_buf, end_pos = temp_buf, temp_pos
			break
		end
	end

	-- we know no modifications to the buffer!!
	if not isSupported then
		return writeUnsupported(buf, pos)
	end

	end_buf = inflate(end_buf, end_pos, 1)
	buffer.writeu8(end_buf, end_pos, STRUCTEND)

	return end_buf, end_pos + 1
end

--[[
	Produces a userdata from the buffer starting at the given position.

	@param buf buffer containing the userdata
	@param pos the starting position of the userdata

	@error Failed to parse userdata
	@error Invalid custom userdata value
	@error buffer access out of bounds

	@return the userdata and the end of the userdata position + 1
]]
function userDeserializer(buf: buffer, pos: number, valId: number)
	local startingPosition = pos

	if valId == UNSUPPORTED then
		local unsupported = newproxy()
		return unsupported, pos + 1
	end

	if valId ~= CUSTOM then
		error(`Failed to parse userdata using byte: {valId} at position {pos}`)
	end

	local data = nil

	local inner_data = {}
	do
		local inner_pos = pos + 1
		local inner_id = buffer.readu8(buf, inner_pos)

		-- CUSTOM STRUCTEND, interpretted as unsupported
		if inner_id == STRUCTEND then
			local unsupported = newproxy()
			return unsupported, inner_pos + 1
		end

		while inner_id ~= STRUCTEND do
			local inner_value
			inner_value, inner_pos = link.deserializer(buf, inner_pos, inner_id)
			table.insert(inner_data, inner_value)
			-- look at the next header byte
			inner_id = buffer.readu8(buf, inner_pos)
		end

		pos = inner_pos
	end

	for _, deserializer in supports.deserializers do
		local temp_data = deserializer(table.unpack(inner_data))
		if temp_data ~= nil then
			data = temp_data
			break
		end
	end

	-- no returning values that cause tables to error
	if data == nil or data ~= data then
		error(
			`Invalid custom userdata value: got {data} at position {startingPosition}`
		)
	end

	-- pass the STRUCTEND byte
	return data, pos + 1
end

--[[
	Adds support for a userdata or group of userdata to be
	 (de)serialized.

	- The provided functions will be called on a last to first supported basis.
	- Duplicate support functions will be shifted to the front.

	**Recommendations:**
	- Group userdata supported by the same environment/runtime together.
	- Consider that later supported functions may attempt to handle the
	 supported userdata, which may be undesirable since they are called **first**.
	  - If undesirable, privatize `BufferSerializer` and provide a public wrapper that
	   replaces `bs.supportUserdata` with:
	  ```luau
	  local function supportUserdata(record: bs.UserdataSupport): ()
		bs.supportUserdata(record)
		-- main_record is defined earlier and **must** run first
		bs.supportUserdata(main_record)
	  end
	  ```
	- Provide and read documentation surrounding the supported userdata.
	  - Conflicting bytecode or opcodes will either corrupt data or cause errors.
	  - Removing or modifying support can also corrupt data or cause errors.

	**Example**
	```luau
	local BufferSerializer = require("@BufferSerializer")

	local sample_userdata = newproxy()
	local sample_id = 0

	BufferSerializer.supportUserdata({
		serialize = function(value: any, serializer: (value: any) -> ())
			if value ~= sample_userdata then
				return
			end
			serializer(sample_id)
		end,
		deserialize = function(...: any)
			local id = ...
			if id == sample_id then
				return sample_userdata
			end
			return nil
		end,
	})

	local serialData = BufferSerializer.serialize(sample_userdata)
	```

	@param record the container holding the (de)serialize functions

	@error Invalid type: When record is not a table
	@error Incomplete record: When record is missing (de)serialize
	@error Invalid property: When the property isn't (de)serialize
	@error Invalid property type: When (de)serialize isn't a function
]]
function addSupport(record: Support)
	assert(
		type(record) == "table",
		`Invalid type: expected table (got {type(record)})`
	)
	assert(record.serialize, `Incomplete record: missing property serialize`)
	assert(record.deserialize, `Incomplete record: missing property deserialize`)

	for name, value in record :: { [string]: any } do
		assert(
			name == "serialize" or name == "deserialize",
			`Invalid property: {name} is not "serialize" or "deserialize"`
		)
		assert(
			type(value) == "function",
			`Invalid property type: expected function for {name} (got {type(value)})`
		)
	end

	local old_serial_pos = table.find(supports.serializers, record.serialize)
	local old_deserial_pos =
		table.find(supports.deserializers, record.deserialize)

	table.insert(supports.serializers, 1, record.serialize)
	table.insert(supports.deserializers, 1, record.deserialize)

	if old_serial_pos then
		table.remove(supports.serializers, old_serial_pos + 1)
	end
	if old_deserial_pos then
		table.remove(supports.deserializers, old_deserial_pos + 1)
	end
end

local Userdata = {
	serialize = userSerializer,
	deserialize = userDeserializer,
	addSupport = addSupport,
}

return table.freeze(Userdata)
