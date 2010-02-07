#! /usr/bin/perl
#
# Copyright (C) 2008-2010 Alexis Bienvenue <paamc@passoire.fr>
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

use IO::File;
use XML::Writer;

use AMC::Basic;
use AMC::Gui::Avancement;
use AMC::Queue;

$VERSION_BAREME=2;

my $cmd_pid='';

my $queue='';

sub catch_signal {
    my $signame = shift;
    debug "*** AMC-prepare : signal $signame, je tue $cmd_pid...";
    kill 9,$cmd_pid if($cmd_pid);
    $queue->killall() if($queue);
    die "Killed";
}

$SIG{INT} = \&catch_signal;

my $mode="mbs";
my $mep_dir="";
my $bareme="";
my $convert_opts="-limit memory 512mb";
my $dpi=300;
my $calage='';

my $moteur_latex='latex';

my $prefix='';

my $debug='';

my $n_procs=0;
my $nombre_copies=0;

my $progress=1;
my $progress_id='';

my $out_calage='';
my $out_sujet='';
my $out_corrige='';

my $moteur_raster='auto';

my $encodage_interne='UTF-8';

GetOptions("mode=s"=>\$mode,
	   "with=s"=>\$moteur_latex,
	   "mep=s"=>\$mep_dir,
	   "bareme=s"=>\$bareme,
	   "calage=s"=>\$calage,
	   "out-calage=s"=>\$out_calage,
	   "out-sujet=s"=>\$out_sujet,
	   "out-corrige=s"=>\$out_corrige,
	   "dpi=s"=>\$dpi,
	   "convert-opts=s"=>\$convert_opts,
	   "debug=s"=>\$debug,
	   "progression=s"=>\$progress,
	   "progression-id=s"=>\$progress_id,
	   "prefix=s"=>\$prefix,
	   "n-procs=s"=>\$n_procs,
	   "n-copies=s"=>\$nombre_copies,
	   "raster=s"=>\$moteur_raster,
	   );

set_debug($debug);

debug("AMC-prepare / DEBUG") if($debug);

$queue=AMC::Queue::new('max.procs',$n_procs);

my $avance=AMC::Gui::Avancement::new($progress,'id'=>$progress_id);

my $tex_source=$ARGV[0];

die "Fichier source LaTeX introuvable : $tex_source" if(! -f $tex_source);

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

my $n_erreurs;
my $a_erreurs;
my $analyse_q='';
my @erreurs_msg=();
my %info_vars=();

sub execute {
    my @s=@_;
    my %analyse_data;
    my %titres;

    my $n_run=0;
    my $rerun=0;
    my $format='';

    do {

	$n_run++;
	
	$n_erreurs=0;
	$a_erreurs=0;

	%analyse_data=();
	%titres=();

	@erreurs_msg=();

	debug "%%% Compilation : passe $n_run";

	$cmd_pid=open(EXEC,"-|",@s) or die "Impossible d'executer ".join(' ',@s);

	while(<EXEC>) {
	    if($analyse_q) {
		
		if(/AUTOQCM\[Q=([0-9]+)\]/) { 
		    verifie_q($analyse_data{'q'},$analyse_data{'etu'}.":".$analyse_data{'titre'});
		    $analyse_data{'q'}={};
		    if($analyse_data{'qs'}->{$1}) {
			$a_erreurs++;
			push @erreurs_msg,"ERR: identifiant d'exercice utilis� plusieurs fois : � ".$titres{$1}." � [".$analyse_data{'etu'}."]\n";
		    }
		    $analyse_data{'titre'}=$titres{$1};
		    $analyse_data{'qs'}->{$1}=1;
		}
		if(/AUTOQCM\[ETU=([0-9]+)\]/) {
		    verifie_q($analyse_data{'q'},$analyse_data{'etu'}.":".$analyse_data{'titre'});
		    %analyse_data=('etu'=>$1,'qs'=>{});
		}
		if(/AUTOQCM\[NUM=([0-9]+)=([^\]]+)\]/) {
		    $titres{$1}=$2;
		    $analyse_data{'titres'}->{$2}=1;
		}
		if(/AUTOQCM\[MULT\]/) { 
		    $analyse_data{'q'}->{'mult'}=1;
		}
		if(/AUTOQCM\[INDIC\]/) { 
		    $analyse_data{'q'}->{'indicative'}=1;
		}
		if(/AUTOQCM\[REP=([0-9]+):([BM])\]/) {
		    my $rep="R".$1;
		    if($analyse_data{'q'}->{$rep}) {
			$a_erreurs++;
			push @erreurs_msg,"ERR: num�ro de r�ponse utilis� plusieurs fois : $1 [".$analyse_q{'etu'}.":".$analyse_data{'titre'}."]\n";
		    }
		    $analyse_data{'q'}->{$rep}=($2 eq 'B' ? 1 : 0);
		}
		if(/AUTOQCM\[VAR:([0-9a-zA-Z.-]+)=([^\]]+)\]/) {
		    $info_vars{$1}=$2;
		}
	    }
	    #LaTeX Warning: Label(s) may have changed. Rerun to get cross-references right.
	    $rerun=1 if(/^LaTeX Warning:.*Rerun to get cross-references right/);
	    $format=$1 if(/^Output written on .*\.([a-z]+) \(/);

	    s/AUTOQCM\[.*\]//g;
	    $n_erreurs++ if(/^\!.*\.$/);
	    print $_ if(/^.+$/);
	}
	close(EXEC);
	verifie_q($analyse_data{'q'},$analyse_data{'etu'}.":".$analyse_data{'titre'}) if($analyse_q);
	$cmd_pid='';

    } while($rerun && $n_run<=1);

    # transformation dvi en pdf si besoin...

    $format='dvi' if($moteur_latex eq 'latex');
    $format='pdf' if($moteur_latex eq 'pdflatex');
    $format='pdf' if($moteur_latex eq 'xelatex');

    print "Format de sortie : $format\n";
    debug "Format de sortie : $format\n";

    if($format eq 'dvi') {
	system("dvips","-q",$f_base,"-o",$f_base.".ps");
	print "Erreur dvips : $?\n" if($?);
	system("ps2pdf",$f_base.".ps",$f_base.".pdf");
	print "Erreur ps2pdf : $?\n" if($?);
    }

    print join('',@erreurs_msg);
}

sub verifie_q {
    my ($q,$t)=@_;
    if($q) {
	if(! $q->{'mult'}) {
	    my $oui=0;
	    my $tot=0;
	    for my $i (grep { /^R/ } (keys %$q)) {
		$tot++;
		$oui++ if($q->{$i});
	    }
	    if($oui!=1 && !$q->{'indicative'}) {
		$a_erreurs++;
		push @erreurs_msg,"ERR: $oui/$tot bonnes r�ponses dans une question simple [$t]\n";
	    }
	}
    }
}

$temp_loc=tmpdir();
$temp_dir = tempdir( DIR=>$temp_loc,CLEANUP => 1 );

# reconnaissance mode binaire/decimal :

$binaire='--binaire';

$cmd_pid=open(SCANTEX,$tex_source) or die "Impossible de lire $tex_source : $!";
while(<SCANTEX>) {
    if(/usepackage\[([^\]]+)\]\{autoQCM\}/) {
	my $opts=$1;
	if($opts =~ /\bdecimal\b/) {
	    $binaire="--no-binaire";
	    print "Mode decimal.\n";
	}

    }
}
close(SCANTEX);
$cmd_pid='';

# on se place dans le repertoire du LaTeX
($v,$d,$f_tex)=splitpath($tex_source);
chdir(catpath($v,$d,""));
$f_base=$f_tex;
$f_base =~ s/\.tex$//i;

$prefix=$f_base."-" if(!$prefix);

sub latex_cmd {
    my (%o)=@_;

    return($moteur_latex,
	   "\\nonstopmode"
	   .join('',map { "\\def\\".$_."{".$o{$_}."}"; } (keys %o) )
	   ." \\input{\"$f_tex\"}");
}

if($mode =~ /k/) {
    # CORRECTION INDIVIDUELLE

    execute(latex_cmd(qw/NoWatermarkExterne 1 NoHyperRef 1 CorrigeIndivExterne 1/));
    if($n_erreurs>0) {
	print "ERR: $n_erreurs erreurs lors de la compilation LaTeX (correction)\n";
	exit(1);
    }
    move("$f_base.pdf",($out_corrige ? $out_corrige : $prefix."corrige.pdf"));
}

if($mode =~ /s/) {
    # SUJETS

    my %opts=(qw/NoWatermarkExterne 1 NoHyperRef 1/);
    $opts{'AMCNombreCopies'}=$nombre_copies if($nombre_copies>0);

    # 1) document de calage

    $analyse_q=1;
    execute(latex_cmd(%opts,'CalibrationExterne'=>1));
    $analyse_q='';
    if($n_erreurs>0) {
	print "ERR: $n_erreurs erreurs lors de la compilation LaTeX (calage)\n";
	exit(1);
    }
    exit(1) if($a_erreurs>0);
    move("$f_base.pdf",($out_calage ? $out_calage : $prefix."calage.pdf"));

    # transmission des variables

    print "Variables :\n";
    for my $k (keys %info_vars) {
	print "VAR: $k=".$info_vars{$k}."\n";
    }

    # 2) compilation de la correction

    execute(latex_cmd(%opts,'CorrigeExterne'=>1));
    if($n_erreurs>0) {
	print "ERR: $n_erreurs erreurs lors de la compilation LaTeX (correction)\n";
	exit(1);
    }
    move("$f_base.pdf",($out_corrige ? $out_corrige : $prefix."corrige.pdf"));

    # 3) compilation du sujet

    execute(latex_cmd(%opts,'SujetExterne'=>1));
    if($n_erreurs>0) {
	print "ERR: $n_erreurs erreurs lors de la compilation LaTeX (sujet)\n";
	exit(1);
    }
    move("$f_base.pdf",($out_sujet ? $out_sujet : $prefix."sujet.pdf"));

}

if($mode =~ /m/) {
    # MISE EN PAGE

    # 1) compilation en mode calibration

    print "********** Compilation...\n";

    if(-f $calage) {
	print "Utilisation du fichier de calage $calage\n";
    } else {
	execute(latex_cmd(qw/CalibrationExterne 1 NoHyperRef 1/));
	$calage="$f_base.pdf";
    }

    $avance->progres(0.07);

    # 2) analyse page par page

    print "********** Conversion en bitmap et analyse...\n";

    @pages=();

    $cmd_pid=open(IDCMD,"-|","pdfinfo",$calage)
	or die "Erreur d'identification : $!";
    while(<IDCMD>) {
	if(/^Pages:\s+([0-9]+)/) {
	    my $npages=$1;
	    @pages=(1..$npages);
	}
    }
    close(IDCMD);
    $cmd_pid='';
    
    $avance->progres(0.03);
    
    my $npage=0;
    my $np=1+$#pages;
    for my $p (@pages) {
	$npage++;

	$queue->add_process([with_prog("AMC-raster.pl"),
			     "--moteur",$moteur_raster,
			     "--page",$p,
			     "--dpi",$dpi,
			     $calage,"$temp_dir/page-$npage.ppm",
			     ],
			    [with_prog("AMC-calepage.pl"),
			     "--progression-debut",.4,
			     "--progression",0.9/$np*$progress,
			     "--progression-id",$progress_id,
			     "--debug",debug_file(),
			     $binaire,
			     "--pdf-source",$calage,
			     "--page",$npage,
			     "--dpi",$dpi,
			     "--modele",
			     "--mep",$mep_dir,
			     "$temp_dir/page-$npage.ppm"],
			    ['rm',"$temp_dir/page-$npage.ppm"],
			    );
    }

    $queue->run();
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
    my $etu='';

    my $delta=0;

    $cmd_pid=open(TEX,"-|",latex_cmd(qw/CalibrationExterne 1 NoHyperRef 1/))
	or die "Impossible d'executer latex";
    while(<TEX>) {
	if(/AUTOQCM\[TOTAL=([\s0-9]+)\]/) { 
	    my $t=$1;
	    $t =~ s/\s//g;
	    if($t>0) {
		$delta=1/$t;
	    } else {
		print "*** TOTAL=$t ***\n";
	    }
	}
	if(/AUTOQCM\[Q=([0-9]+)\]/) { 
	    $quest=$1;
	    $rep=''; 
	    $qs{$quest}={};
	}
	if(/AUTOQCM\[ETU=([0-9]+)\]/) {
	    $avance->progres($delta) if($etu ne '');
	    $etu=$1;
	    print "Copie $etu...\n";
	    debug "Copie $etu...\n";
	    $bs{$etu}={};
	}
	if(/AUTOQCM\[NUM=([0-9]+)=([^\]]+)\]/) {
	    $titres{$1}=$2;
	}
	if(/AUTOQCM\[MULT\]/) { 
	    $qs{$quest}->{'multiple'}=1;
	}
	if(/AUTOQCM\[INDIC\]/) { 
	    $qs{$quest}->{'indicative'}=1;
	}
	if(/AUTOQCM\[REP=([0-9]+):([BM])\]/) {
	    $rep=$1;
	    $bs{$etu}->{"$quest.$rep"}={-bonne=>($2 eq 'B' ? 1 : 0)};
	}
	if(/AUTOQCM\[B=([^\]]+)\]/) {
	    $bs{$etu}->{"$quest.$rep"}->{-bareme}=$1;
	}
	if(/AUTOQCM\[BD(S|M)=([^\]]+)\]/) {
	    $bs{'defaut'}->{"$1."}->{-bareme}=$2;
	}
    }
    close(TEX);
    $cmd_pid='';

    debug "Ecriture bareme dans $bareme";

    my $output=new IO::File($bareme,
			    ">:encoding($encodage_interne)");
    if(! $output) {
	die "Impossible d'ouvrir $bareme : $!";
    }

    my $writer = new XML::Writer(OUTPUT=>$output,
				 ENCODING=>$encodage_interne,
				 DATA_MODE=>1,
				 DATA_INDENT=>2);
    $writer->xmlDecl($encodage_interne);

    $writer->startTag('bareme',src=>$f_tex,version=>$VERSION_BAREME);

    for my $etu (keys %bs) {
	$writer->startTag('etudiant',id=>$etu);

	my $bse=$bs{$etu};
	my @q_ids=();
	if($etu eq 'defaut') {
	    @q_ids=('S','M');
	} else {
	    @q_ids=(keys %qs);
	}
	for my $q (@q_ids) {
	    $writer->startTag('question',id=>$q,
			     titre=>$titres{$q},
			     bareme=>$bse->{"$q."}->{-bareme},
			     indicative=>$qs{$q}->{'indicative'},
			     multiple=>$qs{$q}->{'multiple'},
			     );

	    for my $i (keys %$bse) {
		if($i =~ /^$q\.([0-9]+)/) {
		    my $rep=$1;
		    $writer->emptyTag('reponse',
				      id=>$rep,
				      bonne=>$bse->{$i}->{-bonne},
				      bareme=>$bse->{"$i"}->{-bareme},
				      );
		}
	    }
	    $writer->endTag('question');
	}
	$writer->endTag('etudiant');
    }
    $writer->endTag('bareme');
    $writer->end();
    $output->close();
}

$avance->fin();
