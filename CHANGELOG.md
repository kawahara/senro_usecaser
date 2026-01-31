# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-01-31

### Added

- **Runtime type validation for input**
  - `input` now accepts Module(s) for interface-based validation
  - Single module: `input HasUserId` - validates that input's class includes the module
  - Multiple modules: `input HasUserId, HasEmail` - validates that input's class includes all modules
  - Class validation remains supported for backwards compatibility
- **Runtime type validation for output**
  - When `output` is declared with a Class, the success result's value is validated
  - Raises `TypeError` if the output value is not an instance of the declared class
  - Hash schema (`output({ key: Type })`) skips validation for backwards compatibility
- **New class methods**
  - `input_types` - Returns an array of declared input types (Module/Class)
  - `input_class` - Backwards compatible method, returns Class if specified or first type

### Changed

- Type validation errors raise exceptions with `.call` and return `Result.failure` with `.call!`
  - Input validation: `ArgumentError`
  - Output validation: `TypeError`

## [0.2.0] - 2026-01-31

### Added

- **Hook class with dependency injection** - New `SenroUsecaser::Hook` base class for creating hooks with `depends_on` support
  - Supports `namespace` declaration for scoped dependency resolution
  - Supports `infer_namespace_from_module` configuration
  - Can inherit namespace from the UseCase when not explicitly declared
- **Block hooks can access dependencies**
  - `before` and `after` blocks now run in instance context via `instance_exec`
  - Dependencies declared with `depends_on` are directly accessible in block hooks

### Changed

- **Around block signature** - Changed from `|input, &block|` to `|input, use_case, &block|`
  - The `use_case` argument provides access to dependencies
- **Input class is now mandatory** - All UseCases must define an `input` class
- **Renamed `context` to `input`** - Hook parameters renamed for clarity

## [0.1.0] - 2026-01-30

- Initial release
