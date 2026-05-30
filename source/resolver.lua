-- Resolves different file paths

local Resolver = {}
local IS_WINDOWS = package.config:sub(1, 1) == "\\"

local function ensure_dir(path)
	local dir = path:match("^(.*)[/\\][^/\\]+$")
	if not dir or dir == "" then
		return
	end
	if IS_WINDOWS then
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

local function normalize_slashes(path)
	return (path:gsub("\\", "/"))
end

local function trim_lua_extension(path)
	return (path:gsub("%.lua$", ""))
end

local function trim_leading_dot_slash(path)
	return (path:gsub("^%./", ""))
end

local function starts_with(text, prefix)
	return text:sub(1, #prefix) == prefix
end

-- "some/path/to/mod" -> "some.path.to.mod"
local function path_to_module_name(path)
	path = normalize_slashes(path)
	path = trim_leading_dot_slash(path)
	path = trim_lua_extension(path)
	path = path:gsub("/init$", "")
	path = path:gsub("^/", "")
	return (path:gsub("/", "."))
end

-- "mod.sub.name" -> "mod/sub/name"
local function module_to_path(name)
	return name:gsub("%.", "/")
end

local function try_open(path)
	local f = io.open(path, "r")
	if f then
		f:close()
		return path
	end
end

--- Find the filesystem path for a module name, searching under src_dir.
--- Tries <src>/<name-as-path>.lua and <src>/<name-as-path>/init.lua.
function Resolver.resolve(name, src_dir)
	local base = normalize_dir(src_dir) .. module_to_path(name)
	return try_open(base .. ".lua") or try_open(base .. "/init.lua")
end

--- Normalise an arbitrary specifier (relative path, dot-name, etc.) to a
--- canonical module name relative to src_dir.
function Resolver.normalize_module_name(spec, src_dir)
	local norm = normalize_slashes(spec)
	local src_prefix = trim_leading_dot_slash(normalize_slashes(normalize_dir(src_dir)))
	norm = trim_leading_dot_slash(norm)
	norm = trim_lua_extension(norm)

	if src_prefix ~= "" and starts_with(norm, src_prefix) then
		norm = norm:sub(#src_prefix + 1)
	end

	if norm:match("[/\\]") then
		norm = path_to_module_name(norm)
	end
	return norm
end

--- Read a file, normalising line endings to "\n".
function Resolver.read(path)
	local f, err = io.open(path, "r")
	if not f then
		error("cannot open: " .. path .. (err and ("\n  " .. err) or ""), 2)
	end
	local src = f:read("*a")
	f:close()
	return (src:gsub("\r\n", "\n"):gsub("\r", "\n"))
end

--- Write content to path, creating intermediate directories if needed.
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
