#! /usr/bin/perl

use Data::Dumper;

my %k=();

$s=`svnversion`;
if($s =~ /([0-9]+)[SM]*$/) {
    $k{'svn'}=$1;
}

open(CHL,"ChangeLog");
LINES: while(<CHL>) {
    if(/^([0-9:.-svn]+)/) {
	$k{'deb'}=$1;
	last LINES;
    }
}

$d = Data::Dumper->new([\%k], ['k']); 

open(VPL,">nv.pl");
print VPL $d->Dump;
close(VPL);

open(VMK,">Makefile.versions");
print VMK "PACKAGE_V_DEB=$k{'deb'}\n";
print VMK "PACKAGE_V_SVN=$k{'svn'}\n";
close(VMK);
