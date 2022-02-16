#Requires -RunAsAdministrator

# this may be needed to run the script:
# Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
$ErrorActionPreference = "Stop"

$envscope = "Machine"

function Check-ChocoPkg {
    param ($pkg)

    Write-output "Checking for $pkg..."
    if ($choco_list -like "*$pkg*")
    {
        Write-output "$pkg already installed"
    }
    else
    {
        Write-output "Installing $pkg..."
        choco install --yes $pkg
        refreshenv
    }
}

function Rename-IfExist {
    param ($path, $from, $to)

    if (Test-Path -Path "$path\$from")
    {
        Write-output "Renaming $path/$from to $to..."
        Rename-Item -Path "$path\$from" "$path\$to"
    }
}

function Add-ToPath {
    param($path)
    Write-output "Updating path with $path..."

    $cur = [Environment]::GetEnvironmentVariable("Path", "$envscope")
    if ($cur -like "*$path*")
    {
        Write-output "$path already present"
    }
    else
    {
        $newpath = $cur + ";$path"
        [Environment]::SetEnvironmentVariable("Path", "$newpath", "$envscope")
        Write-output "Done"
    }
}

function Download-ExtractZip {
    param($what, $path, $marker, $url)

    if (Test-Path -Path "$path/$marker")
    {
        Write-output "$what already processed ($marker present)"
        return
    }

    Write-output "Downloading $url in $what.zip..."
    $tmp = "$Env:TEMP/$what.zip"
    curl.exe -sSL -o "$tmp" $url
    if (!$?)
    {
        throw "Error downloading the archive"
    }

    Write-output "Extracting $what.zip in $path"
    7z.exe x "$tmp" -o"$path"
    if (!$?)
    {
        throw "Error extracting the archive"
    }
}

$error.clear()
try {
    Write-output "Checking for chocolatey..."
    choco -v
    Write-output "chocolatey found"
}
catch {
    Write-output "Installing chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}

$choco_list = choco list --local-only | Out-String
Check-ChocoPkg activeperl
Check-ChocoPkg python
Check-ChocoPkg openssl
Check-ChocoPkg winflexbison3
Rename-IfExist "C:\ProgramData\chocolatey\bin" "win_flex.exe" "flex.exe"
Rename-IfExist "C:\ProgramData\chocolatey\bin" "win_bison.exe" "bison.exe"
Check-ChocoPkg git
Check-ChocoPkg 7zip
Check-ChocoPkg visualstudio2019buildtools
Check-ChocoPkg visualstudio2019community
Check-ChocoPkg visualstudio2019-workload-vctools
Check-ChocoPkg visualcpp-build-tools

$gettext_ver = "0.18.1.1-2"
$nls_path = "C:/gettext-$gettext_ver"
Download-ExtractZip "gettext-runtime-dev-$gettext_ver" "$nls_path" "lib/libintl.lib" "https://download.gnome.org/binaries/win64/dependencies/gettext-runtime-dev_$($gettext_ver)_win64.zip"
Rename-IfExist "$nls_path/lib" "intl.lib" "libintl.lib"
Download-ExtractZip "gettext-runtime_$gettext_ver" "$nls_path" "bin/libintl-8.dll" "https://download.gnome.org/binaries/win64/dependencies/gettext-runtime_$($gettext_ver)_win64.zip"
Download-ExtractZip "gettext-tools-dev_$gettext_ver" "$nls_path" "bin/msgfmt.exe" "https://download.gnome.org/binaries/win64/dependencies/gettext-tools-dev_$($gettext_ver)_win64.zip"
Add-ToPath "$nls_path/bin"

Write-output "Linking VS 2019 command line tool to the desktop..."
$dev_cmd_bat_name = "LaunchDevCmd.bat"
$dev_cmd_bat_path = "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\Common7\Tools\"
$dest_bat = [Environment]::GetFolderPath('CommonDesktopDirectory') + "\$dev_cmd_bat_name"
if (Test-Path -Path "$dest_bat")
{
    Write-output "Link already exists"
}
else
{
    New-Item -Path $dest_bat -ItemType SymbolicLink -Value "$dev_cmd_bat_path\$dev_cmd_bat_name"
}

$vcpath = "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\MSBuild\Microsoft\VC\v160\"
$nmake_path = "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Tools\MSVC\14.29.30133\bin\Hostx64\x64"
$msbuild_path = "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin"
$vcvarsall_path = "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\VC\Auxiliary\Build"

Add-ToPath $nmake_path
Add-ToPath $msbuild_path
Add-ToPath $vcvarsall_path

Write-output "Setting VCTargetsPath environment variable..."
[Environment]::SetEnvironmentVariable("VCTargetsPath", "$vcpath", "$envscope")

$launcher = [Environment]::GetFolderPath('CommonDesktopDirectory') + "\postgres.bat"

Write-output "Creating launcher..."
if (Test-Path -Path "$launcher")
{
    Write-output "Launcher already exists"
}
else
{
    New-Item "$launcher" -ItemType File -Value "@TITLE PostgreSQL dev"
    Add-Content "$launcher" [Environment]::NewLine
    Add-Content "$launcher" '@%comspec% /k " vcvarsall x64 && cd C:\Users\user/postgres/src/tools/msvc'
    Write-output "Done"
}
