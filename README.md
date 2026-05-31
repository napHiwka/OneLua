# OneLua

OneLua bundles a Lua project into a single distributable `.lua` file. It can be used as a CLI tool or embedded as a library. Mostly source code requires no manual changes to be bundled.

## Features

- Follows `require()` dependencies automatically, depth-first.
- Hoists `---@` annotations to the top of the bundle for language server support.
- Aliases let you remap module names at runtime (useful for dynamic requires).
- Optionally rewrites simple dynamic `require()` calls to static ones.
- Optionally strips comments and produces compact output.
- Optionally verifies the bundle by loading it immediately after writing.
- Compatible with Lua 5.1 - 5.5, LuaJIT.

## CLI

```sh
lua bundler.lua --entry source/main.lua --src ./ --out dist/bundle.lua
```

Only `--entry` is required; everything else is optional.

`--entry <module>` entry module name or file path
`--src <dir>` source root (default: `./`)
`--out <file>` output path (default: `./bundle.lua`)
`--name <id>` exported variable name (default: entry basename)
`--config <file>` config file path
`--strip <mode>` strip comments (`all` or `non_ann` modes)
`--compact` collapse blank lines in output
`--resolve` rewrite resolvable dynamic requires
`--debug` print verbose dependency resolution logs
`--verify` load the bundle after writing to confirm it runs
`--help` show help

## Config File

The bundler auto-detects `bundler.config.lua` or `bundlerConfig.lua` in the working directory. CLI flags override config values. A configuration file with detailed comments is available [here](bundler.config.lua). There is also a [bare](bare.config.lua) conf file to make it easier to customize if you are already familiar with the structure.

## Concepts

### Static vs dynamic requires

A *static require* has a string literal argument known at analysis time:

```lua
local json = require("vendor.json")
```

A *dynamic require* is computed at runtime and cannot be resolved statically:

```lua
local mod = require(prefix .. "utils")
```

Dynamic requires will produce a `WARN:` line during bundling. To handle them, use `extra` to force-include the module and `aliases` to remap the name (see below), or use `--resolve` if the pattern is simple enough to rewrite automatically.

### Resolve

When enabled, the bundler rewrites simple dynamic require patterns to static ones before emitting. It handles two forms:

```lua
-- Before
local mod = require(prefix .. "utils")
local mod = require("mylib." .. name)

-- After (example, depending on what the bundler can infer)
local mod = require("utils")
local mod = require("mylib.name")
```

Only patterns where the dynamic part is a single identifier concatenated with a string literal are rewritten. Everything else still produces a `WARN:` and requires manual aliases.

### Extra

Lists module names to include unconditionally, even if they are not reachable from the entry module via static requires. Useful for modules that are only loaded dynamically. By default, requires found inside extra files are followed normally. Set `skip_extra_files_requires = true` to include the extra file itself but not its dependencies.

### Aliases

Aliases remap a module name inside the bundle at runtime. The bundle's `require()` wrapper consults the alias table before looking up a loader, so `require("old.name")` transparently resolves to whatever `"new.name"` was bundled as.

```lua
aliases = {
    ["json"] = "vendor.json", -- require("json") -> vendor.json
    [".namespace"] = "src.namespace", -- require(".namespace") -> src.namespace
    ["namespace"] = "src.namespace", -- require("namespace") -> src.namespace
}
```

The primary use case is dynamic requires: if a module calls `require(base .. "utils")`, the runtime will produce a string like `"utils"` or `".utils"` depending on `base`. Adding aliases for both spellings pointing to the bundled module name (`"src.utils"`) means the call resolves correctly without modifying the source.
