-- Default config file name searched
local DEFAULT_CONFIG = "bundler.config.lua"
local FALLBACK_CONFIG = "bundlerConfig.lua"

local CLI = {}

-- Concat in order to not compress the lines in help message
local HELP = table.concat({
	"OneLua - bundle a Lua project into a single file",
	"",
	"Usage:",
	"  lua bundler.lua [options]",
	"",
	"Options:",
	'  --entry   <module>   Entry module or file path      e.g. "main" or "src/main.lua"',
	'  --src     <dir>      Source directory               default: "./"',
	'  --out     <file>     Output bundle path             default: "./bundle.lua"',
	"  --name    <ident>    Exported variable name         default: entry basename",
	"  --config  <file>     Config file path               default: bundler.config.lua",
	"  --strip   <mode>     Strip comments from output",
	"                        all      remove all comments (keeps ---@module for LSP)",
	"                        non_ann  remove non-annotation comments (keeps ---@...)",
	"  --compact            Enable compact output",
	"  --resolve            Resolve possible dynamic dependencies",
	"  --debug              Verbose dependency-discovery logging",
	"  --verify             Load the bundle after writing to confirm it runs",
	"  --help               Show this help",
	"",
	"Config file (bundler.config.lua) is detected automatically when present in",
	"working directory. CLI flags override config-file values when both are present.",
	"",
	"Examples:",
	"  lua bundler.lua --entry main --src src/ --out dist/app.lua",
	"  lua bundler.lua --config my_project.config.lua --debug --verify",
	"  lua bundler.lua --config release.config.lua --strip all --out dist/lib.lua",
}, "\n")

local function parse_args(args)
	local flags = {}
	local i = 1

	while i <= #args do
		local a = args[i]

		if a == "--help" or a == "-h" then
			flags.help = true
		elseif a == "--debug" then
			flags.debug = true
		elseif a == "--verify" then
			flags.verify = true
		elseif a == "--resolve" then
			flags.resolve = true
		elseif a == "--compact" then
			flags.compact = true
		elseif a == "--entry" then
			i = i + 1
			flags.entry = args[i]
		elseif a == "--src" then
			i = i + 1
			flags.src = args[i]
		elseif a == "--out" then
			i = i + 1
			flags.out = args[i]
		elseif a == "--name" then
			i = i + 1
			flags.name = args[i]
		elseif a == "--strip" then
			i = i + 1
			local mode = args[i]
			if mode ~= "all" and mode ~= "non_ann" then
				return nil, "--strip must be 'all' or 'non_ann'"
			end
			flags.strip = mode
		elseif a == "--config" then
			i = i + 1
			flags.config_path = args[i]
		else
			return nil, "unknown option: " .. tostring(a)
		end

		i = i + 1
	end

	return flags
end

local function merge(base, overrides)
	local result = {}
	for k, v in pairs(base or {}) do
		result[k] = v
	end
	for k, v in pairs(overrides or {}) do
		if v ~= nil then
			result[k] = v
		end
	end
	return result
end

local function file_exists(path)
	local f = io.open(path, "r")
	if f then
		f:close()
		return true
	end
	return false
end

local function load_config(path)
	local chunk, err = loadfile(path)
	if not chunk then
		error("config error in '" .. path .. "':\n  " .. (err or "unknown"), 0)
	end
	local cfg = chunk()
	if type(cfg) ~= "table" then
		error("config file '" .. path .. "' must return a table", 0)
	end
	return cfg
end

local function detect_config_path(preferred)
	if preferred then
		if not file_exists(preferred) then
			error("config file not found: " .. preferred, 0)
		end
		return preferred
	end

	local candidates = { DEFAULT_CONFIG, FALLBACK_CONFIG }
	for _, path in ipairs(candidates) do
		if file_exists(path) then
			return path
		end
	end
end

---@param args string[]
---@return table|nil
function CLI.parse(args)
	local flags, parse_msg = parse_args(args)
	if not flags then
		error(parse_msg .. "\n  run with --help for usage", 0)
	end

	if flags.help then
		print(HELP)
		return nil
	end

	local config_path = detect_config_path(flags.config_path)

	local file_cfg = {}
	if config_path then
		file_cfg = load_config(config_path)
		print("[bundler] using config: " .. config_path)
	end

	local cfg = merge(file_cfg, {
		entry = flags.entry,
		src = flags.src,
		out = flags.out,
		name = flags.name,
		strip = flags.strip,
		compact = flags.compact,
		debug = flags.debug,
		verify = flags.verify,
		resolve = flags.resolve,
	})

	-- Apply defaults
	cfg.src = cfg.src or "./"
	cfg.out = cfg.out or "./bundle.lua"
	cfg.compact = cfg.compact or false
	cfg.debug = cfg.debug or false
	cfg.verify = cfg.verify or false
	cfg.resolve = cfg.resolve or false

	if #args == 0 and not config_path then
		print(HELP)
		return nil
	end

	return cfg
end

return CLI
