# libpq-cmake

A CMake port of [libpq](https://www.postgresql.org/docs/current/libpq.html) (the official C client library for PostgreSQL).

## Usage

The library is intended to be used as a Git submodule.

```sh
git submodule add https://github.com/nitrix/libpq-cmake vendor/libpq
``` 

```cmake
add_subdirectory(vendor/libpq)
target_add_library(foo libpq::libpq)
```

`libpq::libpq` resolves to the shared variant when `LIBPQ_BUILD_SHARED=ON`,
otherwise to the static one. The static and shared targets are also exposed
explicitly as `libpq::libpq_static` and `libpq::libpq_shared`.

## Testing

```bash
cmake --build build
PG_CONNINFO="host=localhost port=5432 user=postgres password=postgres dbname=postgres" ctest --test-dir build --output-on-failure
```

## CMake options

| Option               | Default | Description                                           |
|----------------------|---------|-------------------------------------------------------|
| `LIBPQ_WITH_OPENSSL` | `ON`    | Build TLS support (`USE_OPENSSL=1`, requires OpenSSL) |
| `LIBPQ_BUILD_SHARED` | `OFF`   | Build shared libpq alongside the static one           |
| `LIBPQ_BUILD_TESTS`  | `OFF`   | Build the `connect_test` smoke test                   |
| `LIBPQ_INSTALL`      | `ON`    | Generate install / `find_package` export rules        |

## Needed for SSL

| Platform              | Compiler         | Postgres source on host                    | OpenSSL  |
|-----------------------|------------------|--------------------------------------------|----------|
| Linux                 | gcc / clang ≥ 12 | apt `libssl-dev`                           | system   |
| macOS                 | Apple clang      | `brew install openssl@3`                   | Homebrew |
| Windows MSVC          | MSVC 2022        | vcpkg `openssl:x64-windows`                | vcpkg    |
| Windows MSYS2 CLANG64 | clang 18+        | `pacman -S mingw-w64-clang-x86_64-openssl` | MSYS2    |
| Windows Cygwin        | gcc              | `libssl-devel` (Cygwin)                    | Cygwin   |

## Credits

Entirely goes to the [postgres](https://github.com/postgres/postgres) project.  

I made this repository for convenience only.

## License

Except for the work done by the postgres authors which has [its own license](https://github.com/postgres/postgres/blob/master/COPYRIGHT),
you may use this repository however you like.

See [UNLICENSE](UNLICENSE) for more information.