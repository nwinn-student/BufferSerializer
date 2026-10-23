--------------------------------------------------------------------------------
--                                                                            --
--                  `7MM"""Mq.            .M"""bgd                            --
--                    MM   `MM.          ,MI    "Y                            --
--                    MM   ,M9  ,pW"Wq.  `MMb.      .gP"Ya                    --
--                    MMmmdM9  6W'   `Wb   `YMMNq. ,M'   Yb                   --
--                    MM  YM.  8M     M8 .     `MM 8M""""""                   --
--                    MM   `Mb.YA.   ,A9 Mb     dM YM.    ,                   --
--                  .JMML. .JMM.`Ybmd9'  P"Ybmmd"   `Mbmmd'                   --
--                                                                            --
--                         Roblox Instance Serializer                         --
--                                                                            --
--------------------------------------------------------------------------------
--                                                                            --
--  Copyright (c) Gem_API                                                     --
--                                                                            --
--  Permission is hereby granted, free of charge, to any person obtaining     --
--  a copy of this software and associated documentation files (the           --
--  "Software"), to deal in the Software without restriction, including       --
--  without limitation the rights to use, copy, modify, merge, publish,       --
--  distribute, sublicense, and/or sell copies of the Software, and to        --
--  permit persons to whom the Software is furnished to do so, subject to     --
--  the following conditions:                                                 --
--                                                                            --
--  The above copyright notice and this permission notice shall be            --
--  included in all copies or substantial portions of the Software.           --
--                                                                            --
--  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,           --
--  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF        --
--  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.    --
--  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY      --
--  CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,      --
--  TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE         --
--  SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                    --
--                                                                            --
--------------------------------------------------------------------------------
--[[
	API

	rose.serialize
	rose.deserialize

	Notes:
	- All Roblox userdata is supported. (?)
	- Format: { class, properties, children, attributes }
	- Is specialized towards BufferSerializer and merely converts Instances
	 into a simpler form.
	- Follows the similar rules to Rose.  No backreferences and Parent is not set except when known.
		ObjectValue may never be supported.

		Does NOT do the existing thing, that is too much work for now.

	You can store the following types/values in attributes:
	- string, boolean, number
	- UDim, UDim2, BrickColor, Color3, Vector2, Vector3,
		CFrame, NumberSequence, ColorSequence, NumberRange, Rect, Font
	- Undocumented, but you can store EnumItems in attributes
]]

type SerialFormat = {
	number -- class Index
	| { any }? -- properties, w/o defaults
	| { Instance }? -- children
	| { [string]: any }? -- attributes
}

-- ADD INSTANCES TO SUPPORT AND THEIR PROPERTIES
local INSTANCE_ORDER = {
	"Folder",
	"Model",
	"StringValue",
	"BoolValue",
	"NumberValue",
	"CFrameValue",
	"Vector3Value",
	"BrickColorValue",
	"Color3Value",
	"RayValue",

	-- ADD MORE BELOW (order matters)
}

-- To add more Properties to save, append them to the end (order matters)
local VALUE_INSTANCES = { "Name", "Value" }

local SUPPORTED_INSTANCES = {
	Folder = { "Name" },
	StringValue = VALUE_INSTANCES,
	BoolValue = VALUE_INSTANCES,
	NumberValue = VALUE_INSTANCES,
	CFrameValue = VALUE_INSTANCES,
	Vector3Value = VALUE_INSTANCES,
	BrickColorValue = VALUE_INSTANCES,
	Color3Value = VALUE_INSTANCES,
	RayValue = VALUE_INSTANCES,

	-- ADD MORE BELOW
}

local DEFAULT_INSTANCES = {}
local INVERTED_ORDER = {}

for className in SUPPORTED_INSTANCES do
	DEFAULT_INSTANCES[className] = Instance.new(className)
end
for index, className in INSTANCE_ORDER do
	INVERTED_ORDER[className] = index
end

function serialize_instance(obj: Instance)
	local class_name = obj.ClassName
	local prop_pool = SUPPORTED_INSTANCES[class_name]
	local default_instance = DEFAULT_INSTANCES[class_name]

	local props = {}

	if not prop_pool then
		print(`UNSUPPORT INSTANCE CLASS: {class_name}; INSTANCE:`, obj)
		prop_pool = SUPPORTED_INSTANCES.Folder
	end

	for index, property in prop_pool do
		local object_property = obj[property]
		if default_instance[property] == object_property then
			continue
		end
		props[index] = object_property
	end
	if next(props) == nil then
		props = nil
	end

	local children = obj:GetChildren()
	if #children == 0 then
		children = nil
	end

	local attributes = obj:GetAttributes()
	if next(attributes) == nil then
		attributes = nil
	end

	return {
		INVERTED_ORDER[class_name],
		props,
		children,
		attributes,
	}
end

function deserialize_instance(obj: SerialFormat, parent: Instance?)
	local class_index = obj[1]
	local class_name = INSTANCE_ORDER[class_index]
	local instance = Instance.new(class_name)

	local properties = obj[2]
	if properties then
		local prop_pool = SUPPORTED_INSTANCES[class_name]

		for index, value in properties do
			local property = prop_pool[index]
			instance[property] = value
		end
	end

	local children = obj[3]
	if children then
		for _, child in children do
			child.Parent = instance
		end
	end

	local attributes = obj[4]
	if attributes then
		for key, value in attributes do
			instance:SetAttribute(key, value)
		end
	end

	instance.Parent = parent

	return instance
end

local rose = {}

function rose.serialize(data: Instance)
	return serialize_instance(data)
end

function rose.deserialize(data: SerialFormat)
	return deserialize_instance(data, nil)
end

return rose
