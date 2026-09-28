--[[
	Compares the results for BufferSerializer
	- Recommended to pipe the results into a file (JSON format)

	To run:

	lune run tools/compare-results.luau v1.0.0 --versions=ALL > compare-results.json
]]

type BenchData = {
	sample_size: number, -- number of kept runs

	median: number,
	iqr: number, -- q3 - q1
	mad: number, -- median absolute deviation ( median(|x_i - median|) )
	mild_outliers: number, -- q1 - 1.5 * iqr and q3 + 1.5 * iqr

	min: number,
	average: number,
	max: number,
	stdev: number,
}
type BenchFormat = { time: BenchData, space: BenchData }

type Metadata<T> = { metadata: T }

type CategoryData = BenchFormat & Metadata<{ taxonomy: string }>
type SerialFormat = CategoryData & Metadata<{ size: number }>

type VersionData = {
	serialize: SerialFormat,
	deserialize: BenchFormat,
	size: {
		[string]: CategoryData & Metadata<{
			size: number,
			compression: {
				gzip: number,
				lz4: number,
			},
		}>,
	},
}

local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local options = {
	versions = {} :: { string },
	all_versions = false,
	disable_size = false,
	fileName = "benchmark-results.json",
}

function cli_assert(cond: any, message: string, is_help: boolean?): ()
	if not cond then
		print(message)
		if is_help then
			printHelp()
			print()
		end
		process.exit(0)
	end
end

function printHelp(): ()
	print([[
Usage: lune run tools/compare-results [options] <tag>

Compares the results for BufferSerializer
 - Recommended to pipe the results into a file (JSON format)

Argument:
  tag: The provided version to compare against

Available options:
  -h, --help: Display this usage message
  --versions=<tag[,tag]>: Compares provided version against the versions
    ALL can be used to get all versions.
  --file=<fileName>: The file containing the benchmark results
    Defaults to benchmark-results.json
  --disable-size: Whether to remove size comparison from the results
    Disregards the comparison work, it still occurs.
	]])
end

for _, input: string in process.args do
	if input == "-h" or input == "--help" then
		printHelp()
		process.exit(0)
	end
	if input:sub(1, 11) == "--versions=" then
		options.versions = input:sub(12):split(",")
		for _, version: string in options.versions do
			if version == "ALL" then
				options.all_versions = true
				table.clear(options.versions)
				break
			end
		end
		continue
	end
	if input:sub(1, 7) == "--file=" then
		options.fileName = input
		continue
	end
	if input:sub(1, 14) == "--disable-size" then
		options.disable_size = true
		continue
	end
	options.tag = input
end
cli_assert(options.tag, `tag must be set`, true)
cli_assert(fs.isFile(options.fileName), `results not found ({options.fileName})`)

local data: { [string]: VersionData }
do
	local success: boolean, temp_data =
		pcall(serde.decode, "json", fs.readFile(options.fileName))
	cli_assert(success, `improper json in {options.fileName}`)
	cli_assert(
		type(temp_data) == "table",
		`json table expected in {options.fileName}`
	)
	cli_assert(
		temp_data.BufferSerializer,
		`json table does not contain "BufferSerializer" key`
	)
	data = temp_data.BufferSerializer
end

local current_data: VersionData = data[options.tag]
cli_assert(
	current_data,
	`{options.tag} not found in BufferSerializer benchmark data`
)
data[options.tag] = nil

local compare_info = {
	serialize = {},
	deserialize = {},
	size = {},
}

local function percentage_change(first: number, second: number): number
	if second == 0 or not second then
		if first == 0 or not first then
			return 0
		end
		return -1 * percentage_change(second, first)
	end
	return 100 * (first - second) / second
end

local function process_results(msg: string, avg_perc: number): ()
	if avg_perc == 0 then
		--return ("Unchanged %s"):format(msg)
		return
	end
	local optim: string = if avg_perc > 0 then "Optimized" else "Regressed"

	return ("%s %s (%.2f%%)"):format(optim, msg, avg_perc)
end

local function populate_changes(
	result_categories: {
		time: number,
		space: number,
		size: number,
	},
	from: SerialFormat,
	against: SerialFormat
): ()
	result_categories.time =
		percentage_change(from.time.median, against.time.median)
	result_categories.space =
		percentage_change(from.space.average, against.space.average)

	if from.metadata and against.metadata then
		result_categories.size =
			percentage_change(from.metadata.size, against.metadata.size)
	end
end

local function size_compare(version: string, version_data: VersionData): ()
	compare_info.size[version] = {}

	for
		dataset: string,
		results: BenchFormat & Metadata<{ taxonomy: string }> & Metadata<{ compression: { gzip: number, lz4: number }, size: number }>
	in version_data.size do
		compare_info.size[version][dataset] = {
			uncompressed = results.metadata.size,
			gzip = results.metadata.compression.gzip,
			lz4 = results.metadata.compression.lz4,
		}
	end
end

-- current is N% better
local function version_compare(version: string, version_data: VersionData): ()
	local ser_results: {
		time: number,
		space: number,
		size: number,
	} = {}
	local ser_version_results: BenchFormat & Metadata<{ taxonomy: string }> & Metadata<{ size: number }> =
		version_data.serialize

	populate_changes(ser_results, ser_version_results, current_data.serialize)

	compare_info.serialize[version] = {
		time = process_results("time", ser_results.time),
		space = process_results("space", ser_results.space),
		size = process_results("size", ser_results.size),
	}

	local deser_results: {
		time: number,
		space: number,
	} = {}
	local deser_version_results: BenchFormat = version_data.deserialize

	populate_changes(
		deser_results,
		deser_version_results,
		current_data.deserialize
	)

	compare_info.deserialize[version] = {
		time = process_results("time", deser_results.time),
		space = process_results("space", deser_results.space),
	}

	-- now we need to do size stuff..
	size_compare(version, version_data)
end

size_compare(options.tag, current_data)

-- Attempt to compare each version to the current
if options.all_versions then
	for version: string, version_data: VersionData in data do
		version_compare(version, version_data)
	end
end

for _, version: string in options.versions do
	local version_data: VersionData = data[version]

	cli_assert(version_data, `Invalid version "{version}"`, true)

	version_compare(version, version_data)
end

if options.disable_size then
	compare_info.size = nil
end

-- !!!!PIPE IT INTO A FILE!!!!
print(serde.encode("json", compare_info, true))

return compare_info
