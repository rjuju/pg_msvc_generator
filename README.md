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
bits builds.  It will alse create a `release.pl` and a `build.bat` scripts that
can automatically compile and create release archive files for all installed
PostgreSQL versions.

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

Doing a release of your extension
---------------------------------

All you need to do is to execute the `msvc\release.bat` script.  It will setup
the MSVC environment and call the `release.pl` script.  That script will
prepare everything for a release under a
`msvc\${extension_name}-${extension_version}` directory.

It will automatically find the installed PostgreSQL version reading the
`HKLM/SOFTWARE/PostgreSQL/Installations/` registry, compile the extension with
all those versions and for each will generate a subdirectory containing the dll
and the SQL scripts if any, and a zip archive with the same content.

For instance, assuming that you have PostgreSQL 12 and 13 installed and
released HypoPG 1.3.2, your `msvc` directory will now have this additional
content:

```
msvc\hypopg-1.3.2\12-x64\lib\hypopg.dll
msvc\hypopg-1.3.2\12-x64\share\extension\hypopg.control
msvc\hypopg-1.3.2\12-x64\share\extension\*.sql
msvc\hypopg-1.3.2\13-x64\lib\hypopg.dll
msvc\hypopg-1.3.2\13-x64\share\extension\hypopg.control
msvc\hypopg-1.3.2\13-x64\share\extension\*.sql
msvc\hypopg-1.3.2\hypopg-1.3.2-pg12-x64.zip
msvc\hypopg-1.3.2\hypopg-1.3.2-pg13-x64.zip
```

Manually compiling the extension
--------------------------------

The Visual Studio project contains a `pgver` parameter that can be used to
compile the extension for a specific major version.

Example:

```
msbuild C:\git\hypopg\msvc\hypopg.sln /p:Configuration=Release /p:Platform=x64 /p:pgver=12
```

If the project compiles correctly, the DLL will be generated in the
`msvc\$Platform\$configuration\` subdirectory.  In the previous example, it
would be `msvc\x64\Release\hypopg.dll`.
