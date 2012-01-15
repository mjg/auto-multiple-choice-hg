#! /usr/bin/perl
#
# Copyright (C) 2008-2012 Alexis Bienvenue <paamc@passoire.fr>
#
# This file is part of Auto-Multiple-Choice
#
# Auto-Multiple-Choice is free software: you can redistribute it
# and/or modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation, either version 2 of
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

use Getopt::Long;
use Encode;
use Unicode::Normalize;
use XML::Simple;

use AMC::Basic;
use AMC::Exec;
use AMC::Gui::Avancement;
use AMC::NamesFile;
use AMC::Data;
use AMC::DataModule::report ':const';

use File::Spec::Functions qw/tmpdir/;
use File::Temp qw/ tempfile tempdir /;
use File::Copy;

my $debug='';

my $commandes=AMC::Exec::new('AMC-regroupe');
$commandes->signalise();

################################################################

my $projet_dir='';
my $jpgdir='';
my $pdfdir='';
my $modele="";
my $progress=1;
my $progress_id='';
my $fich_noms='';
my $noms_encodage='utf-8';
my $an_saved='';
my $data_dir='';
my $single_output='';
my $id_file='';
my $compose='';

my $moteur_latex='pdflatex';
my $tex_src='';

my $debug='';
my $nombre_copies=0;

my $sujet='';
my $dest_size_x=21/2.54;
my $dest_size_y=29.7/2.54;

GetOptions("projet=s"=>\$projet_dir,
	   "cr=s"=>\$cr,
	   "n-copies=s"=>\$nombre_copies,
	   "sujet=s"=>\$sujet,
	   "data=s"=>\$data_dir,
	   "tex-src=s"=>\$tex_src,
	   "with=s"=>\$moteur_latex,
	   "modele=s"=>\$modele,
	   "fich-noms=s"=>\$fich_noms,
	   "noms-encodage=s"=>\$noms_encodage,
	   "progression=s"=>\$progress,
	   "progression-id=s"=>\$progress_id,
	   "compose!"=>\$compose,
	   "id-file=s"=>\$id_file,
	   "single-output=s"=>\$single_output,
	   "debug=s"=>\$debug,
	   );

set_debug($debug);

$temp_dir = tempdir( DIR=>tmpdir(),
		     CLEANUP => (!get_debug()) );

debug "dir = $temp_dir";

$cr=$projet_dir."/cr" if($projet_dir && !$cr);
$data_dir=$projet_dir."/data" if($projet_dir && !$data_dir);

my $correc_indiv="$temp_dir/correc.pdf";

my $jpgdir="$cr/corrections/jpg";
my $pdfdir="$cr/corrections/pdf";

my $avance=AMC::Gui::Avancement::new($progress * ($single_output ? 0.8 : 1),
				     'id'=>$progress_id);

my $noms='';

if($fich_noms) {
    $noms=AMC::NamesFile::new($fich_noms,
			      "encodage"=>$noms_encodage);

    debug "Keys in names file: ".join(", ",$noms->heads());
}

# check_correc prepares the corrected answer sheet for all
# students. This file is used when option --compose is on, to take
# sheets when the scaned sheet is not present (for example if there
# are sheets with no answer boxes on it). This can be very usefull to
# produce a complete annotated answer sheet with subject *and* answers
# when separate answer sheet layout is used.

my $correc_indiv_ok='';

sub check_correc {
    if(!$correc_indiv_ok) {
	$correc_indiv_ok=1;

	debug "Making individual corrected sheet...";

	$commandes->execute("auto-multiple-choice","prepare",
			    "--n-copies",$nombre_copies,
			    "--with",$moteur_latex,
			    "--mode","k",
			    "--out-corrige",$correc_indiv,
			    "--debug",debug_file(),
			    $tex_src);
    }
}

# gets the dimensions of the page from the subject, if any.

if($sujet) {
    if(-f $sujet) {
	my @c=("identify","-format","%w,%h",$sujet.'[0]');
	debug "IDENT << ".join(' ',@c);
	if(open(IDENT,"-|",@c)) {
	    while(<IDENT>) {
		if(/^([0-9.]+),([0-9.]+)$/) {
		    debug "Size from subject : $1 x $2";
		    $dest_size_x=$1/72;
		    $dest_size_y=$2/72;
		}
	    }
	    close IDENT;
	} else {
	    debug "Error execing: $!";
	}
    } else {
	debug "No subject: $sujet";
    }
}

# Convert image to PDF using the right page dimensions

sub write_pdf {
    my ($img,$file)=@_;

    my ($h,$w)=$img->Get('height','width');
    my $d_x=$w/$dest_size_x;
    my $d_y=$h/$dest_size_y;
    my $dens=($d_x > $d_y ? $d_x : $d_y);

    debug "GEOMETRY : $w x $h\n";
    debug "DENSITY : $d_x x $d_y --> $dens\n";
    debug "destination: $file";

    my $w=$img->Write('filename'=>$file,
		      'page'=>($dens*$dest_size_x).'x'.($dens*$dest_size_y),
		      'adjoin'=>'True','units'=>'PixelsPerInch',
		      'compression'=>'jpeg','density'=>$dens.'x'.$dens);

    if($w) {
	print "Write error: $w\n";
	debug "Write error: $w\n";
	return(0);
    } else {
	return(1);
    }
}

###################################################################
# Connect to the database

my $data=AMC::Data->new($data_dir);
my $layout=$data->module('layout');
my $capture=$data->module('capture');
my $assoc=$data->module('association');
my $report=$data->module('report');

$lk=$assoc->variable_transaction('key_in_list');

###################################################################
# Get student/copy numbers to process.

my @students=();

# a) first case: these numbers are given by --id-file option

if($id_file) {

    open(NUMS,$id_file);
    while(<NUMS>) {
        if(/^([0-9]+):([0-9]+)$/) {
	  push @students,[$1,$2];
	} elsif(/^([0-9]+)$/) {
	  push @students,[$1,0];
	}
    }
    close(NUMS);

}

# b) second case: guess from data capture data

else {
  $capture->begin_read_transaction;
  @students=@{$capture->dbh
		->selectall_arrayref($capture->statement('studentCopies'))};
  $capture->end_transaction;
}

my $n_copies=1+$#students;

if($n_copies<=0) {
    debug "No sheets to group.";
    exit 0;
}

###################################################################
# Processing

# Stacks of PDF pages comming from the PDF corrected answer sheet or
# the PPM annotated pages

my $stk_ii;
my @stk_pages=();
my $stk_type;

sub stk_begin {
    $stk_ii=1;
    $stk_file="$temp_dir/$stk_ii.pdf";
    $stk_type='';
    @stk_pages=();
    stk_pdf_begin();
    stk_ppm_begin();
}

sub stk_push {
    push @stk_pages,$stk_file;
    $stk_ii++;
    $stk_file="$temp_dir/$stk_ii.pdf";
}

sub stk_go {
    stk_pdf_go() if($stk_type eq 'pdf');
    stk_ppm_go() if($stk_type eq 'ppm');
    $stk_type='';
}

sub stk_add {
    my ($t)=@_;
    if($stk_type ne $t) {
	stk_go();
	$stk_type=$t;
    }
}

# pdf

my @stk_pdf_pages=();

sub stk_pdf_begin {
    @stk_pdf_pages=();
}

sub stk_pdf_add {
    stk_add('pdf');
    push @stk_pdf_pages,@_;
}

sub stk_pdf_go {
    debug "Page(s) ".join(',',@stk_pdf_pages)." form corrected sheet";

    check_correc();

    my @ps=sort { $a <=> $b } @stk_pdf_pages;
    my @morceaux=();
    my $mii=0;
    while(@ps) {
	my $debut=shift @ps;
	my $fin=$debut;
	while($ps[0]==$fin+1) { $fin=shift @ps; }

	$mii++;
	my $un_morceau="$temp_dir/m.$mii.pdf";

	debug "Slice $debut-$fin to $un_morceau";

	$commandes->execute("gs","-dBATCH","-dNOPAUSE","-q",
			    "-sDEVICE=pdfwrite",
			    "-sOutputFile=$un_morceau",
			    "-dFirstPage=$debut","-dLastPage=$fin",
			    $correc_indiv);
	push @morceaux,$un_morceau;
    }

    if($#morceaux==0) {
	debug "Moving single slice to destination $stk_file";
	move($morceaux[0],$stk_file);
    } else {
	debug "Joining slices...";
	$commandes->execute("gs","-dBATCH","-dNOPAUSE","-q",
			    "-sDEVICE=pdfwrite",
			    "-sOutputFile=$stk_file",
			    @morceaux);
	unlink @morceaux;
    }

    stk_push();

    stk_pdf_begin();
}

# ppm

my $stk_ppm_im;

sub stk_ppm_begin {
    $stk_ppm_im=magick_perl_module()->new();
}

sub stk_ppm_add {
    stk_add('ppm');
    $stk_ppm_im->ReadImage(shift);
}

sub stk_ppm_go {
    stk_push() if(write_pdf($stk_ppm_im,$stk_file));
    stk_ppm_begin();
}

sub process_output {
    my ($file)=@_;

    stk_go();

    if($#stk_pages==0) {
	debug "Move $stk_pages[0] to $file";
	move($stk_pages[0],$file);
    } elsif($#stk_pages>0) {
	$commandes->execute("gs","-dBATCH","-dNOPAUSE","-q",
			    "-sDEVICE=pdfwrite",
			    "-sOutputFile=$file",@stk_pages);
    }
}

###################################################################
# Going through the sheets to process...

stk_begin() if($single_output);

my $type=($single_output ? REPORT_SINGLE_ANNOTATED_PDF 
	  : REPORT_ANNOTATED_PDF );

$data->begin_transaction('rDELS');
$report->delete_student_type($type);
$data->end_transaction('rDELS');

for my $e (@students) {
  print "Pages for ID=".studentids_string(@$e)."...\n";

  my $f=$modele;

  if(!$single_output) {
    $f='(N)-(ID)' if(!$f);
    $f.='.pdf' if($f !~ /\.pdf$/i);

    my $ex;
    if($e->[1]) {
      $ex=sprintf("%04d:%04d",@$e);
    } else {
      $ex=sprintf("%04d",$e->[0]);
    }
    $f =~ s/\(N\)/$ex/gi;

    if($assoc && $noms) {
      $data->begin_read_transaction('rAGN');
      my $i=$assoc->get_real(@$e);
      $data->end_transaction('rAGN');
      my $nom='XXX';
      my $n;

      debug "Association -> ID=$i";

      if($i) {
	debug "Name found";
	($n)=$noms->data($lk,$i);
	if($n) {
	  $f=$noms->substitute($n,$f);
	}
      }

    } else {
      $f =~ s/-?\(ID\)//gi;
    }

    # no accents and special characters in filename
    $f=NFKD($f);
    $f =~ s/\pM//og;

    # no whitespaces in filename
    $f =~ s/\s+/_/g;

    $data->begin_transaction('rSST');
    $f=$report->free_student_report($type,$f);
    $report->set_student_report($type,@$e,$f,'now');
    $data->end_transaction('rSST');

    $f="$pdfdir/$f";
    debug "Dest file: $f";

    stk_begin();
  }

  $data->begin_read_transaction('rSDP');
  my $pp=$capture->get_student_pages(@$e);
  $data->end_transaction('rSDP');

  for my $p (@$pp) {

    my $f_j0=$p->{'annotated'};
    my $f_j;

    if($f_j0) {
      $f_j="$jpgdir/$f_j0";
      if(!-f $f_j) {
	print "Annotated page $f_j not found\n";
	debug("Annotated page $f_j not found");
	$f_j='';
      }
    }

    if($f_j) {
      # correction JPG presente : on transforme en PDF

      debug "Page ".studentids_string(@$e)."/$p->{'page'} annotated ($f_j)";
      stk_ppm_add($f_j);

    } elsif($compose) {
      # pas de JPG annote : on prend la page corrigee

      debug "Page ".studentids_string(@$e)."/$p->{'page'} from corrected sheet";
      stk_pdf_add($p->{'subjectpage'});
    }
  }

  if(!$single_output) {
    process_output($f);
  }

  $avance->progres(1/$n_copies);
}

if($single_output) {
  process_output($single_output);
  $data->begin_transaction('rSST');
  $report->set_student_report($type,0,0,$single_output,'now');
  $data->end_transaction('rSST');
}

$avance->fin();
