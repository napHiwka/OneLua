-- Extracts lua-language-server annotations from source files
-- so they can be re-emitted at the top level of the bundle.
--
-- What extracted:
--  ---@class, ---@alias, ---@enum (type definitions)
--  ---@field, ---@type on lines immediately following the above
-- Not extracted: ---@param, ---@return, ---@local (too call-site-specific)

local Annotations = {}

local DEFINITION_TAGS = {
	["@class"] = true,
	["@alias"] = true,
	["@enum"] = true,
}

local QUALIFIER_TAGS = {
	["@field"] = true,
	["@operator"] = true,
}

-- Extract the annotation tag from a ---@... line
-- Returns e.g. "@class" or nil
local function tag_of(line)
	return line:match("^%s*%-%-%-%s*(@%a+)")
end

---Extract relevant annotation blocks from a single source string.
---Returns a list of raw annotation lines (stripped of leading whitespace).
---@param src string
---@return string[]
function Annotations.extract(src)
	local lines = {}
	local result = {}
	local in_def = false -- are we inside a definition block?

	for line in (src):gmatch("([^\n]*)\n") do
		lines[#lines + 1] = line
	end

	for _, line in ipairs(lines) do
		local tag = tag_of(line)
		if tag then
			local stripped = line:match("^%s*(.-)%s*$")
			if DEFINITION_TAGS[tag] then
				in_def = true
				result[#result + 1] = stripped
			elseif in_def and QUALIFIER_TAGS[tag] then
				result[#result + 1] = stripped
			else
				in_def = false
			end
		else
			in_def = false
		end
	end

	return result
end

---Given a list of {name, path, src} module entries, collect all unique
---annotation lines across all modules.
---@param modules table[] each has .src string
---@return string[] deduplicated ordered annotation lines
function Annotations.collect(modules)
	local seen = {}
	local result = {}

	for _, mod in ipairs(modules) do
		if mod.src then
			for _, line in ipairs(Annotations.extract(mod.src)) do
				if not seen[line] then
					seen[line] = true
					result[#result + 1] = line
				end
			end
		end
	end

	return result
end

---Try to find the primary @class name returned by a module's source.
---Looks for the last ---@class annotation before a bare 'return' statement.
---Returns nil when nothing confident can be inferred.
---@param src string
---@return string|nil
function Annotations.infer_return_class(src)
	local last_class = nil

	for line in src:gmatch("[^\n]+") do
		local cls = line:match("^%s*%-%-%-%s*@class%s+([%w_%.]+)")
		if cls then
			last_class = cls
		end
	end

	return last_class
end

return Annotations
