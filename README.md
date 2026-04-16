# OneLua

OneLua bundles a Lua project into a single distributable `.lua` file.

## Features

- Follows local static `require()` dependencies automatically
  - For dynamic require() calls, use `extra` and `aliases` in config
- Optionally, can resolve dynamic `require()` statements from `utils = require(VAR .. "utils")` -> `utils = require("utils")`. If you include an extra file `utils` -> working code without manual editing.
- Hoists annotations to the top of the bundle for better language server support
- Optionally verifies the generated bundle by loading it after writing
- Produces compact code (not minified)
- Strips comments from the bundled output
- Supports aliases and extra files
- Compatible with Lua 5.1+

> A static require is when the module path is a constant string known at analysis time.
> A dynamic require is when the module path is computed at runtime, preventing static analysis tools from resolving it.

## CLI

```sh
lua bundler.lua --entry source/main.lua --src ./ --out dist/bundle.lua
```

- `--entry <module>` entry module or file path
- `--src <dir>` source directory (default `./`)
- `--out <file>` output file (default `./bundle.lua`)
- `--name <id>` name of the exported variable
- `--config <file>` path to the config file
- `--strip all|non_ann` strip comments from the output
- `--debug` print dependency resolution logs
- `--verify` require the generated bundle after writing to verify it
- `--help` show help

## Optional Config

The bundler automatically detects this file if it is present in the working directory with name `bundler.config.lua` or `bundlerConfig.lua`.

```lua
return {
	entry = "main.lua",
	src = "src/",
	out = "dist/bundle.lua",
	name = "MyLib",
	extra = {
		"plugins.backend",
	},
	skip_extra_files_requires = false,
	aliases = {
		["json"] = "vendor.json",
	},
	strip = "non_ann",
	resolve = false,
	compact = true,
	debug = true,
	verify = true,
}
```
