pg_msvc_generator
=================

Project to help developping PostgreSQL or its extensions on Windows.

It contains:

- a script to bootstrap an environment to compile PostgreSQL using MSVC
- a tool to generate MSBC project for PostgreSQL extensions.

Environment bootstrap
---------------------

/!\ This script is still a work in progress /!\

The script is aimed to be run against the [evalutation virtual
machine](https://developer.microsoft.com/en-us/windows/downloads/virtual-machines/).

Open an administrator powershell, and execute **bootstrap.ps1**.

You may need to execute first:

```
Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

To be able to run the script.

The script will install all dependencies, configure some environment variable
and create a **postgres.bat** script on the desktop to launch a shell properly
configured.


Project generator
-----------------

Basic tool usage is:

```
pg_msvc_generator.pl [ options ]

Options:

    --default version pgver  : default PostgreSQL version. This is only used
                if you compile the project without specifying a specific major
                version, or when the project is opened with Visual Studio
                IDE.  If not provided, a default value based on the year will
                be chosen (13 for 2021, 14 for 2022 and so on).
    -d | --dir ext_directory : root directory of the extension source code.
    -e | --extension         : extension name.  If not provided, the extension
                name will be assumed using the last part of the given root
                directory.
    -h | --help              : Show this message.
```

It will generate an `msvc` subdirectory in the given extension directory,
containing the required `.sln` and `.vcxproj` files to be able to compile the
extension using Visual Studio 2019, with support for Debug/Release and 32/64
bits builds.  It will alse create copy the `release.pl` and generate a
`build.bat` scripts that can automatically compile and create release archive
files for all installed PostgreSQL versions.

Example:

```
pg_msvc_generator.pl -d C:\git\hypopg
```

Requirements
------------

**At project generation time**:

  - A Windows host with Perl installed to generate the project files

**At extension compilation time**:

  - Perl
  - Visual Studio 2019
  - All major PostgreSQL versions for which you want to build the extension
  - Optionally, NSIS installed **in the default location**
    (`C:\Program Files (x86)\NSIS`) to generate installers

Doing a release of your extension
---------------------------------

All you need to do is to execute the `msvc\release.bat` script.  It will setup
the MSVC environment and call the `release.pl` script.  That script will
prepare everything for a release under a
`msvc\${extension_name}-${extension_version}` directory.

It will automatically find the installed PostgreSQL version reading the
`HKLM/SOFTWARE/PostgreSQL/Installations/` registry, compile the extension with
all those versions and for each will generate a subdirectory containing the dll
and the SQL scripts if any, a zip archive with the same content and optionally
qn installer.

For instance, assuming that you have PostgreSQL 12 and 13 installed and
released HypoPG 1.3.2 and NSIS installed, your `msvc` directory will now have
this additional content:

```
msvc\hypopg-1.3.2\12-x64\lib\hypopg.dll
msvc\hypopg-1.3.2\12-x64\share\extension\hypopg.control
msvc\hypopg-1.3.2\12-x64\share\extension\*.sql
msvc\hypopg-1.3.2\13-x64\lib\hypopg.dll
msvc\hypopg-1.3.2\13-x64\share\extension\hypopg.control
msvc\hypopg-1.3.2\13-x64\share\extension\*.sql
msvc\hypopg-1.3.2\hypopg-1.3.2-pg12-x64.exe
msvc\hypopg-1.3.2\hypopg-1.3.2-pg12-x64.zip
msvc\hypopg-1.3.2\hypopg-1.3.2-pg13-x64.exe
msvc\hypopg-1.3.2\hypopg-1.3.2-pg13-x64.zip
```

Installer
---------

If you have [NSIS](https://nsis.sourceforge.io/) installed in the default
location (`C:\Program Files (x86)\NSIS), the `release.pl` script will generate
a `.nsi` file and compile it using **makensis.exe** to generate a specific
installer for each PostgreSQL major versions found when running the
`release.pl` script/.  At execution time, he installer will try to discover the
server's PostgreSQL installation path by reading the registry key
**HKEY_LOCAL_MACHINE\SOFTWARE\PostgreSQL\Installations\postgresql-$architecture-$majorversion\Base
Directory**.

If the key is found, the installer will inform the user and use it as the
default installation location.  Otherwise, the installer will inform the user
that no installation was automatically found and will force the user to choose
a location before being able to continue the installation.

Manually compiling the extension
--------------------------------

The Visual Studio project contains a `pgver` parameter that can be used to
compile the extension for a specific major version.

Parameters available for the msvc project:

  - **pgroot**: root directory of your PostgreSQL local installations.  Default
                is **C:\Program Files\PostgreSQL** for 64bits platform and
                **C:\Program Files (x86)\PostgreSQL** for 32bits platform.
  - **pgver**: major PostgreSQL version, which will be concatenated to the
               **pgroot** directory.

Example:

```
msbuild C:\git\hypopg\msvc\hypopg.sln /p:Configuration=Release /p:Platform=x64 /p:pgver=12
```

If the project compiles correctly, the DLL will be generated in the
`msvc\$Platform\$configuration\` subdirectory.  In the previous example, it
would be `msvc\x64\Release\hypopg.dll`.
