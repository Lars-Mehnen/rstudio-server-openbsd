# RStudio Server on OpenBSD

Experimental port of current upstream RStudio Server to OpenBSD.

Tested with:

- OpenBSD 8.0-current/snapshot
- amd64
- R 4.6.1
- RStudio 2026.10.999-dev+999 "Blue Mistflower"

## Status

Working:

- `rserver`
- `rsession`
- Web UI
- R console
- R 4.6.1 integration

Known warning:

- `r-ldpath` is currently missing from the build-tree runtime layout.

## Restore source tree

Either clone from the bundle:

```sh
git clone rstudio-openbsd.bundle rstudio
cd rstudio
git switch openbsd-rstudio-2026.10
```

or apply the OpenBSD patch to the matching upstream revision.

## Build order

1. Install OpenBSD dependencies.
2. Configure login limits.
3. Build and install SOCI 4.0.3.
4. Prepare Pandoc, MathJax, dictionaries, and GWT.
5. Prepare OpenBSD-native esbuild binaries.
6. Build RStudio with `build-rstudio.sh`.
7. Run `setup-runtime.sh`.
8. Start `rserver`.

## Build configuration

The working CMake configuration was:

```sh
cmake .. -G Ninja \
  -DRSTUDIO_TARGET=Server \
  -DCMAKE_BUILD_TYPE=Release \
  -DRSTUDIO_USE_SYSTEM_BOOST=1 \
  -DRSTUDIO_UNIT_TESTS_DISABLED=ON \
  -DQUARTO_ENABLED=FALSE \
  -DRSTUDIO_ENABLE_COPILOT=FALSE \
  -DDL_LIB="" \
  -DDL_LIBRARIES="" \
  -DRT_LIBRARIES="" \
  -DCMAKE_CXX_FLAGS="-I/usr/local/include/postgresql" \
  -DSOCI_CORE_LIB=/usr/local/lib/libsoci_core.a \
  -DSOCI_SQLITE_LIB=/usr/local/lib/libsoci_sqlite3.a \
  -DSOCI_POSTGRESQL_LIB=/usr/local/lib/libsoci_postgresql.a
```

Java environment:

```sh
export JAVA_HOME=/usr/local/jdk-17
export PATH="$JAVA_HOME/bin:$PATH"
```

## Runtime setup used during testing

The following build-tree links were required for the current test setup:

```text
build/src/cpp/db -> server/db
build/src/cpp/R -> ../../../src/cpp/r/R
build/src/cpp/resources -> ../../../src/cpp/session/resources
src/cpp/r/R/modules -> ../../../../build/src/cpp/session/modules/R
```

RStudio also expected an unversioned R shared-library name:

```text
/usr/local/lib/R/lib/libR.so -> /usr/local/lib/R/lib/libR.so.42.0
```

Example:

```sh
doas ln -s /usr/local/lib/R/lib/libR.so.42.0 \
  /usr/local/lib/R/lib/libR.so
```

For the temporary non-root test setup, `/var/lib/rstudio-server` was created and made writable by the test user. For a real installation, use a dedicated `rstudio-server` account and appropriate ownership.

## Test start

The helper scripts assume this workspace layout by default:

```text
workspace/
??? rstudio-server-openbsd/
??? rstudio/
??? esbuild-native/
```

All paths can be overridden with environment variables such as
`WORKSPACE`, `RSTUDIO_SRC`, and `ESBUILD_NATIVE_DIR`.

After running `setup-runtime.sh`, start the development server with:

```sh
cd rstudio-server-openbsd
./start-rstudio.sh
```

By default the server listens on:

```text
http://127.0.0.1:8787
```

If the RStudio source checkout is elsewhere:

```sh
RSTUDIO_SRC=/path/to/rstudio ./start-rstudio.sh
```

## Confirmed working R session

The tested R session reported:

```text
R version 4.6.1 (2026-06-24) -- "Happy Hop"
Platform: x86_64-unknown-openbsd8.0
```

## External dependencies used

Key components used during the successful build included:

- Boost 1.91
- PostgreSQL / libpq
- SQLite3
- libinotify
- libexecinfo
- SOCI 4.0.3, built from source
- Java 17
- Node.js 24
- npm / Corepack / Yarn 1.22
- Pandoc
- MathJax
- Dictionaries
- GWT 2.12.2
- OpenBSD-native esbuild binaries:
  - 0.15.18
  - 0.16.17
  - 0.17.19
  - 0.25.6

## OpenBSD resource limits

The build required increased process memory and file-descriptor limits. The working `staff` login class used approximately:

```text
:datasize-cur=6G:
:datasize-max=infinity:
:maxproc-max=512:
:maxproc-cur=256:
:openfiles-cur=4096:
:openfiles-max=8192:
```

After modifying `/etc/login.conf`:

```sh
doas cap_mkdb /etc/login.conf
```

Log out and back in before building.

## Upgrading R

After `pkg_add -u R` the versioned `libR.so` ABI number changes and `rsession` must be
relinked. Clear the CMake cache and rebuild the session target:

```sh
rm rstudio/build/CMakeCache.txt
cd rstudio-server-openbsd
./build-rstudio.sh
```

The fmt vendored-library fix (`<stdlib.h>` include) is now automated in the cmake build
and no longer requires manual intervention after a rebuild.

## Source backup

The working source state was saved as:

```text
rstudio-openbsd.bundle
rstudio-openbsd.patch
rstudio-openbsd-working.patch
```

The bundle can be used to recreate the exact Git branch. The patch is useful for reviewing or porting the OpenBSD changes to later upstream RStudio versions.

## Notes

This is currently a working development-port setup rather than a polished OpenBSD package.

Before packaging or upstream submission, the following should be cleaned up:

- replace build-tree runtime symlinks with proper install rules;
- install `r-ldpath` into the expected runtime layout;
- use a dedicated `rstudio-server` service account;
- review OpenBSD process and resource handling;
- make dependency setup reproducible;
- revisit disabled unit tests;
- convert the working changes into a clean OpenBSD ports-style patch set.
