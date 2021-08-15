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

use Archive::Zip qw( :ERROR_CODES :CONSTANTS );
use Cwd qw(getcwd);
use File::Basename;
use File::Copy;
use File::Spec::Functions;
use IPC::Run qw(run);
use Win32API::Registry qw(regLastError KEY_READ);
use Win32::TieRegistry ( Delimiter=>"#", ArrayValues=>0);

main();

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

sub release_one_version
{
	my ($extname, $extversion, $sql_files, $pgver, $platform) = @_;
	my $out;

	print "Compiling $extname for PostgreSQL $pgver ($platform)...\n";
	my @comp = ("msbuild",
		"$extname.vcxproj",
		"/p:Configuration=Release",
		"/p:Platform=$platform",
		"/p:pgver=$2");

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

	print "Done\n\n";
}

sub main
{
	check_msbuild();

	my ($extname, $extversion) = discover_controlfile();
	my $sql_files = discover_extension();

	print "Found extension $extname, version $extversion\n";

	my $pound= $Registry->Delimiter("/");

	my $hklm = $Registry->Open( "LMachine", {Access=>KEY_READ(), Delimiter=>"/"} );
	my $path = "SOFTWARE/PostgreSQL/Installations/";
	my $installs = $hklm->Open($path)
		or die("Could not find PostgreSQL installations in \"HKLM/$path\".\n");

	foreach my $ver ( keys(%{$installs}) ) {
		if ($ver =~ /postgresql(-x64)?-(\d+(\.\d+)?)/) {
			my $pgver = $2;
			my $platform = $1 ? "x64" : "x86";

			release_one_version($extname, $extversion, $sql_files, $pgver,
				$platform);
		} else {
			print "Could not understand version \"$ver\"."
		}
	}
}
