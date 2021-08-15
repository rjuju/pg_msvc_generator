pg_msvc_generator
=================

MSVC project generator for PostgreSQL extensions.

Usage
-----

Basic tool usage is:

```
pg_msvc_generator.pl [ options ]

Options:

    --default version pgver  : default PostgreSQL version. This is only used
                if you compile the project zithout specifying a specific ;ajor
                version, or when the project is opened with Visual Studio
                IDE.  If not provided, a default value based on the year will
                be choosen (13 for 2021, 14 for 2022 and so on).
    -d | --dir ext_directory : root directory of the extension source code.
    -e | --extension         : extension name.  If not provided, the extension
                name will be assumed using the last part of the given root
                directory.
    -h | --help              : Show this message.
```

It will generate an `msvc` subdirectory in the given extension directory,
containing the required `.sln` and `.vcxproj` files to be able to compile the
extension using Visual Studio 2019, with support for Debug/Release and 32/64
bits builds.

Example:

```
pg_msvc_generator,pl -d C:\git\hypopg
```

Requirements
------------

**At project generation time**:

  - A Windows host to generate the project files

**At extension compilation time**:

  - Visual Studio 2019
  - All major PostgreSQL versions for which you want to build the extension,
    installed from PGDG packages in the default location
    (`C:\Program Files\PostgreSQL\$MAJOR_VERSION`)

Compiling the extension
-----------------------

The Visual Studio project contains a `pgver` parameter that can be used to
compile the extension for a specific major version.

Example:

```
msbuild C:\git\hypopg\msvc\hypopg.sln /p:Configuration=Release /p:Platform=x64 /p:pgver=12
```

If the project compiles correctly, the DLL will be generated in the
`msvc\$Platform\$configuration\` subdirectory.  In the previous example, it
would be `msvc\x64\Release\hypopg.dll`.
