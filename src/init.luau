--!optimize 2
--!strict

local function trim(data: buffer, pos: number)
	if pos == buffer.len(data) then
		return data
	end

	local newBuffer = buffer.create(pos)

	buffer.copy(newBuffer, 0, data, 0, pos)

	return newBuffer
end

-- TODO: Add documentation
local BufferSerializer = {}

local link = require("@self/link")
local userdata = require("@self/userdata")

type Serialize = (value: any, buf: buffer, pos: number) -> (buffer, number)
type Deserialize = (buf: buffer, pos: number, valId: number) -> (any, number)

--[[
	Serializes the provided value into a buffer.

	- Follows the specified format in [FORMAT.md](../FORMAT.md).

	**Recommendations:**
	- Protect value from concurrent modifications, specifically tables and buffers.

	**Example:**
	```luau
	local BufferSerializer = require("./path/to/BufferSerializer")

	local serialData = BufferSerializer.serialize({ "Foo", "Foo" })
	```

	@param value the value to serialize
	
	@return a buffer representing the serialized value
]]
function BufferSerializer.serialize(value: any): buffer
	local typeValue = type(value)
	if typeValue == "function" or typeValue == "thread" then
		typeValue = "nil"
	end

	local buf, pos = link.serializer(value, buffer.create(0), 0)

	return trim(buf, pos)
end

--[[
	Deserializes the provided buffer, producing the value originally serialized.

	- Operates under the assumption that the buffer follows the specified format in
	   [spec](../spec/format.md).
	- Capable of deserializing values impossible for `serialize` to produce.

	**Recommendations:**
	- Protect value from concurrent modifications.

	**Example:**
	```luau
	local BufferSerializer = require("./path/to/BufferSerializer")
	local serialData = BufferSerializer.serialize({ "Foo", "Foo" })

	local originData = BufferSerializer.deserialize(serialData)
	```

	@param value buffer containing a serialized value

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

	@return the original value
]]
function BufferSerializer.deserialize(value: buffer): any
	local valId = buffer.readu8(value, 0)
	if valId == 0 then
	local valId = buffer.readu8(value, 0)
	if valId == 0 then
		return nil
	end

	return (link.deserializer(value, 0, valId))
end

--[[
	A dictionary for `BufferSerializer.supportUserdata`, with the following available values:
	- `serialize` - A function for serializing userdata
	- `deserialize` - A function for deserializing userdata
]]
export type UserdataSupport = {
	--[[
		Forwards values that can be used to recreate the `value` userdata to the
		 `serializer` function.
	
		@param value - the userdata to serialize
		@param serializer - the function to pass representational values in
	]]
	serialize: (value: any, serializer: (value: any) -> ()) -> (),
	--[[
		Produces a userdata based on a tuple of values.

		@param ... - a tuple of values

		@return the userdata
	]]
	deserialize: (...any) -> any,
}

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
		deserialize = function(...any)
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
function BufferSerializer.supportUserdata(record: UserdataSupport)
	userdata.addSupport(record)
end

--[[
	Returns whether the userdata is capable of being serialized and deserialized.

	- Meaning the userdata does not deserialize into an unsupported userdata.

	**Recommendations:**
	- Ensure the userdata deserializes into the desired form.

	@param ud the userdata to check

	@error Failed to parse userdata
	@error Invalid custom userdata value
	@error buffer access out of bounds
]]
function BufferSerializer.isSupported(ud: any): boolean
	local buf, pos = userdata.serialize(ud, buffer.create(0), 0)

	userdata.deserialize(buf, 0, buffer.readu8(buf, 0))
	-- Only unsupported userdata can return pos == 1
	return pos ~= 1
end

return table.freeze(BufferSerializer)
