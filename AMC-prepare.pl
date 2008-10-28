#! /usr/bin/perl
#
# Copyright (C) 2008 Alexis Bienvenue <paamc@passoire.fr>
#
# This file is part of Auto-Multiple-Choice
#
# Auto-Multiple-Choice is free software: you can redistribute it
# and/or modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation, either version 3 of
# the License, or (at your option) any later version.
#
# Auto-Multiple-Choice is distributed in the hope that it will be
# useful, but WITHOUT ANY WARRANTY; without even the implied warranty
# of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Auto-Multiple-Choice.  If not, see
# <http://www.gnu.org/licenses/>.

use XML::Simple;
use File::Copy;
use File::Spec::Functions qw/splitpath catpath splitdir catdir catfile rel2abs tmpdir/;
use File::Temp qw/ tempfile tempdir /;
use Data::Dumper;
use Getopt::Long;

use AMC::Gui::Avancement;

my $mode="mbs";
my $mep_dir="";
my $bareme="";
my $convert_opts="-limit memory 512mb";
my $dpi=300;
my $calage='';

my $ppm_via='pdf';

my $prefix='';

my $debug=0;

my $progress=0;

GetOptions("mode=s"=>\$mode,
	   "via=s"=>\$ppm_via,
	   "mep=s"=>\$mep_dir,
	   "bareme=s"=>\$bareme,
	   "calage=s"=>\$calage,
	   "dpi=s"=>\$dpi,
	   "convert-opts=s"=>\$convert_opts,
	   "debug!"=>\$debug,
	   "progression=s"=>\$progress,
	   "prefix=s"=>\$prefix,
	   );

my $avance=AMC::Gui::Avancement::new($progress);

$debug=($debug ? " --debug " : "");

my $tex_source=$ARGV[0];

die "Fichier inconnu : $tex_source" if(! -f $tex_source);

my $base=$tex_source;
$base =~ s/\.tex$//gi;

$bareme="$base-bareme.xml" if(!$bareme);
$mep_dir="$base-mep" if(!$mep_dir);

for(\$bareme,\$mep_dir,\$tex_source) {
    $$_=rel2abs($$_);
}

if(! -x $mep_dir) {
    mkdir($mep_dir);
}

die "Repertoire inexistant : $mep_dir" if(! -d $mep_dir);

($e_volume,$e_vdirectories,$e_vfile) = splitpath( rel2abs($0) );
sub with_prog {
    my $fich=shift;
    return(catpath($e_volume,$e_vdirectories,$fich));
}

sub execute {
    my $s=shift;

    open(EXEC,"$s |") or die "Impossible d'executer $s";
    while(<EXEC>) {
	s/AUTOQCM\[.*\]//g;
	print $_ if(/^.+$/);
    }
    close(EXEC);
    #system($s);
}

$temp_loc=tmpdir();
$temp_dir = tempdir( DIR=>$temp_loc,CLEANUP => 1 );

# reconnaissance mode binaire/decimal :

$binaire=' --binaire ';

open(SCANTEX,$tex_source) or die "Impossible de lire $tex_source : $!";
while(<SCANTEX>) {
    if(/usepackage\[([^\]]+)\]\{autoQCM\}/) {
	my $opts=$1;
	if($opts =~ /\bdecimal\b/) {
	    $binaire="";
	    print "Mode decimal.\n";
	}

    }
}
close(SCANTEX);

# on se place dans le repertoire du LaTeX
($v,$d,$f_tex)=splitpath($tex_source);
chdir(catpath($v,$d,""));
$f_base=$f_tex;
$f_base =~ s/\.tex$//i;

$prefix=$f_base."-" if(!$prefix);

$latex_cmd="latex \"\\nonstopmode\\def\\CalibrationExterne{1}\\def\\NoHyperRef{1} \\input $f_tex\"";

if($mode =~ /s/) {
    # SUJETS

    # 1) compilation du sujet

    execute("pdflatex \"\\nonstopmode\\def\\SujetExterne{1}\\def\\NoHyperRef{1} \\input $f_tex\"");
    move("$f_base.pdf",$prefix."sujet.pdf");

    # 2) compilation de la correction

    execute("pdflatex \"\\nonstopmode\\def\\CorrigeExterne{1}\\def\\NoHyperRef{1} \\input $f_tex\"");
    move("$f_base.pdf",$prefix."corrige.pdf");

    # 3) document de calage

    execute("pdf".$latex_cmd);
    move("$f_base.pdf",$prefix."calage.pdf");

}

if($mode =~ /m/) {
    # MISE EN PAGE

    # 1) compilation en mode calibration

    print "********** Compilation...\n";

    $avance->progres(0.07);

    if(-f $calage && $calage =~ /\.$ppm_via$/) {
	print "Utilisation du fichier de calage $calage\n";
    } else {
	if($ppm_via eq 'pdf') {
	    execute("pdf".$latex_cmd);
	} elsif($ppm_via eq 'ps') {
	    execute($latex_cmd);
	    execute("dvips $f_base -o");
	} else {
	    die "Mauvaise valeur pour --via : $ppm_via";
	}
	$calage="$f_base.$ppm_via";
    }

    # 2) analyse page par page

    print "********** Conversion en bitmap et analyse...\n";

    $avance->progres(0.03);
    
    @pages=();
    open(IDCMD,"identify $calage |") or die "Erreur d'identification : $!";
    while(<IDCMD>) {
	if(/^([^\[]+)\[([0-9]+)\]\s+(PDF|PS)/) {
	    push @pages,"$1\'[$2]\'";
	}
    }
    close(IDCMD);
    
    my $npage=0;
    my $np=1+$#pages;
    for my $p (@pages) {
	$npage++;
	print "*** $p\n";
	$avance->progres(0.9/$np*.4);
	execute("convert $convert_opts -density $dpi -depth 8 +antialias $p $temp_dir/page.ppm");
	$avance->progres(0.9/$np*.6);
	$cmd=with_prog("AMC-calepage.pl")
	    ." --progression ".($progress>0 ? $progress+1 : 0)
	    ." $debug $binaire --tex-source $tex_source --page $npage --dpi $dpi --modele --mep $mep_dir $temp_dir/page.ppm";
	execute($cmd);
    }
}

if($mode =~ /b/) {
    # BAREME

    print "********** Preparation du bareme...\n";

    # compilation en mode calibration

    my %bs=();
    my %qs=();
    my %titres=();

    my $quest='';
    my $rep='';
    open(TEX,"$latex_cmd |") or die "Impossible d'executer latex";
    while(<TEX>) {
	if(/AUTOQCM\[Q=([0-9]+)\]/) { 
	    $quest=$1;$rep=''; 
	    $qs{$quest}=1;
	}
	if(/AUTOQCM\[NUM=([0-9]+)=([^\]]+)\]/) {
	    $titres{$1}=$2;
	}
	if(/AUTOQCM\[MULT\]/) { 
	    $qs{$quest}='M';
	}
	if(/AUTOQCM\[REP=([0-9]+):([BM])\]/) {
	    $rep=$1;
	    $bs{"$quest.$rep"}={-bonne=>($2 eq 'B' ? 1 : 0)};
	}
	if(/AUTOQCM\[B=([^\]]+)\]/) {
	    $bs{"$quest.$rep"}->{-bareme}=$1;
	}
    }
    close(TEX);

    open(BAR,">$bareme") or die "Impossible d'ecrire dans $bareme";
    print BAR "<?xml version='1.0' standalone='yes'?>\n";
    print BAR "<bareme src=\"$f_tex\">\n";
    for my $q (keys %qs) {
	print BAR "  <question id=\"$q\""
	    ." titre=\"".$titres{$q}."\""
	    .($bs{"$q."} ? " bareme=\"".$bs{"$q."}->{-bareme}."\"" : "")
	    ." multiple=\"".($qs{$q} eq "M" ? 1 : "")."\""
	    .">\n";
	for my $i (keys %bs) {
	    if($i =~ /^$q\.([0-9]+)/) {
		my $rep=$1;
		print BAR "    <reponse id=\"$rep\" bonne=\""
		    .$bs{$i}->{-bonne}."\""
		    .($bs{"$i"}->{-bareme} ? " bareme=\"".$bs{"$i"}->{-bareme}."\"" : "")
		    ." />\n";
	    }
	}
	print BAR "  </question>\n";
    }
    print BAR "</bareme>\n";
    close(BAR);
}

