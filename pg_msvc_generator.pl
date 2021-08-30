#!/usr/bin/env perl
#------------------------------------------------------------------------------
#
# pg_msvc_generator - MSVC project generator for PostgreSQL extensions.
#
# This program is open source, incensed under the PostgreSQL Licence.
# For license terms, see the LICENSE file.
#
# Copyright (c) 2021, Julien Rouhaud

use strict;
use warnings;

use Cwd qw(getcwd);
use Data::Dumper;
use File::Basename;
use File::Copy;
use File::Spec::Functions;
use Getopt::Long;
use Time::Piece;
use Win32;

my %args = (
	"default-version"	=> undef,
	"dir"		        => undef,
	"extension"			=> undef,
	"help"				=> 0,
);

my $result = GetOptions(
	\%args,
	"default-version=s",
	"dir|d=s",
	"extension|e=s",
	"help|h!",
) or help(1);

help(0) if ($args{help});
help(1, "No directory specified") unless defined($args{dir});

if (not defined($args{extension}))
{
	my $ext = basename($args{dir});
	$args{extension} = $ext;

	printf("No explicit extension name provided, assuming \"$ext\"\n");
}

main(\%args);

sub help
{
	my ($rc, $msg) = @_;

	printf "%s\n", $msg if (defined $msg);

	printf qq{
Usage: pg_msvc_generator.pl [ options ]

	MSVC project generator for PostgreSQL extensions.

Options:

    --default version pgver  : default PostgreSQL version. This is only used
                when the project is opened with Visual Studio.  If not
                provided, a default value based on the year will be choosen (13
                for 2021, 14 for 2022 and so on).
    -d | --dir ext_directory : root directory of the extension source code.
    -e | --extension         : extension name.
    -h | --help              : Show this message.
};

	exit($rc);
}

sub discover_files
{
	my ($dir, $match) = @_;

	if ($match =~ /\$\(wildcard (.*)\)/m)
	{
		my $_dir = getcwd();

		chdir "$dir";
		my @files = glob "$1";
		chdir "$_dir";

		return \@files;
	}
	else
	{
		my @files;

		foreach my $f (split /\s+/, $match)
		{
			chomp($f);
			push(@files, $f);
		}

		return \@files;
	}
}

sub discover_extension
{
	my ($dir, $extname) = @_;
	my $makefile = catfile($dir, "Makefile");
	my %ext = (
		source_files	=> undef,
		sql_files		=> undef,
	);

	help(1, "Directory \"$dir\" does not exist.") unless -d "$dir";
	help(1, "Makefile \"$makefile\" does not exist.")
		unless -f "$makefile";

	local $/ = undef; # rules can span over multiple lines
	open(my $fh, '<', $makefile) or die $!;
	my $rules = <$fh>;
	close($fh);
	$rules =~ s{\\\r?\n}{}g;

	foreach my $line (split("\n", $rules))
	{
		chomp($line);

		if ($line =~ /^([A-Z]+)\s*=\s*(.*)$/m)
		{
			my $what = $1;
			my $match = $2;

			if ($what eq "DATA")
			{
				$ext{sql_files} = discover_files($dir, $match);
			}
			elsif ($what eq "MODULES")
			{
				$ext{source_files} = discover_files($dir, $match);

				$_ .= ".c" for @{$ext{source_files}};
			}
			elsif ($what eq "OBJS")
			{
				$ext{source_files} = discover_files($dir, $match);

				$_ =~ s/\.o/.c/ for @{$ext{source_files}};
			}
		}
	}

	foreach my $key ("sql_files", "source_files")
	{
		die "No $key found in $makefile.\n"
			unless(defined $ext{$key} and scalar @{$ext{$key}} > 0);
	}

	return \%ext;
}

sub setup_msvc
{
	my ($ext) = @_;

	$ext->{msvc}->{configuration} = ["Debug", "Release"];
	$ext->{msvc}->{platform} = ["Win32", "x64"];
}

sub append_proj_config
{
	my ($ext, $fh) = @_;

	print $fh <<EOF;
  <ItemGroup Label="ProjectConfigurations">
EOF
	foreach my $platform (@{$ext->{msvc}->{platform}})
	{
		foreach my $config (@{$ext->{msvc}->{configuration}})
		{
			print $fh <<EOF;
    <ProjectConfiguration Include="$config|$platform">
      <Configuration>$config</Configuration>
      <Platform>$platform</Platform>
    </ProjectConfiguration>
EOF
		}
	}

	print $fh <<EOF;
  </ItemGroup>
EOF

	foreach my $platform (@{$ext->{msvc}->{platform}})
	{

		foreach my $config (@{$ext->{msvc}->{configuration}})
		{
			my $use_debug = $config eq "Debug" ? "true" : "false";

			print $fh <<EOF;
  <PropertyGroup Condition="'\$(Configuration)|\$(Platform)'=='$config|$platform'" Label="Configuration">
    <ConfigurationType>DynamicLibrary</ConfigurationType>
    <UseDebugLibraries>$use_debug</UseDebugLibraries>
EOF
			if ($config eq "Release")
			{
				print $fh <<EOF;
    <WholeProgramOptimization>true</WholeProgramOptimization>
EOF
			}

			print $fh <<EOF;
    <PlatformToolset>v142</PlatformToolset>
    <CharacterSet>Unicode</CharacterSet>
  </PropertyGroup>
EOF
		}
	}
}

sub append_proj_importgroup
{
	my ($ext, $fh) = @_;

	print $fh <<EOF;
  <Import Project="\$(VCTargetsPath)\\Microsoft.Cpp.props" />
  <ImportGroup Label="ExtensionSettings">
  </ImportGroup>
  <ImportGroup Label="Shared">
  </ImportGroup>
EOF

	foreach my $platform (@{$ext->{msvc}->{platform}})
	{
		foreach my $config (@{$ext->{msvc}->{configuration}})
		{
			print $fh <<EOF;
  <ImportGroup Label="PropertySheets" Condition="'\$(Configuration)|\$(Platform)'=='$config|$platform'">
    <Import Project="\$(UserRootDir)\\Microsoft.Cpp.\$(Platform).user.props" Condition="exists('\$(UserRootDir)\\Microsoft.Cpp.\$(Platform).user.props')" Label="LocalAppDataPlatform" />
  </ImportGroup>
EOF
		}
	}
}

sub append_proj_default_version
{
	my ($fh, $default_version) = @_;

	if (not defined $default_version)
	{
		my $t = Time::Piece->new();

		$default_version = $t->year - 2021 + 13;
	}

	print $fh <<EOF;
  <PropertyGroup>
    <PgVer Condition=" '\$(pgver)' == '' ">$default_version</PgVer>
    <PgRoot Condition=" '\$(pgroot)|\$(Platform)' == '|win32' ">C:\\Program Files (x86)\\PostgreSQL</PgRoot>
    <PgRoot Condition=" '\$(pgroot)|\$(Platform)' == '|x64' ">C:\\Program Files\\PostgreSQL</PgRoot>
  </PropertyGroup>
EOF
}

sub append_proj_propertygroup
{
	my ($ext, $fh) = @_;

	print $fh <<EOF;
  <PropertyGroup Label="UserMacros" />
EOF

	foreach my $platform (@{$ext->{msvc}->{platform}})
	{
		foreach my $config (@{$ext->{msvc}->{configuration}})
		{
			my $link_inc = $config eq "Debug" ? "true" : "false";

			print $fh <<EOF;
  <PropertyGroup Condition="'\$(Configuration)|\$(Platform)'=='$config|$platform'">
    <LinkIncremental>$link_inc</LinkIncremental>
    <GenerateManifest>false</GenerateManifest>
  </PropertyGroup>
EOF
		}
	}
}

sub append_proj_includes
{
	my ($ext, $fh) = @_;

	foreach my $platform (@{$ext->{msvc}->{platform}})
	{
		my $root = "\$(PgRoot)\\\$(PgVer)";
		my $inc_dirs = "$root\\include\\server\\port\\win32_msvc"
			. ";$root\\include\\server\\port\\win32"
			. ";$root\\include\\server"
			. ";$root\\include"
			. ";.."
			. ";%(AdditionalIncludeDirectories)";
		my $lib_dirs = "$root\\lib"
			. ";%(AdditionalLibraryDirectories)";

		foreach my $config (@{$ext->{msvc}->{configuration}})
		{
			my $preprocessor = "_CRT_SECURE_NO_WARNINGS;_CONSOLE";

			if ($platform eq "Win32")
			{
				$preprocessor .= ";WIN32";
			}

			if ($config eq "Debug")
			{
				$preprocessor .= ";_DEBUG";
			}
			else
			{
				$preprocessor .= ";NDEBUG";
			}

			$preprocessor .= ";%(PreprocessorDefinitions)";

			print $fh <<EOF;
  <ItemDefinitionGroup Condition="'\$(Configuration)|\$(Platform)'=='$config|$platform'">
    <ClCompile>
      <WarningLevel>Level3</WarningLevel>
      <SDLCheck>true</SDLCheck>
      <PreprocessorDefinitions>$preprocessor</PreprocessorDefinitions>
      <DisableSpecificWarnings>4018;4244;4228;4267</DisableSpecificWarnings>
      <ConformanceMode>true</ConformanceMode>
      <ExceptionHandling>false</ExceptionHandling>
      <CompileAs>CompileAsC</CompileAs>
      <AdditionalIncludeDirectories>$inc_dirs</AdditionalIncludeDirectories>
EOF

			if ($config eq "Release")
			{
				print $fh <<EOF;
      <FunctionLevelLinking>true</FunctionLevelLinking>
      <IntrinsicFunctions>true</IntrinsicFunctions>
EOF
			}

			print $fh <<EOF;
    </ClCompile>
    <Link>
      <SubSystem>Console</SubSystem>
      <GenerateDebugInformation>true</GenerateDebugInformation>
      <AdditionalDependencies>postgres.lib;%(AdditionalDependencies)</AdditionalDependencies>
      <AdditionalLibraryDirectories>$lib_dirs</AdditionalLibraryDirectories>
EOF

			if ($config eq "Release")
			{
				print $fh <<EOF;
      <EnableCOMDATFolding>true</EnableCOMDATFolding>
      <OptimizeReferences>true</OptimizeReferences>
EOF
			}

			print $fh <<EOF;
    </Link>
  </ItemDefinitionGroup>
EOF
		}
	}
}

sub append_proj_sources
{
	my ($ext, $fh) = @_;

	print $fh <<EOF;
  <ItemGroup>
EOF

	foreach my $f (@{$ext->{source_files}})
	{
		$f =~ s/\//\\/g;

		print $fh <<EOF;
    <ClCompile Include="..\\$f" />
EOF
	}

	print $fh <<EOF;
  </ItemGroup>
EOF
}

sub generate_msvc
{
	my ($ext, $dir, $extname, $default_version) = @_;
	my $msvc = catfile($dir, "msvc");
	my $sln_path = catfile($msvc, "$extname.sln");
	my $proj_path = catfile($msvc, "$extname.vcxproj");
	my $sol_guid = Win32::GuidGen();
	my $proj_guid = Win32::GuidGen();

	if (not -d $msvc)
	{
		mkdir($msvc, 0700) or die "Could not create directory \"$msvc\">"
	}

	open(my $sln, '>', "$sln_path") or die $!;
	print $sln <<EOF;

Microsoft Visual Studio Solution File, Format Version 12.00
# Visual Studio Version 16
VisualStudioVersion = 16.0.28279.10
MinimumVisualStudioVersion = 10.0.40219.1
Project("{8BC9CEB8-8B4A-11D0-8D11-00A0C91BC942}") = "$extname", "$extname.vcxproj", "$proj_guid"
EndProject
Global
	GlobalSection(SolutionConfigurationPlatforms) = preSolution
		Debug|x64 = Debug|x64
		Debug|x86 = Debug|x86
		Release|x64 = Release|x64
		Release|x86 = Release|x86
	EndGlobalSection
	GlobalSection(ProjectConfigurationPlatforms) = postSolution
		$proj_guid.Debug|x64.ActiveCfg = Debug|x64
		$proj_guid.Debug|x64.Build.0 = Debug|x64
		$proj_guid.Debug|x86.ActiveCfg = Debug|Win32
		$proj_guid.Debug|x86.Build.0 = Debug|Win32
		$proj_guid.Release|x64.ActiveCfg = Release|x64
		$proj_guid.Release|x64.Build.0 = Release|x64
		$proj_guid.Release|x86.ActiveCfg = Release|Win32
		$proj_guid.Release|x86.Build.0 = Release|Win32
	EndGlobalSection
	GlobalSection(SolutionProperties) = preSolution
		HideSolutionNode = FALSE
	EndGlobalSection
	GlobalSection(ExtensibilityGlobals) = postSolution
		SolutionGuid = $sol_guid
	EndGlobalSection
EndGlobal
EOF
	close($sln);

	open(my $proj, '>', "$proj_path") or die $!;

	print $proj <<EOF;
<?xml version="1.0" encoding="utf-8"?>
<Project DefaultTargets="Build" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <PropertyGroup Label="Globals">
    <VCProjectVersion>16.0</VCProjectVersion>
    <Keyword>Win32Proj</Keyword>
    <ProjectGuid>$proj_guid</ProjectGuid>
    <WindowsTargetPlatformVersion>10.0</WindowsTargetPlatformVersion>
  </PropertyGroup>
  <Import Project="\$(VCTargetsPath)\\Microsoft.Cpp.Default.props" />
EOF
	append_proj_config($ext, $proj);
	append_proj_importgroup($ext, $proj);
	append_proj_propertygroup($ext, $proj);
	append_proj_default_version($proj, $default_version);
	append_proj_includes($ext, $proj);
	append_proj_sources($ext, $proj);

	print $proj <<EOF;
  <Import Project="\$(VCTargetsPath)\\Microsoft.Cpp.targets" />
  <ImportGroup Label="ExtensionTargets">
  </ImportGroup>
</Project>
EOF

	close($proj);
}

sub generate_utils
{
	my ($dir) = @_;
	my $msvc = catfile($dir, "msvc");

	open(my $bat, '>', catfile($msvc, "release.bat")) or die $!;
	print $bat <<EOF;
call "C:\\Program Files (x86)\\Microsoft Visual Studio\\2019\\Community\\VC\\Auxiliary\\Build\\vcvars64.bat"

ECHO Running release.pl
cd %~dp0
perl release.pl
pause
EOF

	copy("release.pl", catfile($msvc, "release.pl"));
}

sub main
{
	my ($args) = @_;

	my $ext = discover_extension($args->{dir}, $args->{extension});

	setup_msvc($ext);

	generate_msvc($ext, $args->{dir}, $args->{extension},
		$args->{"default-version"});

	generate_utils($args->{dir});
}
