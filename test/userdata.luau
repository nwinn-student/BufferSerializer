--!strict
-- Runs tests for ../src/userdata

local test = require("./test")
local userdata = require("../src/userdata")
local isSupported = require("../src").isSupported

local CUSTOM = 202
local UNSUPPORTED = 203

local proxy = newproxy()
local zero_proxy = newproxy()

-- Check that userdata.luau works properly
test.compare(false, isSupported(proxy))

local function reader(...: any)
	local args = { ... }
	local id = args[1]
	if id == 0 then
		return zero_proxy
	end
	return nil
end

local function writer(value: any, serializer: (value: any) -> ())
	if value ~= zero_proxy then
		return
	end
	serializer(0)
end
userdata.addSupport({
	serialize = writer,
	deserialize = reader,
})

local obtainedBuffer, obtainedValue = test.inspect(proxy, {
	disableValueComparison = true,
})
test.compare(test.newBuffer(UNSUPPORTED), obtainedBuffer)
test.compare(false, isSupported(obtainedValue))

test.compare(test.newBuffer(CUSTOM, 97, 200), test.inspect(zero_proxy))
test.compare(true, isSupported(zero_proxy))

return {}
