--!optimize 2
--!strict

local link = {}

type TYPES = "userdata" | "number" | "string" | "vector"
type SERIALIZABLE_TYPES = TYPES | "boolean" | "buffer" | "nil" | "table"

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

return table.freeze(link)
