#!/usr/bin/env perl
#------------------------------------------------------------------------------
#
# pg_msvc_generator - MSVC project generator for PostgreSQL extensions.
#
# This program is open source, incensed under the PostgreSQL Licence.
# For license terms, see the LICENSE file.
#
# Copyright (c) 2021-2022, Julien Rouhaud

use strict;
use warnings;

use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use Cwd qw(getcwd);
use File::Basename;
use File::Copy;
use File::Spec::Functions;
use Getopt::Long;
use IPC::Run qw(run);
use Win32API::Registry qw(regLastError KEY_READ);
use Win32::TieRegistry ( Delimiter=>"#", ArrayValues=>0);

my %args = (
	"keep-nsi"			=> 0,
	"help"				=> 0,
);

my $result = GetOptions(
	\%args,
	"keep-nsi!",
	"help|h!",
) or help(1);

help(0) if ($args{help});

main(\%args);

sub help
{
	my ($rc, $msg) = @_;

	printf "%s\n", $msg if (defined $msg);

	printf qq{
Usage: release.pl [ options ]

	Extension release script.

Options:

    --keep-nsi      : don't remove the .nsi files after compilation.
    -h | --help     : Show this message.
};

	exit($rc);
}

sub check_msbuild
{
	my $out;

	my @command = ("msbuild", "/version");
	run \@command, ">&", \$out;

	foreach my $line (split("\n", $out))
	{
		if ($line =~ /^([(\.)\d+]+)$/m)
		{
			print "Found msbuild, version $1\n";
		}
	}
}

sub discover_controlfile
{
	my @files = glob catfile("..", "*.control");

	die "Could not find a .control file in parent directory."
		if (scalar @files == 0);
	die "Found multiple .control file in parent directory."
		if (scalar @files != 1);

	my $extname = basename($files[0]);
	$extname =~ s{\.[^.]+$}{};

	open(my $fh, '<', $files[0]) or die $!;
	my @control = <$fh>;
	close($fh);

	my $extversion = undef;
	foreach my $line (@control)
	{
		if ($line =~ /^default_version\s*=\s*'(.*)'/m)
		{
			$extversion = $1;
		}
	}

	return ($extname, $extversion);
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
	my ($extname, $share) = @_;
		my $makefile = catfile("..", "Makefile");

	die "No makefile found!" if (not -f $makefile);

	local $/ = undef; # rules can span over multiple lines
	open(my $fh, '<', $makefile) or die $!;
	my $rules = <$fh>;
	close($fh);
	$rules =~ s{\\\r?\n}{}g;

	my $files = undef;

	foreach my $line (split("\n", $rules))
	{
		chomp($line);

		if ($line =~ /^DATA\s*=\s*(.*)$/m)
		{
			$files = discover_files("..", $1);
		}
	}

	return $files;
}

sub generate_zip
{
	my ($extname, $extversion, $pgver, $platform, $dir) = @_;

	my $zipname= catfile("$extname-$extversion",
		"$extname-$extversion-pg$pgver-$platform.zip");

	my $zip = Archive::Zip->new();
	foreach my $subdir ("lib", "share")
	{
		$zip->addTreeMatching(catfile($dir, $subdir), $subdir, '.*' );
	}

	die 'Could not create $zipname'
		unless $zip->writeToFileNamed($zipname) == AZ_OK;
}

sub generate_installer
{
	my ($extname, $extversion, $pgver, $platform, $sql_files, $keepnsi) = @_;
	my $makensis = "C:\\Program Files (x86)\\NSIS\\Bin\\makensis.exe";

	return if (not -f "$makensis");

	my $basename = catfile("$extname-$extversion",
		"$extname-$extversion-pg$pgver-$platform");
	my $nsiname = "${basename}.nsi";

	open(my $nsi, '>', $nsiname) or die $!;
	print $nsi <<EOF;
;--------------------------------
;NSIS install script for $extname $extversion for pg$pgver $platform
;Generated by pg_msvc_generator

;--------------------------------
;Include Modern UI

  !include "MUI2.nsh"

;--------------------------------
;General

  ;Name and file
  Name "$extname $extversion for PostgreSQL $pgver $platform"
  OutFile "$extname-$extversion-pg$pgver-$platform.exe"
  Unicode True

;--------------------------------
;Interface Settings

  !define MUI_ABORTWARNING
  !define MUI_FINISHPAGE_NOAUTOCLOSE
  ShowInstDetails show

;--------------------------------
; Custom defines and variables
  !define regkey "Software\\PostgreSQL\\Installations\\postgresql-$platform-$pgver"
  Var directory_text

;--------------------------------
;Pages

  ; Variable is set on .onInit
  !define MUI_DIRECTORYPAGE_TEXT_TOP \$directory_text
  !insertmacro MUI_PAGE_DIRECTORY
  !insertmacro MUI_PAGE_INSTFILES
  !insertmacro MUI_PAGE_FINISH

  !insertmacro MUI_UNPAGE_WELCOME
  !insertmacro MUI_UNPAGE_CONFIRM
  !insertmacro MUI_UNPAGE_INSTFILES
  !insertmacro MUI_UNPAGE_FINISH

;--------------------------------
;Languages

  !insertmacro MUI_LANGUAGE "English"

;--------------------------------
;Installer Sections

Function .onInit
EOF

	if ($platform eq "x64")
	{
		print $nsi <<EOF;
  ; Need to view the 64bits version of the registry.
  SetRegView 64
EOF
	}

	print $nsi <<EOF;
  ReadRegStr \$INSTDIR  HKLM "\${regkey}" "Base Directory"
  StrCmp \$INSTDIR  "" 0 NoAbort
	StrCpy \$directory_text "No PostgreSQL $pgver $platform installation was \\
							found.\$\\r\$\\n\$\\r\$\\nClick Browse and \\
							select the folder where PostgreSQL 10 x64 is \\
							installed and then click Install to start the \\
							installation of $extname $extversion for \\
							PostgreSQL $pgver $platform."
	Return
  NoAbort:
  StrCpy \$directory_text "A PostgreSQL $pgver $platform installation was \\
						found in \$\\"\$INSTDIR\$\\".\$\\r\$\\n\$\\r\$\\n \\
						Setup will install $extname $extversion for \\
						PostgreSQL $pgver $platform in this folder. To \\
						install in a different folder, click Browse and \\
						select another folder. Click Install to start the \\
						installation."
FunctionEnd

Section "Install" Install

  SetOutPath "\$INSTDIR\\lib"
  File $pgver-$platform\\lib\\$extname.dll

  SetOutPath "\$INSTDIR\\share\\extension"
  File $pgver-$platform\\share\\extension\\$extname.control
EOF

	foreach my $file (@{$sql_files})
	{
		print $nsi <<EOF;
  File $pgver-$platform\\share\\extension\\$file
EOF
	}

	print $nsi <<EOF;

SectionEnd
EOF
	close($nsi);

	my $out;
	my @command = ($makensis, "/V0", "$nsiname");

	print "Compiling installer $basename.exe...\n";
	run \@command, ">&", \$out or print "Error:\n$out\n";
	unlink "$nsiname" unless ($keepnsi);
}

sub release_one_version
{
	my ($release) = @_;
	my $extname = $release->{extname};
	my $extversion = $release->{extversion};
	my $sql_files = $release->{sql_files};
	my $pgroot = $release->{pgroot};
	my $pgver = $release->{pgver};
	my $platform = $release->{platform};
	my $keepnsi = $release->{keep_nsi};
	my $out;

	print "Compiling $extname for PostgreSQL $pgver ($platform)...\n";
	my @comp = ("msbuild",
		"$extname.vcxproj",
		"/p:Configuration=Release",
		"/p:Platform=$platform",
		"/p:pgroot=$pgroot",
		"/p:pgver=$pgver");

	run \@comp, ">&", \$out;

	if ($? ne 0)
	{
		print "Compilation error:\n$out\n";
		return;
	}

	my $dll = catfile($platform, "Release", "$extname.dll");
	if (not -f $dll)
	{
		print "Could not compile $dll\n" if (not -f $dll);
		return;
	}

	print "Preparing the relase...\n";
	my $dir = "$extname-$extversion";
	mkdir($dir, 0700) if (not -d $dir);
	$dir = catfile($dir, "$pgver-$platform");
	mkdir($dir, 0700) if (not -d $dir);

	my $lib = catfile($dir, "lib");
	mkdir($lib, 0700) if (not -d $lib);
	copy($dll, $lib);

	my $share = catfile($dir, "share");
	mkdir($share, 0700) if (not -d $share);
	$share = catfile($share, "extension");
	mkdir($share, 0700) if (not -d $share);
	copy(catfile("..", "$extname.control"), $share);

	if (defined $sql_files)
	{
		foreach my $file (@{$sql_files})
		{
			copy(catfile("..", "$file"), $share);
		}
	}

	generate_zip($extname, $extversion, $pgver, $platform, $dir);
	generate_installer($extname, $extversion, $pgver, $platform, $sql_files,
		$keepnsi);

	print "Done\n\n";
}

sub main
{
	my ($args) = @_;

	check_msbuild();

	my ($extname, $extversion) = discover_controlfile();
	my $sql_files = discover_extension();

	print "Found extension $extname, version $extversion\n";

	my $pound= $Registry->Delimiter("/");

	my $hklm = $Registry->Open( "LMachine", {Access=>KEY_READ(), Delimiter=>"/"} );
	my $path = "SOFTWARE/PostgreSQL/Installations";
	my $installs = $hklm->Open($path)
		or die("Could not find PostgreSQL installations in \"HKLM/$path\".\n");

	foreach my $ver ( keys(%{$installs}) ) {
		if ($ver =~ /postgresql(-x64)?-(\d+(\.\d+)?)/) {
			my $pgver = $2;
			my $platform = $1 ? "x64" : "x86";
			my $pgroot = $installs->{"$ver/Base Directory"} or die(
				"Could not find PostgreSQL installation directory"
				. " in \"HKLM/$path/$ver/Base Directory.\n");

			$pgroot =~ s/(.*)\\(\d+\.)?\d+$/$1/;

			my %release = (
				"extname"		=> $extname,
				"extversion"	=> $extversion,
				"sql_files"		=> $sql_files,
				"pgroot"		=> $pgroot,
				"pgver"			=> $pgver,
				"platform"		=> $platform,
				"keep_nsi"		=> $args->{"keep-nsi"},
			);

			release_one_version(\%release);
		} else {
			print "Could not understand version \"$ver\"."
		}
	}
}
