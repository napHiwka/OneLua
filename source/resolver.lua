local Resolver = {}

local function ensure_dir(path)
	local dir = path:match("^(.*)[/\\][^/\\]+$")
	if not dir or dir == "" then
		return
	end
	local sep = package.config:sub(1, 1)
	if sep == "\\" then
		os.execute('mkdir "' .. dir:gsub("/", "\\") .. '" 2>nul')
	else
		os.execute('mkdir -p "' .. dir .. '"')
	end
end

local function normalize_dir(dir)
	if dir == "" then
		return "./"
	end
	return dir:match("[/\\]$") and dir or dir .. "/"
end

local function name_to_path(name)
	return name:gsub("%.", "/")
end

local function normalize_slashes(path)
	return (path:gsub("\\", "/"))
end

local function trim_lua_extension(name)
	return (name:gsub("%.lua$", ""))
end

local function trim_leading_current_dir(path)
	return (path:gsub("^%./", ""))
end

local function starts_with(text, prefix)
	return text:sub(1, #prefix) == prefix
end

local function path_to_module_name(path)
	path = normalize_slashes(path)
	path = trim_leading_current_dir(path)
	path = trim_lua_extension(path)
	path = path:gsub("/init$", "")
	path = path:gsub("^/", "")
	return (path:gsub("/", "."))
end

local function try_open(path)
	local f = io.open(path, "r")
	if f then
		f:close()
		return path
	end
end

---Resolve a module name to an absolute (or relative) file path.
---@param name string dotted module name, e.g. "database.config"
---@param src string base directory to search in
---@return string|nil file path or nil if not found locally
function Resolver.resolve(name, src)
	local base = normalize_dir(src) .. name_to_path(name)
	return try_open(base .. ".lua") or try_open(base .. "/init.lua")
end

---Normalize a module spec passed by user input or config.
---Accepts module names, bare file names, and relative file paths.
---@param spec string
---@param src string
---@return string
function Resolver.normalize_module_name(spec, src)
	local normalized = normalize_slashes(spec)
	local src_prefix = trim_leading_current_dir(normalize_slashes(normalize_dir(src)))

	normalized = trim_leading_current_dir(normalized)
	normalized = trim_lua_extension(normalized)

	if src_prefix ~= "" and starts_with(normalized, src_prefix) then
		normalized = normalized:sub(#src_prefix + 1)
	end

	if normalized:match("[/\\]") then
		normalized = path_to_module_name(normalized)
	end

	return normalized
end

---Read a file's contents, normalising line endings
---Raises an error if the file cannot be opened
---@param path string
---@return string
function Resolver.read(path)
	local f, err = io.open(path, "r")
	if not f then
		error("cannot open: " .. path .. (err and ("\n  " .. err) or ""), 2)
	end
	local src = f:read("*a")
	f:close()
	return (src:gsub("\r\n", "\n"):gsub("\r", "\n"))
end

---Write content to a file; raises on failure
---@param path string
---@param content string
function Resolver.write(path, content)
	ensure_dir(path)
	local f, err = io.open(path, "w")
	if not f then
		error("cannot write: " .. path .. (err and ("\n  " .. err) or ""), 2)
	end
	f:write(content)
	f:close()
end

return Resolver
