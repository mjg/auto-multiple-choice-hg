#! /usr/bin/perl
#
# Copyright (C) 2008-2011 Alexis Bienvenue <paamc@passoire.fr>
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

use XML::Simple;
use IO::File;
use XML::Writer;
use Getopt::Long;
use POSIX qw(ceil floor);
use AMC::Basic;
use AMC::Gui::Avancement;
use AMC::Scoring;
use AMC::Data;

use encoding 'utf8';

my $association="-";
my $seuil=0.1;
my $annotation_copies='';

my $note_plancher='';
my $note_parfaite=20;
my $grain='0.5';
my $arrondi='';
my $delimiteur=',';
my $encodage_interne='UTF-8';
my $data_dir='';

my $postcorrect='';

my $progres=1;
my $plafond=1;
my $progres_id='';

my $debug='';

GetOptions("data=s"=>\$data_dir,
	   "seuil=s"=>\$seuil,
	   "debug=s"=>\$debug,
	   "copies!"=>\$annotation_copies,
	   "grain=s"=>\$grain,
	   "arrondi=s"=>\$type_arrondi,
	   "notemax=s"=>\$note_parfaite,
	   "plafond!"=>\$plafond,
	   "notemin=s"=>\$note_plancher,
	   "postcorrect=s"=>\$postcorrect,
	   "encodage-interne=s"=>\$encodage_interne,
	   "progression-id=s"=>\$progres_id,
	   "progression=s"=>\$progres,
	   );

set_debug($debug);

# fixes decimal separator ',' potential problem, replacing it with a
# dot.
for my $x (\$grain,\$note_plancher,\$note_parfaite) {
    $$x =~ s/,/./;
    $$x =~ s/\s+//;
}

# Implements the different possible rounding schemes.

sub arrondi_inf {
    my $x=shift;
    return(floor($x));
}

sub arrondi_central {
    my $x=shift;
    return(floor($x+0.5));
}

sub arrondi_sup {
    my $x=shift;
    return(ceil($x));
}

my %fonction_arrondi=('i'=>\&arrondi_inf,'n'=>\&arrondi_central,'s'=>\&arrondi_sup);

if($type_arrondi) {
    for my $k (keys %fonction_arrondi) {
	if($type_arrondi =~ /^$k/i) {
	    $arrondi=$fonction_arrondi{$k};
	}
    }
}

if(! -d $data_dir) {
    attention("No DATA directory: $data_dir");
    die "No DATA directory: $data_dir";
}

if($grain<=0) {
    $grain=1;
    $arrondi='';
    $type_arrondi='';
    debug("Nonpositive grain: rounding off");
}

my $avance=AMC::Gui::Avancement::new($progres,'id'=>$progres_id);

my $data=AMC::Data->new($data_dir);
my $capture=$data->module('capture');
my $scoring=$data->module('scoring');

my $bar=AMC::Scoring::new('onerror'=>'die',
			  'data'=>$data,
			  'seuil'=>$seuil);

$avance->progres(0.05);

$data->begin_transaction;

$scoring->clear_score;
$scoring->variable('seuil',$seuil);
$scoring->variable('notemin',$note_plancher);
$scoring->variable('notemax',$note_parfaite);
$scoring->variable('plafond',$plafond);
$scoring->variable('arrondi',$type_arrondi);
$scoring->variable('grain',$grain);
$scoring->variable('postcorrect',$postcorrect);

my $somme_notes=0;
my $n_notes=0;

my @a_calculer=@{$capture->dbh
		   ->selectall_arrayref($capture->statement('studentCopies'),{})};

my $delta=0.19;
$delta/=(1+$#a_calculer) if($#a_calculer>=0);

# postcorrect mode?
if($postcorrect) {
    $scoring->postcorrect($postcorrect);
}

for my $sc (@a_calculer) {
  my $student=$sc->[0];
  my $student_strategy=$scoring->unalias($student);

  debug "MARK: --- SHEET ".studentids_string(@$sc);

  my $total=0;
  my $max_i=0;
  my %codes=();

  for my $q ($scoring->student_questions($student_strategy)) {
    ($xx,$raison,$keys)=$bar->score_question(@$sc,$q);
    ($notemax)=$bar->score_max_question($student_strategy,$q);

    my $tit=$scoring->question_title($q);

    debug "MARK: QUESTION $q TITLE $tit";

    if ($tit =~ /^(.*)\.([0-9]+)$/) {
      $codes{$1}->{$2}=$xx;
    }

    if ($scoring->indicative($student_strategy,$q)) {
      $notemax=1;
    } else {
      $total+=$xx;
      $max_i+=$notemax;
    }

    $scoring->new_score(@$sc,$q,$xx,$notemax,$raison);
  }

  # Final mark --

  # total qui faut pour avoir le max
  $max_i=$bar->main_tag('SUF',$max_i,$student_strategy);
  if ($max_i<=0) {
    debug "Warning: Nonpositive value for MAX.";
    $max_i=1;
  }

  # application du grain et de la note max
  my $x;

  if ($note_parfaite>0) {
    $x=$note_parfaite/$grain*$total/$max_i;
  } else {
    $x=$total/$grain;
  }
  $x=&$arrondi($x) if($arrondi);
  $x*=$grain;

  $x=$note_parfaite if($note_parfaite>0 && $plafond && $x>$note_parfaite);

  # plancher

  if ($note_plancher ne '' && $note_plancher !~ /[a-z]/i) {
    $x=$note_plancher if($x<$note_plancher);
  }

  #--

  $n_notes++;
  $somme_notes+=$x;

  $scoring->new_mark(@$sc,$total,$max,$x);

  for my $k (keys %codes) {
    my @i=(keys %{$codes{$k}});
    if ($#i>0) {
      my $v=join('',map { $codes{$k}->{$_} }
		 sort { $b <=> $a } (@i));
      $scoring->new_code(@$sc,$k,$v);
    }
  }

  $avance->progres($delta);
}

$data->end_transaction;

$avance->fin();
