-- Extracts lua-language-server annotations from source files
-- so they can be re-emitted at the top level of the bundle.

local Annotations = {}

-- LuaLS annotation tags
local DEFINITION_TAGS = {
	["@class"] = true,
	["@alias"] = true,
	["@enum"] = true,
}

-- Tags that qualify an open definition
local QUALIFIER_TAGS = {
	["@field"] = true,
	["@operator"] = true,
}

-- Extract the annotation tag from a ---@... line
local function tag_of(line)
	return line:match("^%s*%-%-%-%s*(@%a+)")
end

--- Extract annotation lines from a single source string.
function Annotations.extract(src)
	local result = {}
	local in_def = false

	for line in (src .. "\n"):gmatch("([^\n]*)\n") do
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

--- Collect deduplicated annotation lines across all modules.
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

--- Return the last @class name declared in src, or nil.
function Annotations.infer_return_class(src)
	local last_class
	for line in src:gmatch("[^\n]+") do
		local cls = line:match("^%s*%-%-%-%s*@class%s+([%w_%.]+)")
		if cls then
			last_class = cls
		end
	end
	return last_class
end

return Annotations
