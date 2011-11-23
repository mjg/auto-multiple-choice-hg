#! /usr/bin/perl
#
# Copyright (C) 2009-2011 Alexis Bienvenue <paamc@passoire.fr>
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
use Getopt::Long;
use Data::Dumper;

use Gtk2;
use Cairo;

use AMC::Basic;
use AMC::Exec;
use AMC::Gui::Avancement;
use AMC::AssocFile;
use AMC::NamesFile;
use AMC::Data;
use AMC::DataModule::capture qw/:zone :position/;
use encoding 'utf8';

$VERSION_BAREME=2;

my $cr_dir="";
my $rep_projet='';
my $rep_projets='';
my $fichnotes='';
my $fich_bareme='';

my $seuil=0.1;

my $data_dir='';

my $taille_max="1000x1500";
my $qualite_jpg="65";

my $debug='';

my $progress=1;
my $progress_id='';

my $line_width=2;
my @o_symbols=();
my $annote_indicatives='';
my $position='marge';
my $ecart=1;
my $ecart_marge=1.5;
my $pointsize_rel=60;

my $chiffres_significatifs=4;

my $verdict='TOTAL : %S/%M => %s/%m';
my $verdict_question='';

my $font_name='FreeSans';
my $rtl='';
my $test_font_size=100;

my $association='';
my $fich_noms='';
my $noms_encodage='utf-8';

# cle : "a_cocher-cochee"
my %symboles=(
    '0-0'=>{qw/type none/},
    '0-1'=>{qw/type circle color red/},
    '1-0'=>{qw/type mark color red/},
    '1-1'=>{qw/type mark color blue/},
);

@ARGV=unpack_args(@ARGV);

GetOptions("cr=s"=>\$cr_dir,
	   "projet=s",\$rep_projet,
	   "projets=s",\$rep_projets,
	   "data=s"=>\$data_dir,
	   "bareme=s"=>\$fich_bareme,
	   "notes=s"=>\$fichnotes,
	   "debug=s"=>\$debug,
	   "taille-max=s"=>\$taille_max,
	   "qualite=s"=>\$qualite_jpg,
	   "progression=s"=>\$progress,
	   "progression-id=s"=>\$progress_id,
	   "line-width=s"=>\$line_width,
	   "symbols=s"=>\@o_symbols,
	   "indicatives=s"=>\$annote_indicatives,
	   "position=s"=>\$position,
	   "pointsize-nl=s"=>\$pointsize_rel,
	   "ecart=s"=>\$ecart,
	   "ecart-marge=s"=>\$ecart_marge,
	   "ch-sign=s"=>\$chiffres_significatifs,
	   "verdict=s"=>\$verdict,
	   "verdict-question=s"=>\$verdict_question,
	   "fich-assoc=s"=>\$association,
	   "fich-noms=s"=>\$fich_noms,
	   "noms-encodage=s"=>\$noms_encodage,
	   "font=s"=>\$font_name,
	   "rtl!"=>\$rtl,
	   );

set_debug($debug);

for(split(/,/,join(',',@o_symbols))) {
    if(/^([01]-[01]):(none|circle|mark|box)(?:\/([\#a-z0-9]+))?$/) {
	$symboles{$1}={type=>$2,color=>$3};
    } else {
	die "Bad symbol syntax: $_";
    }
}

my $commandes=AMC::Exec::new("AMC-annote");
$commandes->signalise();

$cr_dir=$rep_projet."/cr" if(! $cr_dir);

if(! -d $cr_dir) {
    attention("No CR directory: $cr_dir");
    die "No CR directory: $cr_dir";
}
if(! -f $fichnotes) {
    attention("No marks file: $fichnotes");
    die "No marks file: $fichnotes";
}
if(! -f $fich_bareme) {
    attention("No marking scale file: $fich_bareme");
    die "No marking scale file: $fich_bareme";
}

my $assoc='';
my $lk='';

if($association) {
    $assoc=AMC::AssocFile::new($association);
    if($assoc) {
	$assoc->load();
	$lk=$assoc->get_param('liste_key');
    }
}

my $noms='';

if($fich_noms) {
    $noms=AMC::NamesFile::new($fich_noms,
			      "encodage"=>$noms_encodage);

    debug "Keys in names file: ".join(", ",$noms->heads());
}

# ---

sub color_rgb {
    my ($s)=@_;
    my $col=Gtk2::Gdk::Color->parse($s);
    return($col->red/65535,$col->green/65535,$col->blue/65535);
}

sub format_note {
    my $x=shift;
    if($chiffres_significatifs>0) {
	$x=sprintf("%.*g",$chiffres_significatifs,$x);
    }
    return($x);
}

my $avance=AMC::Gui::Avancement::new($progress,'id'=>$progress_id);

my $data=AMC::Data->new($data_dir);
my $capture=$data->module('capture');

my $bar=XMLin($fich_bareme,ForceArray => 1,KeyAttr=> [ 'id' ]);

if($VERSION_BAREME ne $bar->{'version'}) {
    attention("Marking scale file version (".$bar->{'version'}.")",
	      "is old (here $VERSIN_BAREME) :",
	      "please make marking scale file again...");
    die("Marking scale file version mismatch : $VERSION_BAREME / ".$bar->{'version'});
}


# fichier des notes :

my $notes=eval { XMLin($fichnotes,
		       'ForceArray'=>1,
		       'KeyAttr'=>['id'],
		       ) };

if(!$notes) {
    debug "Error analysing marks file ".$fichnotes."\n";
    return($self);
}

$seuil=$notes->{'seuil'} if($notes->{'seuil'});

#################################

sub milieu_cercle {
    my $zoneid=shift;
    return($capture->sql_row($capture->statement('zoneCenter'),
			     $zoneid,POSITION_BOX));
}

sub cercle_coors {
    my ($context,$zoneid,$color)=@_;
    my ($x,$y)=milieu_cercle($zoneid);
    my $t=sqrt($capture->zone_dist2($zoneid,$x,$y));
    $context->set_source_rgb(color_rgb($color));
    $context->new_path;
    $context->arc($x,$y,$t,0,360);
    $context->stroke;
}

sub croix_coors {
    my ($context,$zoneid,$color)=@_;
    $context->set_source_rgb(color_rgb($color));
    $context->new_path;
    for my $i (1,2) {
	$context->move_to($capture->zone_corner($zoneid,$i));
	$context->line_to($capture->zone_corner($zoneid,$i+2));
    }
    $context->stroke;
}

sub boite_coors {
    my ($context,$zoneid,$color)=@_;
    my @pts="";
    $context->set_source_rgb(color_rgb($color));
    $context->new_path;
    $context->move_to($capture->zone_corner($zoneid,1));
    for my $i (2..4) {
	$context->line_to($capture->zone_corner($zoneid,$i));
    }
    $context->close_path;
    $context->stroke;
}

my $delta=1;

$capture->begin_read_transaction;

my @pages=@{$capture->dbh
	      ->selectall_arrayref($capture->statement('pages'),
				   {Slice => {}})};

$capture->end_transaction;

$delta=1/(1+$#pages) if($#pages>=0);

 PAGE: for my $p (@pages) {
  my @spc=map { $p->{$_} } (qw/student page copy/);

  debug "Analyzing ".pageids_string(@spc);

  my $scan=$p->{'src'};

  debug "Scan file: $scan";

  if($rep_projet) {
    $scan=proj2abs({'%PROJET',$rep_projet,
		    '%PROJETS',$rep_projets,
		    '%HOME'=>$ENV{'HOME'},
		   },
		   $scan);
  }

  my $scan_f=$scan;

  $scan_f =~ s/\[[0-9]+\]$//;

  if(-f $scan_f) {

    # ONE SCAN FILE

    # read scan file (converting to PNG)
    debug "Reading $scan";
    open(CONV,"-|",magick_module("convert"),$scan,"png:-");
    my $surface = Cairo::ImageSurface
      ->create_from_png_stream(
			       sub {
				 my ($cb_data,$length)=@_;
				 read CONV,$data,$length;
				 return($data);
			       });
    close(CONV);

    my $context = Cairo::Context->create ($surface);
    $context->set_line_width($line_width);

    my $layout=Pango::Cairo::create_layout($context);

    # adjusts text size...
    my $l0=Pango::Cairo::create_layout($context);
    $l0->set_font_description (Pango::FontDescription->from_string ($font_name.' '.$test_font_size));
    $l0->set_text('H');
    my ($text_x,$text_y)=$l0->get_pixel_size();
    my $page_width=$surface->get_width;
    my $page_height=$surface->get_height;
    debug "Scan height: $page_height";
    my $target_y=$page_height/$pointsize_rel;
    debug "Target TY: $target_y";
    my $font_size=int($test_font_size*$target_y/$text_y);
    debug "Font size: $font_size";

    $layout->set_font_description (Pango::FontDescription->from_string ($font_name.' '.$font_size));
    $layout->set_text('H');
    ($text_x,$text_y)=$layout->get_pixel_size();

    my ($x_ppem, $y_ppem, $ascender, $descender, $width, $height, $max_advance);

    print "Annotating $scan...\n";

    my $idf=pageids_string(@spc,'path'=>1);

    my %question=();

    my $ne=$notes->{'copie'}->{studentids_string(@spc[0,2])};

    if(!$ne) {
      print "*** no marks for copy ".studentids_string(@spc[0,2])." ***\n";
      debug "No marks found ! Copy=".studentids_string(@spc[0,2]);
      next PAGE;
    }

    $capture->begin_read_transaction;

    # print global mark and name on the page

    if($p->{'page'}==1 || $capture->zones_count(@spc,ZONE_NAME)) {
      my $t=$ne->{'total'}->[0];
      my $text=$verdict;

      $text =~ s/\%[S]/format_note($t->{'total'})/ge;
      $text =~ s/\%[M]/format_note($t->{'max'})/ge;
      $text =~ s/\%[s]/format_note($t->{'note'})/ge;
      $text =~ s/\%[m]/format_note($notes->{'notemax'})/ge;

      if($assoc && $noms) {
	my $i=$assoc->effectif($etud);
	my $n;

	debug "Association -> ID=$i";

	if($i) {
	  debug "Name found";
	  ($n)=$noms->data($lk,$i);
	  if($n) {
	    $text=$noms->substitute($n,$text,'prefix'=>'%');
	  }
	}
      }

      $layout->set_text($text);
      $context->set_source_rgb(color_rgb('red'));
      if($rtl) {
	my ($tx,$ty)=$layout->get_pixel_size;
	$context->move_to($page_width-$text_x-$tx,$text_y*.7);
      } else {
	$context->move_to($text_x,$text_y*.7);
      }
      Pango::Cairo::show_layout($context,$layout);
    }

    #########################################
    # signs around each box

    my $sth=$capture->statement('pageZones');
    $sth->execute(@spc,ZONE_BOX);
  BOX: while(my $b=$sth->fetchrow_hashref) {

      my $q=$b->{'id_a'};
      my $r=$b->{'id_b'};
      my $indic=$bar->{'etudiant'}->{$p->{'student'}}
	->{'question'}->{$q}->{'indicative'};

      next BOX if($indic && !$annote_indicatives);

      # to be ticked?
      my $bonne=($bar->{'etudiant'}->{$p->{'student'}}->{'question'}->{$q}->{'reponse'}->{$r}->{'bonne'} ? 1 : 0);

      # ticked on this scan?
      my $cochee=$capture->ticked($p->{'student'},$p->{'copy'},
				  $q,$r,$seuil);

      debug "Q=$q R=$r $bonne-$cochee";

      my $sy=$symboles{"$bonne-$cochee"};

      if($sy->{type} eq 'circle') {
	cercle_coors($context,$b->{'zoneid'},$sy->{color});
      } elsif($sy->{type} eq 'mark') {
	croix_coors($context,$b->{'zoneid'},$sy->{color});
      } elsif($sy->{type} eq 'box') {
	boite_coors($context,$b->{'zoneid'},$sy->{color});
      } elsif($sy->{type} eq 'none') {
      } else {
	debug "Unknown symbol type ($bonne-$cochee): $sy->{type}";
      }

      # pour avoir la moyenne des coors pour marquer la note de
      # la question

      $question{$q}={} if(!$question{$q});
      my @mil=milieu_cercle($b->{'zoneid'});
      $question{$q}->{'n'}++;
      $question{$q}->{'x'}=$mil[0] 
	if((!$question{$q}->{'x'}) || ($mil[0]<$question{$q}->{'x'}));
      $question{$q}->{'xmax'}=$mil[0] 
	if((!$question{$q}->{'xmax'}) || ($mil[0]>$question{$q}->{'xmax'}));
      $question{$q}->{'y'}+=$mil[1];
    }

    #########################################
    # write questions scores

    if($position ne 'none') {
    QUEST: for my $q (keys %question) {
	next QUEST if($bar->{'etudiant'}->{$etud}->{'question'}->{$q}->{'indicative'});
	my $x;

	my $nq=$ne->{'question'}->{$bar->{'etudiant'}->{$etud}->{'question'}->{$q}->{'titre'}};

	my $text=$verdict_question;

	$text =~ s/\%[S]/$nq->{'note'}/g;
	$text =~ s/\%[M]/$nq->{'max'}/g;
	$text =~ s/\%[s]/format_note($nq->{'note'})/ge;
	$text =~ s/\%[m]/format_note($nq->{'max'})/ge;

	my $te=eval($text);
	if($@) {
	  debug "Annotation: $text";
	  debug "Evaluation error $@";
	} else {
	  $text=$te;
	}

	$layout->set_text($text);
	my ($tx,$ty)=$layout->get_pixel_size;
	if($position eq 'marge') {
	  if($rtl) {
	    $x=$page_width-$ecart_marge*$text_x-$tx;
	  } else {
	    $x=$ecart_marge*$text_x;
	  }
	} elsif($position eq 'case') {
	  if($rtl) {
	    $x=$question{$q}->{'xmax'} + $ecart*$text_x ;
	  } else {
	    $x=$question{$q}->{'x'} - $ecart*$text_x - $tx;
	  }
	} else {
	  debug "Annotation : position invalide : $position";
	  $x=$text_x;
	}

	# moyenne des y des cases de la question
	my $y=$question{$q}->{'y'}/$question{$q}->{'n'}-$ty/2;

	$context->set_source_rgb(color_rgb('red'));
	$context->move_to($x,$y);
	Pango::Cairo::show_layout($context,$layout);
      }
    }

    $capture->end_transaction;

    # WRITE TO FILE

    $context->show_page;

    my $out_file="page-$idf.jpg";

    debug "Saving annotated scan to $cr_dir/corrections/jpg/$out_file";

    open(CONV,"|-",magick_module("convert"),"png:-",
	 "-quality",$qualite_jpg,"-geometry",$taille_max,
	 "$cr_dir/corrections/jpg/$out_file");
    $surface->write_to_png_stream(
				  sub {
				    my ($cb_data,$data)=@_;
				    print CONV $data;
				  });
    close(CONV);

    $capture->begin_transaction;
    $capture->set_annotated(@spc,$out_file);
    $capture->end_transaction;

  } else {
    print "*** no scan $scan_f ***\n";
    debug "No scan: $scan_f";
  }

  $avance->progres($delta);
}

$avance->fin();

