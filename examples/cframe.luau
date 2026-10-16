local bufferSerial = require("@BufferSerializer")
local vectorSerial = require("@BufferSerializer/vector")

local CFRAME = 5 -- assuming you want to have other userdata supported

--[[
	Note: The below example at any point in time may fail to
	 function due to external reliance.

	There are multiple approaches of varying accuracy depending on how cheap
	 CFrames must be.  The below approach is incredibly accurate, however for
	 perfect accuracy numbers must be used in place of CFrame:ToEulerAnglesXYZ.

	Should solely the position or solely the orientation be important, only
	 serialize those sections.  Should a section's accuracy not be as important,
	 the values can be pre-processed to ensure a cheaper result.
]]

local function cframeWriter(value: CFrame, serializer: (value: any) -> ())
	local typeV = typeof(value)
	if typeV == "CFrame" then
		-- Id
		serializer(CFRAME)

		serializer(value.Position)

		local x, y, z = value:ToEulerAnglesXYZ()

		serializer(vector.create(x, y, z))
	end
end

local function cframeReader(id: number?, posVector: vector?, eulerVector: vector?)
	if
		id == CFRAME
		and type(posVector) == "vector"
		and type(eulerVector) == "vector"
	then
		return CFrame.fromEulerAngles(eulerVector.x, eulerVector.y, eulerVector.z)
			+ posVector
	end
	return nil
end

bufferSerial.supportUserdata({
	serialize = cframeWriter,
	deserialize = cframeReader,
})

local data = CFrame.new()

local serData = bufferSerial.serialize(data)

-- ...

local _deserData = bufferSerial.deserialize(serData)
