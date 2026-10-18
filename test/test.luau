--!strict
--!optimize 2

--[[
	Test API

	newBuffer(...: number | string): buffer
	sizedBuffer(size: number, ...: number | string): buffer
	run(cond: boolean, message: string)
	-- We can use type system to do precursor check
	compare<T>(expected: T, obtained: T): boolean

	-- Looks at the (de)serialization of `value` to ensure correctness
	-- Returns the deserialized buffer.
	-- TODO: Consider adding an options parameter that allows
	--  for the disabling of deserialization comparison and possibly
	--  other aspects.
	test.inspect<T>(value: T, options: InspectOptions?): (buffer, T)
]]

export type InspectOptions = {
	disableValueComparison: boolean?,
}

local test = {}

local function getSize(tab: { number | string })
	local size = 0
	for _, value in tab do
		if type(value) == "string" then
			size += #value
			continue
		end
		assert(type(value) == "number")
		size += 1
	end
	return size
end

local function tosimplestring(value: any)
	local typeValue = type(value)
	return if typeValue == "string"
		then `"{value}"`
		elseif typeValue == "buffer" then `b"{buffer.tostring(value)}"`
		else tostring(value)
end

local function stringCompare(expected: string, obtained: string)
	local hasFailed = false
	local traceback = debug.traceback("", 3)

	local expectedSize = #expected
	local obtaintedSize = #obtained

	if expectedSize ~= obtaintedSize then
		print(`Expected size {expectedSize} (got {obtaintedSize})`)
		hasFailed = true
	end

	for i = 0, math.min(expectedSize, obtaintedSize) do
		local expectedChar = expected:sub(i, i)
		local expectedByte = expectedChar:byte()
		local obtainedChar = obtained:sub(i, i)
		local obtainedByte = obtainedChar:byte()

		if expectedByte ~= obtainedByte then
			print(
				`Expected {expectedChar} ({expectedByte}) at position {i} (got {obtainedChar} ({obtainedByte}))`
			)
			hasFailed = true
		end
	end

	if hasFailed then
		print(traceback:sub(2, -1))
	end
	return hasFailed
end

local function tableCompare(expected: { [any]: any }, obtained: { [any]: any })
	local cyclicStorage = { [expected] = true, [obtained] = expected }
	local hasFailed = false
	local traceback = debug.traceback("", 3)

	local function comparer(expected: { [any]: any }, obtained: { [any]: any })
		local keyStorage = {}

		for key, value in expected do
			keyStorage[key] = true

			local obtainedValueAtKey = obtained[key]
			if obtainedValueAtKey == nil then
				print(
					`Expected [{tosimplestring(key)}] = {tosimplestring(value)} (got nil)`
				)
				hasFailed = true
				continue
			end

			if cyclicStorage[value] then
				if cyclicStorage[obtainedValueAtKey] ~= value then
					print(
						`Expected [{tosimplestring(key)}] = *CYCLIC* (got {tosimplestring(
							value
						)})`
					)
					hasFailed = true
				end
				continue
			end

			-- When making tests, do NOT have tables as keys, we don't have a
			--  correct way to determine which table key is linked with which.
			if type(key) == "table" then
				continue
			end
			if type(value) == "table" and type(obtainedValueAtKey) == "table" then
				cyclicStorage[value] = true
				cyclicStorage[obtainedValueAtKey] = value
				comparer(value, obtainedValueAtKey)
				continue
			end

			if not test.compare(value, obtainedValueAtKey) then
				hasFailed = true
			end
		end

		for key, value in obtained do
			if not keyStorage[key] then
				print(
					`Expected [{tosimplestring(key)}] = nil (got {tosimplestring(
						value
					)})`
				)
				hasFailed = true
			end
		end
	end

	comparer(expected, obtained)

	if hasFailed then
		print(traceback:sub(2, -1))
	end
	return hasFailed
end

function test.run(cond: boolean, message: string)
	if cond then
		return
	end
	print(`{message} {debug.traceback("", 2)}`)
end

function test.sizedBuffer(size: number, ...: number | string)
	local args = { ... }
	local buf = buffer.create(size)
	local pos = 0
	for _, value in args do
		if type(value) == "string" then
			buffer.writestring(buf, pos, value)
			pos += #value
			continue
		end
		assert(type(value) == "number")
		buffer.writeu8(buf, pos, value)
		pos += 1
	end
	return buf
end

function test.newBuffer(...: number | string)
	local size = getSize({ ... })
	return test.sizedBuffer(size, ...)
end

function test.compare<T>(expected: T, obtained: T)
	if
		expected == obtained
		or tosimplestring(expected) == tosimplestring(obtained)
	then
		return true
	end

	local traceback = debug.traceback("", 2)

	local expectedType = type(expected)
	local obtainedType = type(obtained)
	if expectedType ~= obtainedType then
		print(`Expected type {expectedType} (got {obtainedType}) {traceback}`)
		return false
	end

	if expectedType == "string" then
		-- match obtained against expected?
		return stringCompare(expected, obtained)
	elseif expectedType == "buffer" then
		return stringCompare(buffer.tostring(expected), buffer.tostring(obtained))
	elseif expectedType == "table" then
		return tableCompare(expected, obtained)
	else
		print(`Expected {expected} (got {obtained}) {traceback}`)
		return false
	end
end

local mainSerial = require("@BufferSerializer").serialize
-- Checks serial and deserial, returns the buffer
function test.inspect<T>(value: T, options: InspectOptions?): (buffer, T)
	local traceback = debug.traceback("", 2)
	local hasFailed = false
	local disableValueComparison = if options
			and options.disableValueComparison
		then true
		else false

	local serial = (require(`@BufferSerializer/{type(value)}`) :: any).serialize
	local deserial = (require(`@BufferSerializer/{type(value)}`) :: any).deserialize

	local mainBuffer = mainSerial(value)
	local size = buffer.len(mainBuffer)

	local expectedPos = size + 1
	local expectedSize = 2 ^ (32 - bit32.countlz(size + 2))

	local wrappedBuffer = test.sizedBuffer(expectedSize, 100)
	buffer.writeu8(wrappedBuffer, expectedPos, 200)

	local obtainedBuffer, obtainedPos = serial(value, wrappedBuffer, 1)
	local obtainedSize = buffer.len(obtainedBuffer)

	-- We must ensure byte 1 is 100 and final byte is 200
	if buffer.readu8(obtainedBuffer, 0) ~= 100 then
		print(`Expected 100 at pos 0 (got {buffer.readu8(obtainedBuffer, 0)})`)
		hasFailed = true
	end
	if buffer.readu8(obtainedBuffer, expectedPos) ~= 200 then
		print(
			`Expected 200 at pos {expectedPos} (got {buffer.readu8(
				obtainedBuffer,
				expectedPos
			)})`
		)
		hasFailed = true
	end
	if expectedPos ~= obtainedPos then
		print(`Expected position {expectedPos} (got {obtainedPos})`)
		hasFailed = true
	end
	if expectedSize ~= obtainedSize then
		print(`Expected size {expectedSize} (got {obtainedSize})`)
		hasFailed = true
	end

	-- if it has failed do we just nogo?
	local obtainedValue, obtainedDPos =
		deserial(obtainedBuffer, 1, buffer.readu8(obtainedBuffer, 1))
	if not disableValueComparison then
		test.compare(value, obtainedValue) -- already prints stuff
	end
	if expectedPos ~= obtainedDPos then
		print(
			`Expected deserialization position {expectedPos} (got {obtainedDPos})`
		)
		hasFailed = true
	end

	if hasFailed then
		print(traceback:sub(2, -1))
	end

	local unwrappedBuffer = test.sizedBuffer(size)
	buffer.copy(unwrappedBuffer, 0, obtainedBuffer, 1, size)
	return unwrappedBuffer, obtainedValue
end

return test
