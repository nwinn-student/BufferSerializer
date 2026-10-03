--!strict
-- Runs tests for ../src/link

local link = require("../src/link")
local test = require("./test")

-- Validate type
test.compare("boolean", link.type(1))
test.compare("boolean", link.type(2))
test.compare("buffer", link.type(3))
test.compare("buffer", link.type(7))
test.compare("string", link.type(8))
test.compare("string", link.type(96))
test.compare("number", link.type(97))
test.compare("number", link.type(141))
test.compare("vector", link.type(142))
test.compare("vector", link.type(193))
test.compare("table", link.type(194))
test.compare("table", link.type(201))
test.compare("userdata", link.type(202))
test.compare("userdata", link.type(215))

return {}
