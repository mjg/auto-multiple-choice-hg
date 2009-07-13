#! /usr/bin/perl -w
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

use Getopt::Long;

use Gtk2 -init;
use Gtk2::GladeXML;
use XML::Simple;
use IO::File;
use IO::Select;
use File::Spec::Functions qw/splitpath catpath splitdir catdir catfile rel2abs tmpdir/;
use File::Temp;
use File::Copy;
use Time::localtime;
use Encode;
use I18N::Langinfo qw(langinfo CODESET);

use Net::CUPS;
use Net::CUPS::PPD;

use AMC::Basic;
use AMC::MEPList;
use AMC::ANList;
use AMC::Gui::Manuel;
use AMC::Gui::Association;
use AMC::Gui::Commande;

use Data::Dumper;

use constant {
    DOC_TITRE => 0,
    DOC_MAJ => 1,

    MEP_PAGE => 0,
    MEP_ID => 1,
    MEP_MAJ => 2,

    DIAG_ID => 0,
    DIAG_ID_BACK => 1,
    DIAG_MAJ => 2,
    DIAG_EQM => 3,
    DIAG_EQM_BACK => 4,
    DIAG_DELTA => 5,
    DIAG_DELTA_BACK => 6,

    INCONNU_SCAN => 0,
    INCONNU_ID => 1,

    PROJ_NOM => 0,
    PROJ_ICO => 1,

    CORREC_ID => 0,
    CORREC_MAJ => 1,
    CORREC_FILE => 2,

    COMBO_ID => 1,
    COMBO_TEXT => 0,

    COPIE_N => 0,

    LISTE_TXT =>0,
};

my $debug=0;

GetOptions("debug!"=>\$debug,
	   );

print "DEBUG MODE\n" if($debug);

($e_volume,$e_vdirectories,undef) = splitpath( rel2abs($0) );
sub with_prog {
    my $fich=shift;
    return(catpath($e_volume,$e_vdirectories,$fich));
}

my $mep_list;
my $an_list;

my $glade_xml=__FILE__;
$glade_xml =~ s/\.p[ml]$/.glade/i;

my $o_file=Glib::get_home_dir().'/.AMC.xml';

#chomp(my $encodage_systeme=eval { `locale charmap` });
my $encodage_systeme=langinfo(CODESET());
$encodage_systeme='UTF-8' if(!$encodage_systeme);

my %w=();
my %o_defaut=('pdf_viewer'=>['commande',
			     'evince','acroread','gpdf','xpdf',
			     ],
	      'img_viewer'=>['commande',
			     'eog',
			     ],
	      'dat_viewer'=>['commande',
			     'oocalc','gnumeric',
			     ],
	      'xml_viewer'=>['commande',
			     'gedit','kedit','mousepad',
			     ],
	      'tex_editor'=>['commande',
			     'texmaker','kile','emacs','gedit','mousepad',
			     ],
	      'html_browser'=>['commande',
			       'sensible-browser %u','firefox %u','galeon %u','konqueror %u','dillo %u',
			       ],
	      'dir_opener'=>['commande',
			     'nautilus --no-desktop file://%d',
			     'Thunar %d',
			     'konqueror file://%d',
			     ],
	      'print_command_pdf'=>['commande',
				    'cupsdoprint %f','lpr %f',
				    ],
	      'rep_projets'=>Glib::get_home_dir().'/Projets-QCM',
	      'rep_modeles'=>'/usr/share/doc/auto-multiple-choice/exemples',
	      'seuil_eqm'=>3.0,
	      'seuil_sens'=>8.0,
	      'saisie_dpi'=>150,
	      'n_procs'=>0,
	      'delimiteur_decimal'=>',',
	      'encodage_liste'=>'',
	      'encodage_interne'=>'UTF-8',
	      'encodage_csv'=>'',
	      'encodage_latex'=>'',
	      'taille_max_correction'=>'1000x1500',
	      'qualite_correction'=>'150',
	      'conserve_taille'=>1,
	      'methode_impression'=>'CUPS',
	      'imprimante'=>'',
	      'options_impression'=>{'sides'=>'two-sided-long-edge',
				     'number-up'=>1,
				     },
	      'manuel_image_type'=>'xpm',
	      );

my %projet_defaut=('texsrc'=>'',
		   'mep'=>'mep',
		   'cr'=>'cr',
		   'listeetudiants'=>'',
		   'notes'=>'notes.xml',
		   'seuil'=>0.1,
		   'maj_bareme'=>1,
		   'fichbareme'=>'bareme.xml',
		   'docs'=>['sujet.pdf','corrige.pdf','calage.pdf'],
		   
		   'modele_regroupement'=>'',

		   'note_max'=>20,
		   'note_grain'=>"0,5",
		   'note_arrondi'=>'inf',

		   'liste_key'=>'',
		   'assoc_code'=>'',
	    
		   'modifie'=>1,
		   
		   );

my $mep_saved='mep.storable';
my $an_saved='an.storable';

# peut-on acceder a cette commande par exec ?
sub commande_accessible {
    my $c=shift;
    $c =~ s/(?<=[^\s])\s.*//;
    $c =~ s/^\s+//;
    if($c =~ /^\//) {
	return (-x $c);
    } else {
	$ok='';
	for (split(/:/,$ENV{'PATH'})) {
	    $ok=1 if(-x "$_/$c");
	}
	return($ok);
    }
}

# toutes les commandes prevues sont-elles accessibles ? Si non, on
# avertit l'utilisateur

sub test_commandes {
    my @pasbon=();
    for my $c (grep { /_(viewer|editor|opener)$/ } keys(%o)) {
	my $nc=$o{$c};
	$nc =~ s/\s.*//;
	push @pasbon,$nc if(!commande_accessible($nc));
    }
    if(@pasbon) {
	my $dialog = Gtk2::MessageDialog->new_with_markup ($w{'main_window'},
					       'destroy-with-parent',
					       'warning', # message type
					       'ok', # which set of buttons?
					       "Certaines commandes pr�vues pour l'ouverture de documents ne sont pas accessibles : ".join(", ",map { "<b>$_</b>"; } @pasbon).". V�rifiez que les commandes sont les bonnes et que les programmes correspondants sont bien install�s. Vous pouvez aussi modifier les commandes � utiliser en s�lectionnant Pr�f�rences dans le menu �dition.");
	$dialog->run;
	$dialog->destroy;
    }
}

# lecture options ...

my %o=();

if(-r $o_file) {
    %o=%{XMLin($o_file,SuppressEmpty => '')};
}

for my $k (keys %o_defaut) {
    if(! exists($o{$k})) {
	if(ref($o_defaut{$k}) eq 'ARRAY') {
	    my ($type,@valeurs)=@{$o_defaut{$k}};
	    if($type eq 'commande') {
	      UC: for my $c (@valeurs) {
		  if(commande_accessible($c)) {
		      $o{$k}=$c;
		      last UC;
		  }
	      }
		$o{$k}=$valeurs[0] if(!$o{$k});
	    } else {
		print STDERR "ERR: Type d'option inconnu : $type\n";
	    }
	} elsif(ref($o_defaut{$k}) eq 'HASH') {
	    $o{$k}={%{$o_defaut{$k}}};
	} else {
	    $o{$k}=$o_defaut{$k};
	    $o{$k}=$encodage_systeme if($k =~ /^encodage_/ && !$o{$k});
	}
	print "Nouveau parametre global : $k = $o{$k}\n" if($o{$k});
    }
    $o{'modifie'}=0;

    # XML::Writer utilise dans Association.pm n'accepte rien d'autre...
    if($o{'encodage_interne'} ne 'UTF-8') {
	$o{'encodage_interne'}='UTF-8';
	$o{'modifie'}=1;
    }
}

###

my %projet=();

sub id2file {
    my ($id,$prefix,$extension)=(@_);
    $id =~ s/\+//g;
    $id =~ s/\//-/g;
    return(localise($projet{'cr'})."/$prefix-$id.$extension");
}

sub localise {
    my $f=shift;
    if(defined($f)) {
	return($f =~ /^\// ? $f : $o{'rep_projets'}."/".$projet{'nom'}."/$f");
    } else {
	return('');
    }
}

sub is_local {
    my ($f,$proj)=@_;
    my $prefix=$o{'rep_projets'}."/";
    $prefix .= $projet{'nom'}."/" if($proj);
    if(defined($f)) {
	return($f !~ /^\// || $f =~ /^$prefix/);
    } else {
	return('');
    }
}

sub fich_options {
    my $nom=shift;
    return $o{'rep_projets'}."/$nom/options.xml";
}

$gui=Gtk2::GladeXML->new($glade_xml,'main_window');

for(qw/onglets_projet preparation_etats documents_tree main_window mep_tree edition_latex
    onglet_notation onglet_saisie
    log_general commande avancement
    liste diag_tree inconnu_tree diag_result
    maj_bareme correc_tree correction_result regroupement_corriges/) {
    $w{$_}=$gui->get_widget($_);
}

$w{'commande'}->hide();

### modele documents

$doc_store = Gtk2::ListStore->new ('Glib::String', 
				   'Glib::String');

my @doc_ligne=($doc_store->append,$doc_store->append,$doc_store->append);

$doc_store->set($doc_ligne[0],DOC_TITRE,'sujet',DOC_MAJ,'');
$doc_store->set($doc_ligne[1],DOC_TITRE,'corrig�',DOC_MAJ,'');
$doc_store->set($doc_ligne[2],DOC_TITRE,'calage',DOC_MAJ,'');
$w{'documents_tree'}->set_model($doc_store);

my $renderer;
my $column;

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("document",
						     $renderer,
						     text=> DOC_TITRE);
$w{'documents_tree'}->append_column ($column);

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("�tat",
						     $renderer,
						     text=> DOC_MAJ);
$w{'documents_tree'}->append_column ($column);

### modele MEP

$mep_store = Gtk2::ListStore->new ('Glib::String',
				   'Glib::String', 
				   'Glib::String');

$w{'mep_tree'}->set_model($mep_store);

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("page",
						     $renderer,
						     text=> MEP_PAGE);
$w{'mep_tree'}->append_column ($column);

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("ID",
						     $renderer,
						     text=> MEP_ID);
$w{'mep_tree'}->append_column ($column);

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("MAJ",
						     $renderer,
						     text=> MEP_MAJ);
$w{'mep_tree'}->append_column ($column);

### COPIES

$copies_store = Gtk2::ListStore->new ('Glib::String');


### modele CORREC

$correc_store = Gtk2::ListStore->new ('Glib::String',
				      'Glib::String', 
				      'Glib::String', 
				      );

$w{'correc_tree'}->set_model($correc_store);

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("ID",
						     $renderer,
						     text=> CORREC_ID);
$w{'correc_tree'}->append_column ($column);

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("MAJ",
						     $renderer,
						     text=> CORREC_MAJ);
$w{'correc_tree'}->append_column ($column);

### modele DIAGNOSTIQUE SAISIE

$diag_store = Gtk2::ListStore->new ('Glib::String',
				    'Glib::String', 
				    'Glib::String', 
				    'Glib::String', 
				    'Glib::String', 
				    'Glib::String', 
				    'Glib::String');

$w{'diag_tree'}->set_model($diag_store);

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("identifiant",
						     $renderer,
						     text=> DIAG_ID,
						     'background'=> DIAG_ID_BACK);
$column->set_sort_column_id(DIAG_ID);
$w{'diag_tree'}->append_column ($column);

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("mise � jour",
						     $renderer,
						     text=> DIAG_MAJ);
$w{'diag_tree'}->append_column ($column);

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("EQM",
						     $renderer,
						     'text'=> DIAG_EQM,
						     'background'=> DIAG_EQM_BACK);
$column->set_sort_column_id(DIAG_EQM);
$w{'diag_tree'}->append_column ($column);

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("sensibilit�",
						     $renderer,
						     'text'=> DIAG_DELTA,
						     'background'=> DIAG_DELTA_BACK);
$column->set_sort_column_id(DIAG_DELTA);
$w{'diag_tree'}->append_column ($column);

### modeles combobox

sub cb_model {
    my @texte=(@_);
    my $cs=Gtk2::ListStore->new ('Glib::String','Glib::String');
    my $k;
    my $t;
    while(($k,$t)=splice(@texte,0,2)) {
	$cs->set($cs->append,
		 COMBO_ID,$k,
		 COMBO_TEXT,$t);
    }
    return($cs);
}

# rajouter a partir de Encode::Supported
my $encodages=[{qw/inputenc latin1 iso ISO-8859-1/,'txt'=>'ISO-8859-1 (Europe occidentale)'},
	       {qw/inputenc latin2 iso ISO-8859-2/,'txt'=>'ISO-8859-2 (Europe centrale)'},
	       {qw/inputenc latin3 iso ISO-8859-3/,'txt'=>'ISO-8859-3 (Europe du sud)'},
	       {qw/inputenc latin4 iso ISO-8859-4/,'txt'=>'ISO-8859-4 (Europe du Nord)'},
	       {qw/inputenc latin5 iso ISO-8859-5/,'txt'=>'ISO-8859-5 (Cyrillique)'},
	       {qw/inputenc latin9 iso ISO-8859-9/,'txt'=>'ISO-8859-9 (Turc)'},
	       {qw/inputenc latin10 iso ISO-8859-10/,'txt'=>'ISO-8859-10 (Nordique)'},
	       {qw/inputenc utf8 iso UTF-8/,'txt'=>'UTF-8 (Unicode)'},
	       {qw/inputenc cp1252 iso cp1252/,'txt'=>'Windows-1252',
		alias=>['Windows-1252','Windows']},
	       {qw/inputenc applemac iso MacRoman/,'txt'=>'Macintosh Europe occidentale'},
	       {qw/inputenc macce iso MacCentralEurRoman/,'txt'=>'Macintosh Europe centrale'},
	       ];

sub get_enc {
    my ($txt)=@_;
    for my $e (@$encodages) {
	return($e) if($e->{'inputenc'} =~ /^$txt$/i ||
		      $e->{'iso'} =~ /^$txt$/i);
	if($e->{'alias'}) {
	    for my $a (@{$e->{'alias'}}) {
		return($e) if($a =~ /^$txt$/i);
	    }
	}
    }
    return('');
}

my $cb_model_vide=cb_model(''=>'(aucun)');

my %cb_stores=(
	       'delimiteur_decimal'=>cb_model(',',', (virgule)',
					      '.','. (point)'),
	       'note_arrondi'=>cb_model('inf','inf�rieur',
					'normal','normal',
					'sup','sup�rieur'),
	       'methode_impression'=>cb_model('CUPS','CUPS',
					      'commande','commande'),
	       'sides'=>cb_model('one-sided','Non',
				 'two-sided-long-edge','Grand c�t�',
				 'two-sided-short-edge','Petit c�t�'),
	       'encodage_latex'=>cb_model(map { $_->{'iso'}=>$_->{'txt'} }
					  (@$encodages)),
	       'manuel_image_type'=>cb_model('ppm'=>'(aucun)',
					     'xpm'=>'XPM',
					     'gif'=>'GIF'),
	       'liste_key'=>$cb_model_vide,
	       'assoc_code'=>$cb_model_vide,
	       );

$diag_store->set_sort_func(DIAG_EQM,\&sort_num,DIAG_EQM);
$diag_store->set_sort_func(DIAG_DELTA,\&sort_num,DIAG_DELTA);

## tri pour IDS

$diag_store->set_sort_func(DIAG_ID,\&sort_id,DIAG_ID);

## menu contextuel sur liste diagnostique -> visualisation zoom/page

$w{'diag_tree'}->signal_connect('button_release_event' =>
    sub {
	my ($self, $event) = @_;
	return FALSE unless $event->button == 3;
	my ($path, $column, $cell_x, $cell_y) = 
	    $w{'diag_tree'}->get_path_at_pos ($event->x, $event->y);
	if ($path) {
	    #my $row = $path->to_string();
	    #print "X=$cell_x Y=$cell_y ROW=$row\n";
	    
	    my $menu = Gtk2::Menu->new;
	    my $c=0;
	    foreach (qw/page zoom/) {
		my $id=$diag_store->get($diag_store->get_iter($path),
					DIAG_ID);
		my $f=id2file($id,$_,'jpg');
		if(-f $f) {
		    $c++;
		    my $item = Gtk2::MenuItem->new ($_);
		    $menu->append ($item);
		    $item->show;
		    $item->signal_connect (activate => sub {
			my (undef, $sortkey) = @_;
			print "Visualisation $f...\n";
			if(fork()==0) {
			    exec($o{'img_viewer'},$f);
			}
		    }, $_);
		}
	    }
	    $menu->popup (undef, undef, undef, undef,
			  $event->button, $event->time) if($c>0);
	    return TRUE; # stop propagation!
	    
	}
    });

### modele inconnus

$inconnu_store = Gtk2::ListStore->new ('Glib::String','Glib::String');

$w{'inconnu_tree'}->set_model($inconnu_store);

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("scan",
						     $renderer,
						     text=> INCONNU_SCAN);
$w{'inconnu_tree'}->append_column ($column);

$renderer=Gtk2::CellRendererText->new;
$column = Gtk2::TreeViewColumn->new_with_attributes ("ID",
						     $renderer,
						     text=> INCONNU_ID);
$w{'inconnu_tree'}->append_column ($column);


### Appel � des commandes externes -- log, annulation

my %les_commandes=();
my $cmd_id=0;

sub commande {
    my (@opts)=@_;
    $cmd_id++;

    my $c=AMC::Gui::Commande::new('avancement'=>$w{'avancement'},
				  'log'=>$w{'log_general'},
				  'finw'=>sub {
				      my $c=shift;
				      $w{'onglets_projet'}->set_sensitive(1);
				      $w{'commande'}->hide();
				      delete $les_commandes{$c->{'_cmdid'}};
				  },
				  @opts);

    $c->{'_cmdid'}=$cmd_id;
    $les_commandes{$cmd_id}=$c;

    $w{'onglets_projet'}->set_sensitive(0);
    $w{'commande'}->show();

    $c->open();
}
    
sub commande_annule {
    for (keys %les_commandes) { $les_commandes{$_}->quitte(); }
}

### Actions des menus

my $proj_store;

sub projet_nouveau {
    projet_charge('',1);
}

sub projet_charge {
    my (undef,$cree)=(@_);
    my @projs;
    
    mkdir($o{'rep_projets'}) if($cree && ! -d $o{'rep_projets'});
    
    if(-d $o{'rep_projets'}) {
	opendir(DIR, $o{'rep_projets'}) 
	    || die "Erreur a l'ouverture du repertoire ".$o{'rep_projets'}." : $!";
	my @f=map { decode("utf-8",$_); } readdir(DIR);
	#print "F:".join(',',map { $_.":".(-d $o{'rep_projets'}."/".$_) } @f).".\n";
	@projs = grep { ! /^\./ && -d $o{'rep_projets'}."/".$_ } @f;
	closedir DIR;
	#print "[".$o{'rep_projets'}."] P:".join(',',@projs).".\n";
    }

    if($#projs>=0 || $cree) {
	
	my $gp=Gtk2::GladeXML->new($glade_xml,'choix_projet');
	$gp->signal_autoconnect_from_package('main');

	for(qw/choix_projet choix_projets_liste
	    projet_bouton_ouverture projet_bouton_creation
	    projet_nom projet_nouveau/) {
	    $w{$_}=$gp->get_widget($_);
	}

	if($cree) {
	    $w{'projet_nouveau'}->show();
	    $w{'projet_bouton_creation'}->show();
	    $w{'projet_bouton_ouverture'}->hide();
	}
	
	$proj_store = Gtk2::ListStore->new ('Glib::String',
					    'Gtk2::Gdk::Pixbuf');
	
	$w{'choix_projets_liste'}->set_model($proj_store);
	
	$w{'choix_projets_liste'}->set_text_column(PROJ_NOM);
	$w{'choix_projets_liste'}->set_pixbuf_column(PROJ_ICO);
	
	my $pb=$w{'main_window'}->render_icon ('gtk-open', 'menu');
	
	for (sort { $a cmp $b } @projs) {
	    #print "Projet : $_.\n";
	    $proj_store->set($proj_store->append,
			     PROJ_NOM,$_,
			     PROJ_ICO,$pb); 
	}
	
    } else {
	my $dialog = Gtk2::MessageDialog->new ($w{'main_window'},
					       'destroy-with-parent',
					       'info', # message type
					       'ok', # which set of buttons?
					       "Vous n'avez aucun projet de QCM dans le r�pertoire %s !",$o{'rep_projets'});
	$dialog->run;
	$dialog->destroy;
	
    }
}

sub projet_charge_ok {
    my $sel=$w{'choix_projets_liste'}->get_selected_items();
    my $proj;

    if($sel) {
	$proj=$proj_store->get($proj_store->get_iter($sel),PROJ_NOM);
    }

    $w{'choix_projet'}->destroy();

    projet_ouvre($proj) if($proj);
}

sub projet_charge_nouveau {
    my $proj=$w{'projet_nom'}->get_text();
    $w{'choix_projet'}->destroy();

    # existe deja ?

    if(-e $o{'rep_projets'}."/$proj") {

	my $dialog = Gtk2::MessageDialog->new_with_markup ($w{'main_window'},
					       'destroy-with-parent',
					       'error', # message type
					       'ok', # which set of buttons?
					       sprintf("Le nom <b>%s</b> est d�j� utilis� dans le r�pertoire des projets. Pour cr�er un nouveau projet, il faut choisir un autre nom.",$proj));
	$dialog->run;
	$dialog->destroy;      
	

    } else {

	projet_ouvre($proj,1);
	projet_sauve();

    }
}

sub projet_charge_non {
    $w{'choix_projet'}->destroy();
}

sub projet_sauve {
    print "Sauvegarde du projet...\n";
    my $of=fich_options($projet{'nom'});
    if(open(OPTS,">:encoding(utf-8)",$of)) {
	print OPTS XMLout(\%projet,
			  "XMLDecl"=>'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>',
			  "RootName"=>'projetAMC','NoAttr'=>1)."\n";
	close OPTS;
	$projet{'modifie'}=0;
    } else {
	my $dialog = Gtk2::MessageDialog->new ($w{'main_window'},
					       'destroy-with-parent',
					       'error', # message type
					       'ok', # which set of buttons?
					       "Erreur � l'ecriture du fichier d'options %s : %s",$of,$!);
	$dialog->run;
	$dialog->destroy;      
    }
}

### Actions des boutons de la partie DOCUMENTS

sub doc_active {
    my $sel=$w{'documents_tree'}->get_selection()->get_selected_rows()->get_indices();
    #print "Active $sel...\n";
    my $f=localise($projet{'docs'}->[$sel]);
    print "Visualisation $f...\n";
    if(fork()==0) {
	exec($o{'pdf_viewer'},$f);
    }
}

sub mep_active {
    my $sel=$w{'mep_tree'}->get_selection()->get_selected_rows()->get_indices();
    my $id=($mep_list->ids())[$sel];
    print "Active MEP $sel : ID=$id...\n";
    my $f=$mep_list->filename($id);
    print "Visualisation $f...\n";
    if(fork()==0) {
	exec($o{'xml_viewer'},$f);
    }
}

sub fichiers_mep {
    my $md=localise($projet{'mep'});
    opendir(MDIR, $md) || die "can't opendir $md: $!";
    my @meps = map { "$md/$_" } grep { /^mep.*xml$/ && -f "$md/$_" } readdir(MDIR);
    closedir MDIR;
    return(@meps);
}

sub mini {($_[0]<$_[1] ? $_[0] : $_[1])}

sub doc_maj {
    my $sur=0;
    if($an_list->nombre()>0) {
	my $dialog = Gtk2::MessageDialog->new_with_markup ($w{'main_window'},
					       'destroy-with-parent',
					       'warning', # message type
					       'ok-cancel', # which set of buttons?
					       "L'analyse de certaines copies a d�j� �t� effectu�e sur la base des documents de travail actuels. Vous avez donc vraisemblablement d�j� effectu� l'examen sur la base de ces documents. Si vous modifiez les documents de travail, vous ne serez plus en mesure d'analyser les copies que vous avez d�j� distribu� ! Souhaitez-vous tout de m�me continuer ? Cliquez sur Valider pour effacer les anciennes mises en page et mettre � jour les documents de travail, ou sur Annuler pour annuler cette op�ration. <b>Pour permettre l'utilisation d'un sujet d�j� imprim�, annulez !</b>");
	my $reponse=$dialog->run;
	$dialog->destroy;      
	
	if($reponse eq 'cancel') {
	    return(0);
	} 

	$sur=1;
    }
	
    # deja des MEP fabriquees ?
    my @meps=fichiers_mep();
    if(@meps) {
	if(!$sur) {
	    my $dialog = Gtk2::MessageDialog->new_with_markup ($w{'main_window'},
							       'destroy-with-parent',
							       'question', # message type
							       'ok-cancel', # which set of buttons?
							       "Certaines mises en page on d�j� �t� calcul�es pour les documents actuels. En refabriquant les documents de travail, les mises en page deviendront obsol�tes et seront donc effac�es. Souhaitez-vous tout de m�me continuer ? Cliquez sur Valider pour effacer les anciennes mises en page et mettre � jour les documents de travail, ou sur Annuler pour annuler cette op�ration. <b>Pour permettre l'utilisation d'un sujet d�j� imprim�, annulez !</b>");
	    my $reponse=$dialog->run;
	    $dialog->destroy;      
	    
	    if($reponse eq 'cancel') {
		return(0);
	    } 
	}
	
	unlink @meps;
	detecte_mep();
    }   

    #
    commande('commande'=>[with_prog("AMC-prepare.pl"),
			  "--mode","s",
			  localise($projet{'texsrc'}),
			  "--prefix",localise(''),
			  ],
	     'signal'=>2,
	     'texte'=>'Mise � jour des documents...',
	     'progres.id'=>'MAJ',
	     'progres.pulse'=>0.01,
	     'fin'=>sub { 
		 my $c=shift;
		 my @err=$c->erreurs();
		 if(@err) {
		     my $dialog = Gtk2::MessageDialog->new_with_markup ($w{'main_window'},
									'destroy-with-parent',
									'error', # message type
									'ok', # which set of buttons?
									"La compilation de votre source LaTeX a occasionn� des erreurs. Vous devez corriger votre LaTeX pour obtenir une mise � jour des documents. Utilisez votre �diteur LaTeX ou la commande latex pour un diagnostic pr�cis des erreurs.\n\n".join("\n",@err[0..mini(9,$#err)]).($#err>9 ? "\n\n<i>(Seules les dix premi�res erreurs ont �t� retranscrites)</i>": "") );
		     my $reponse=$dialog->run;
		     $dialog->destroy;
		 }
		 detecte_documents(); 
	     });
    
}

my $cups;
my $g_imprime;

sub nonnul {
    my $s=shift;
    $s =~ s/\000//g;
    return($s);
}

sub autre_imprimante {
    my $i=$w{'imprimante'}->get_model->get($w{'imprimante'}->get_active_iter,COMBO_ID);
    print "Choix imprimante $i\n";
    my $ppd=$cups->getPPD($i);
    my $k='';

  CHOIX: for my $i (qw/StapleLocation/) {
      my $oi=$ppd->getOption($i);
      if(%$oi) {
	  $k=nonnul($oi->{'keyword'});
	  print "- $k\n";
	  my $ok=$o{'options_impression'}->{$k};
	  $o{'options_impression'}->{$k}=nonnul($oi->{'defchoice'})
	      if(!$ok);
	  $cb_stores{'agrafe'}=cb_model(map { (nonnul($_->{'choice'}),
					       nonnul($_->{'text'})) } (@{$oi->{'choices'}}));
	  transmet_pref($g_imprime,'imp',$o{'options_impression'},
			{$k=>'agrafe'});
	  $o{'options_impression'}->{$k}=$ok;
	  last CHOIX;
      }
  }
    if(!$k) {
	$cb_stores{'agrafe'}=cb_model();
	$w{'imp_c_agrafe'}->set_model($cb_stores{'agrafe'});
    }
}

sub sujet_impressions {
    print "Choix des impressions...\n";

    $g_imprime=Gtk2::GladeXML->new($glade_xml,'choix_pages_impression');
    $g_imprime->signal_autoconnect_from_package('main');
    for(qw/choix_pages_impression arbre_choix_copies bloc_imprimante imprimante imp_c_agrafe/) {
	$w{$_}=$g_imprime->get_widget($_);
    }

    if($o{'methode_impression'} eq 'CUPS') {
	$w{'bloc_imprimante'}->show();

	$cups=Net::CUPS->new();

	# les imprimantes :

	my @printers = $cups->getDestinations();
	print "Imprimantes : ".join(' ',map { $_->getName() } @printers)."\n";
	my $p_model=cb_model(map { ($_->getName(),$_->getDescription()) } @printers);
	$w{'imprimante'}->set_model($p_model);
	if(! $o{'imprimante'}) {
	    $o{'imprimante'}=$cups->getDestination()->getName();
	}
	my $i=model_id_to_iter($p_model,COMBO_ID,$o{'imprimante'});
	if($i) {
	    $w{'imprimante'}->set_active_iter($i);
	}

	# transmission

	transmet_pref($g_imprime,'imp',$o{'options_impression'});
    }

    $copies_store->clear();
    for my $c ($mep_list->etus()) {
	$copies_store->set($copies_store->append(),COPIE_N,$c);
    }

    $w{'arbre_choix_copies'}->set_model($copies_store);

    my $renderer=Gtk2::CellRendererText->new;
    my $column = Gtk2::TreeViewColumn->new_with_attributes ("copies",
							    $renderer,
							    text=> COPIE_N );
    $w{'arbre_choix_copies'}->append_column ($column);

    $w{'arbre_choix_copies'}->get_selection->set_mode("multiple");

}

sub sujet_impressions_cancel {
    $w{'choix_pages_impression'}->destroy;
}

sub sujet_impressions_ok {
    my $os='none';
    my @e=();
    for my $i ($w{'arbre_choix_copies'}->get_selection()->get_selected_rows() ) {
	push @e,$copies_store->get($copies_store->get_iter($i),COPIE_N);
    }

    if($o{'methode_impression'} eq 'CUPS') {
	my $i=$w{'imprimante'}->get_model->get($w{'imprimante'}->get_active_iter,COMBO_ID);
	if($i ne $o{'imprimante'}) {
	    $o{'imprimante'}=$i;
	    $o{'modifie'}=1;
	}

	reprend_pref('imp',$o{'options_impression'});

	if($o{'options_impression'}->{'modifie'}) {
	    $o{'modifie'}=1;
	    delete $o{'options_impression'}->{'modifie'};
	}

	$os=join(',',map { $_."=".$o{'options_impression'}->{$_} } 
		 grep { $o{'options_impression'}->{$_} }
		 (keys %{$o{'options_impression'}}) );
    }

    $w{'choix_pages_impression'}->destroy;
    
    print "Impression : ".join(",",@e)."\n";

    my $fh=File::Temp->new(TEMPLATE => "nums-XXXXXX",
			   TMPDIR => 1,
			   UNLINK=> 1);
    print $fh join("\n",@e)."\n";
    $fh->seek( 0, SEEK_END );

    commande('commande'=>[with_prog("AMC-imprime.pl"),
			  "--methode",$o{'methode_impression'},
			  "--imprimante",$o{'imprimante'},
			  "--options",$os,
			  "--print-command",$o{'print_command_pdf'},
			  "--sujet",localise($projet{'docs'}->[0]),
			  "--mep",localise($projet{'mep'}),
			  "--progression-id",'impression',
			  "--progression",1,
			  "--fich-numeros",$fh->filename,
			  ],
	     'signal'=>2,
	     'texte'=>'Impression copie par copie...',
	     'progres.id'=>'impression',
	     'o'=>{'fh'=>$fh},
	     'fin'=>sub {
		 my $c=shift;
		 close($c->{'o'}->{'fh'});
	     },

	     );
}

sub calcule_mep {
    # on efface les anciennes MEP
    my @meps=fichiers_mep();
    unlink @meps;
    # on recalcule...
    commande('commande'=>[with_prog("AMC-prepare.pl"),
			  "--calage",localise($projet{'docs'}->[2]),
			  "--progression-id",'MEP',
			  "--progression",1,
			  "--n-procs",$o{'n_procs'},
			  "--mode","m",
			  localise($projet{'texsrc'}),
			  "--mep",localise($projet{'mep'}),
			  ],
	     'texte'=>'Calcul des mises en page...',
	     'progres.id'=>'MEP',
	     'fin'=>sub { detecte_mep(); });
}

### Actions des boutons de la partie SAISIE

sub saisie_manuelle {
    if($mep_list->nombre()>0) {
	my $gm=AMC::Gui::Manuel::new('cr-dir'=>localise($projet{'cr'}),
				     'mep-dir'=>localise($projet{'mep'}),
				     'mep-data'=>$mep_list,
				     'an-data'=>$an_list,
				     'liste'=>$projet{'listeetudiants'},
				     'sujet'=>localise($projet{'docs'}->[0]),
				     'etud'=>'',
				     'dpi'=>$o{'saisie_dpi'},
				     'debug'=>$debug,
				     'seuil'=>$projet{'seuil'},
				     'seuil_sens'=>$o{'seuil_sens'},
				     'seuil_eqm'=>$o{'seuil_eqm'},
				     'global'=>0,
				     'encodage_interne'=>$o{'encodage_interne'},
				     'encodage_liste'=>$o{'encodage_liste'},
				     'image_type'=>$o{'manuel_image_type'},
				     'en_quittant'=>\&detecte_analyse,
				     );
    } else {
	my $dialog = Gtk2::MessageDialog->new_with_markup ($w{'main_window'},
					       'destroy-with-parent',
					       'error', # message type
					       'ok', # which set of buttons?
					       "Aucune mise en page n'est disponible pour ce projet. Veuillez utiliser le bouton <i>calculer les mises en page</i> de l'onglet <i>pr�paration</i> avant la saisie manuelle.");
	$dialog->run;
	$dialog->destroy;      
    }
}

sub saisie_automatique {
    my $gsa=Gtk2::GladeXML->new($glade_xml,'saisie_auto');
    $gsa->signal_autoconnect_from_package('main');
    for(qw/saisie_auto copie_scans/) {
	$w{$_}=$gsa->get_widget($_);
    }
}

sub saisie_auto_annule {
    $w{'saisie_auto'}->destroy();
}

sub saisie_auto_ok {
    my @f=$w{'saisie_auto'}->get_filenames();
    my $copie=$w{'copie_scans'}->get_active();
    print "Scans : ".join(',',@f)."\n";
    $w{'saisie_auto'}->destroy();

    # copie eventuelle dans le repertoire projet

    if($copie) {
	my @fl=();
	my $c=0;
	for my $fich (@f) {
	    my ($fxa,$fxb,$fb) = splitpath($fich);
	    my $dest=localise("scans/".$fb);
	    if(copy($fich,$dest)) {
		push @fl,$dest; 
		$c++;
	    } else {
		push @fl,$fich;
	    }
	}
	print "Copie des fichiers scan : ".$c."/".(1+$#f)."\n";
	@f=@fl;
    }

    # pour eviter tout probleme du a une longueur excessive de la
    # ligne de commande, fabrication fichier temporaire avec la liste
    # des fichiers...

    my $fh=File::Temp->new(TEMPLATE => "liste-XXXXXX",
			   TMPDIR => 1,
			   UNLINK=> 1);
    print $fh join("\n",@f)."\n";
    $fh->seek( 0, SEEK_END );

    # appel AMC-analyse avec cette liste

    commande('commande'=>[with_prog("AMC-analyse.pl"),
			  "--binaire",
			  "--seuil-coche",$projet{'seuil'},
			  "--progression-id",'analyse',
			  "--progression",1,
			  "--n-procs",$o{'n_procs'},
			  "--mep",localise($projet{'mep'}),
			  "--cr",localise($projet{'cr'}),
			  "--liste-fichiers",$fh->filename,
			  ],
	     'signal'=>2,
	     'texte'=>'Saisie automatique...',
	     'progres.id'=>'analyse',
	     'niveau1'=>sub { detecte_analyse('interne'=>1); },
	     'o'=>{'fh'=>$fh},
	     'fin'=>sub {
		 my $c=shift;
		 my @err=$c->erreurs();

		 close($c->{'o'}->{'fh'});

		 my @fe=();
		 for(@err) {
		     if(/ERREUR\(([^\)]+)\)\(([^\)]+)\)/) {
			 push @fe,[$1,$2];
		     }
		 }
		 detecte_analyse('erreurs'=>\@fe);
	     }
	     );
    
}

sub valide_liste {
    my (%oo)=@_;
    print "* valide_liste\n" if($debug);

    my $fl=$w{'liste'}->get_filename();

    # lecture du fichier pour verification de format...
    my @heads=();
    my $err=0;
    my $nl=0;
    my $nd;
    open(FL,"<:encoding(".$o{'encodage_liste'}.")",$fl);
  LIG: while(<FL>) {
      chomp;
      $nl++;
      s/\#.*//;
      next LIG if(/^\s*$/);
      if(@heads) {
	  $nd = 1+tr/:/:/;
	  if($nd != (1+$#heads)) {
	      $err=$nl;
	      last LIG;
	  }
      } else {
	  @heads=split(/:/,$_);
      }
  }
    close(FL);

    if($err) {
	if(!$oo{'noinfo'}) {
	    my $dialog = Gtk2::MessageDialog->new_with_markup ($w{'main_window'},
							       'destroy-with-parent',
							       'error', # message type
							       'ok', # which set of buttons?
							       "Le fichier choisi ne convient pas : ".($#heads>0 ? ($#heads+1)." ent�tes ont �t� d�tect�s (".join(', ',@heads).")," : "aucun ent�te n'est pr�sent,")." mais il y a $nd champs en ligne $err.");
	    $dialog->run;
	    $dialog->destroy;
	} else {
	    print "Ligne $err : $nd champs / ".join(', ',@heads)."\n" if($debug);
	}
	$cb_stores{'liste_key'}=$cb_model_vide;
    } else {
	# ok
	if(!$oo{'nomodif'}) {
	    $projet{'listeetudiants'}=$fl;
	    $projet{'modifie'}=1;
	}
	# transmission liste des en-tetes
	print "entetes : ".join(",",@heads)."\n" if($debug);
	$cb_stores{'liste_key'}=cb_model('','(aucun)',
					 map { ($_,$_) } (@heads));
    }
    transmet_pref($gui,'notation',\%projet);
}

### Actions des boutons de la partie NOTATION

sub associe {
    if(-f $projet{'listeetudiants'}) {
	my $ga=AMC::Gui::Association::new('cr'=>localise($projet{'cr'}),
					  'liste'=>$projet{'listeetudiants'},
					  'global'=>0,
					  'encodage_liste'=>$o{'encodage_liste'},
					  'encodage_interne'=>$o{'encodage_interne'},
					  );
    } else {
	my $dialog = Gtk2::MessageDialog->new ($w{'main_window'},
					       'destroy-with-parent',
					       'info', # message type
					       'ok', # which set of buttons?
					       "Avant d'associer les noms aux copies, il faut indiquer un fichier de liste des �tudiants dans l'onglet � Saisie �.");
	$dialog->run;
	$dialog->destroy;
	
    }
}

sub valide_cb {
    my ($var,$cb)=@_;
    my $cbc=$cb->get_active();
    if($cbc xor $$var) {
	$$var=$cbc;
	$projet{'modifie'}=1;
	print "* valide_cb\n" if($debug);
    }
}

sub valide_options_correction {
    my ($ww,$o)=@_;
    my $name=$ww->get_name();
    print "Valide OC depuis $name\n" if($debug);
    valide_cb(\$projet{$name},$w{$name});
}

sub valide_options_notation {
    reprend_pref('notation',\%projet);
}

sub voir_notes {
    if(-f localise($projet{'notes'})) {
	if(fork()==0) {
	    exec($o{'dat_viewer'},localise($projet{'notes'}));
	}
    } else {
	my $dialog = Gtk2::MessageDialog->new ($w{'main_window'},
					       'destroy-with-parent',
					       'info', # message type
					       'ok', # which set of buttons?
					       "Les copies ne sont pas encore corrig�es : veuillez d'abord utiliser le bouton � Corriger �.");
	$dialog->run;
	$dialog->destroy;
	
    }
}

sub noter {
    if($projet{'maj_bareme'}) {
	commande('commande'=>[with_prog("AMC-prepare.pl"),
			      "--mode","b",
			      "--bareme",localise($projet{'fichbareme'}),
			      localise($projet{'texsrc'}),
			      ],
		 'texte'=>'Lecture du bareme...',
		 'fin'=>\&noter_calcul,
		 'progres.pulse'=>0.01);
    } else {
	noter_calcul();
    }
}

sub noter_calcul {
    commande('commande'=>[with_prog("AMC-note.pl"),
			  "--cr",localise($projet{'cr'}),
			  "--an-saved",localise($an_saved),
			  "--bareme",localise($projet{'fichbareme'}),
			  "-o",localise($projet{'notes'}),
			  "--seuil",$projet{'seuil'},
			  
			  "--grain",$projet{'note_grain'},
			  "--arrondi",$projet{'note_arrondi'},
			  "--notemax",$projet{'note_max'},
			  
			  "--encodage-interne",$o{'encodage_interne'},
			  ],
	     'signal'=>2,
	     'texte'=>'Calcul des notes...',
	     'progres.pulse'=>0.01,
	     'fin'=>sub {
		 noter_resultat();
	     },
	     );
}

sub noter_resultat {
    my $moy;
    if(-s localise($projet{'notes'})) {
	my $notes=eval { XMLin(localise($projet{'notes'})) };
	if($notes) {
	    $moy=$notes->{'moyenne'};
	    $w{'correction_result'}->set_markup("<span foreground=\"darkgreen\">Moyenne : $moy</span>");
	} else {
	    $w{'correction_result'}->set_markup("<span foreground=\"red\">Notes illisibles</span>");
	}
    } else {
	$w{'correction_result'}->set_markup("<span foreground=\"red\">Aucun calcul de notes</span>");
    }
}

sub visualise_correc {
    my $sel=$w{'correc_tree'}->get_selection()->get_selected_rows();
    #print "Correc $sel $correc_store\n";
    my $f=$correc_store->get($correc_store->get_iter($sel),CORREC_FILE);
    print "Visualisation $f...\n";
    if(fork()==0) {
	exec($o{'img_viewer'},$f);
    }
}

sub regroupement {

    valide_options_notation();

    commande('commande'=>[with_prog("AMC-regroupe.pl"),
			  "--cr",localise($projet{'cr'}),
			  "--progression-id",'regroupe',
			  "--progression",1,
			  "--modele",$projet{'modele_regroupement'},
			  ],
	     'texte'=>'Regroupement des pages corrig�es par �tudiant...',
	     'progres.id'=>'regroupe',
	     );
}

sub regarde_regroupements {
    my $f=localise($projet{'cr'})."/corrections/pdf";
    print STDERR "Je vais voir $f\n";
    my $seq=0;
    my @c=map { $seq+=s/[%]d/$f/g;$_; } split(/\s+/,$o{'dir_opener'});
    push @c,$f if(!$seq);
    # nautilus attend des arguments dans l'encodage specifie par LANG & co.
    @c=map { encode($encodage_systeme,$_); } @c;

    if(fork()==0) {
	exec(@c);
    }
}

###

sub activate_apropos {
    my $gap=Gtk2::GladeXML->new($glade_xml,'apropos');
    $gap->signal_autoconnect_from_package('main');
    for(qw/apropos/) {
	$w{$_}=$gap->get_widget($_);
    }
}

sub close_apropos {
    $w{'apropos'}->destroy();
}

sub activate_doc {
    my $url='file:///usr/share/doc/auto-multiple-choice/html/auto-multiple-choice/index.html';

    if(fork()==0) {
	my $seq=0;
	my @c=map { $seq+=s/[%]u/$url/g;$_; } split(/\s+/,$o{'html_browser'});
	push @c,$url if(!$seq);
	@c=map { encode($encodage_systeme,$_); } @c;

	exec(@c);
    }
}

# transmet les preferences vers les widgets correspondants
sub transmet_pref {
    my ($gap,$prefixe,$h,$alias)=@_;

    for my $t (keys %$h) {
	my $ta=$t;
	$ta=$alias->{$t} if($alias->{$t});

	my $wp=$gap->get_widget($prefixe.'_x_'.$ta);
	if($wp) {
	    $w{$prefixe.'_x_'.$t}=$wp;
	    $wp->set_text($h->{$t});
	}
	$wp=$gap->get_widget($prefixe.'_f_'.$ta);
	if($wp) {
	    $w{$prefixe.'_f_'.$t}=$wp;
	    if($wp->get_action =~ /-folder$/i) {
		$wp->set_current_folder($h->{$t});
	    } else {
		$wp->set_filename($h->{$t});
	    }
	}
	$wp=$gap->get_widget($prefixe.'_v_'.$ta);
	if($wp) {
	    $w{$prefixe.'_v_'.$t}=$wp;
	    $wp->set_active($h->{$t});
	}
	$wp=$gap->get_widget($prefixe.'_s_'.$ta);
	if($wp) {
	    $w{$prefixe.'_s_'.$t}=$wp;
	    $wp->set_value($h->{$t});
	}
	$wp=$gap->get_widget($prefixe.'_c_'.$ta);
	if($wp) {
	    $w{$prefixe.'_c_'.$t}=$wp;
	    if($cb_stores{$ta}) {
		print "CB_STORE($t) modifie\n" if($debug);
		$wp->set_model($cb_stores{$ta});
		my $i=model_id_to_iter($wp->get_model,COMBO_ID,$h->{$t});
		if($i) {
		    print "[$t] trouve $i\n" if($debug);
		    print " -> ".$cb_stores{$t}->get($i,COMBO_TEXT)."\n" if($debug);
		    $wp->set_active_iter($i);
		}
	    } else {
		print "pas de CB_STORE pour $t\n" if($debug);
		$wp->set_active($h->{$t});
	    }
	}
    }
}

# met a jour les preferences depuis les widgets correspondants
sub reprend_pref {
    my ($prefixe,$h)=@_;

    for my $t (keys %$h) {
	my $n;
	my $wp=$w{$prefixe.'_x_'.$t};
	if($wp) {
	    $n=$wp->get_text();
	    $h->{'modifie'}=1 if($h->{$t} ne $n);
	    $h->{$t}=$n;
	}
	$wp=$w{$prefixe.'_f_'.$t};
	if($wp) {
	    if($wp->get_action =~ /-folder$/i) {
		$n=$wp->get_current_folder();
	    } else {
		$n=$wp->get_filename();
	    }
	    $h->{'modifie'}=1 if($h->{$t} ne $n);
	    $h->{$t}=$n;
	}
	$wp=$w{$prefixe.'_v_'.$t};
	if($wp) {
	    $n=$wp->get_active();
	    $h->{'modifie'}=1 if($h->{$t} ne $n);
	    $h->{$t}=$n;
	}
	$wp=$w{$prefixe.'_s_'.$t};
	if($wp) {
	    $n=$wp->get_value();
	    $h->{'modifie'}=1 if($h->{$t} ne $n);
	    $h->{$t}=$n;
	}
	$wp=$w{$prefixe.'_c_'.$t};
	if($wp) {
	    if($wp->get_model) {
		if($wp->get_active_iter) {
		    $n=$wp->get_model->get($wp->get_active_iter,COMBO_ID);
		} else {
		    $n='';
		}
		#print "[$t] valeur=$n\n";
	    } else {
		$n=$wp->get_active();
	    }
	    $h->{'modifie'}=1 if($h->{$t} ne $n);
	    $h->{$t}=$n;
	}
    }
    
}

sub change_methode_impression {
    if($w{'pref_x_print_command_pdf'}) {
	my $m='';
	if($w{'pref_c_methode_impression'}->get_active_iter) {
	    $m=$w{'pref_c_methode_impression'}->get_model->get($w{'pref_c_methode_impression'}->get_active_iter,COMBO_ID);
	}
	$w{'pref_x_print_command_pdf'}->set_sensitive($m eq 'commande');
    }
}

sub edit_preferences {
    my $gap=Gtk2::GladeXML->new($glade_xml,'edit_preferences');

    for(qw/edit_preferences pref_projet_tous pref_projet_annonce pref_x_print_command_pdf pref_c_methode_impression/) {
	$w{$_}=$gap->get_widget($_);
    }

    $gap->signal_autoconnect_from_package('main');

    for my $t (grep { /^pref(_projet)?_[xfcv]_/ } (keys %w)) {
	delete $w{$t};
    }
    transmet_pref($gap,'pref',\%o);
    transmet_pref($gap,'pref_projet',\%projet) if($projet{'nom'});

    # projet ouvert -> ne pas changer localisation
    if($projet{'nom'}) {
	$w{'pref_f_rep_projets'}->set_sensitive(0);
	$w{'pref_projet_annonce'}->set_label('<i>Pr�f�rences du projet � <b>'.$projet{'nom'}.'</b> �</i>');
    } else {
	$w{'pref_projet_tous'}->set_sensitive(0);
	$w{'pref_projet_annonce'}->set_label('<i>Pr�f�rences du projet</i>');
    }

    change_methode_impression();
}

sub accepte_preferences {
    reprend_pref('pref',\%o);
    reprend_pref('pref_projet',\%projet) if($projet{'nom'});
    $w{'edit_preferences'}->destroy();

    sauve_pref_generales();

    test_commandes();
}

sub sauve_pref_generales {
    print "Sauvegarde des preferences generales...\n";

    if(open(OPTS,">$o_file")) {
	print OPTS XMLout(\%o,"RootName"=>'AMC','NoAttr'=>1)."\n";
	close OPTS;
	$o{'modifie'}=0;
    } else {
	my $dialog = Gtk2::MessageDialog->new ($w{'main_window'},
					       'destroy-with-parent',
					       'error', # message type
					       'ok', # which set of buttons?
					       "Erreur � l'ecriture du fichier d'options %s : %s",$o_file,$!);
	$dialog->run;
	$dialog->destroy;      
    }
}

sub annule_preferences {
    print "Annule\n";
    $w{'edit_preferences'}->destroy();
}

sub file_maj {
    my $f=shift;
    if(-f $f) {
	if(-r $f) {
	    my @s=stat($f);
	    my $t=localtime($s[9]);
	    return(sprintf("%02d/%02d/%04d %02d:%02d",
			   $t->mday,$t->mon+1,$t->year+1900,$t->hour,$t->min));
	} else {
	    return('illisible');
	}
    } else {
	return('inexistant');
    }
}

sub detecte_documents {
    for my $i (0..2) {
	my $r='';
	my $f=localise($projet{'docs'}->[$i]);
	$doc_store->set($doc_ligne[$i],DOC_MAJ,file_maj($f));
    }
}

sub detecte_mep {
    $w{'commande'}->show();
    $w{'avancement'}->set_text("Recherche des mises en page d�tect�es...");
    $w{'avancement'}->set_fraction(0);
    Gtk2->main_iteration while ( Gtk2->events_pending );

    $mep_list->maj('progres'=>sub {
	$w{'avancement'}->set_pulse_step(.02);
	$w{'avancement'}->pulse();
	Gtk2->main_iteration while ( Gtk2->events_pending );
    },
		   );

    $mep_store->clear();

    $w{'onglet_saisie'}->set_sensitive($mep_list->nombre()>0);

    my $ii=0;
    for my $i ($mep_list->ids()) {
	my $iter=$mep_store->append;
	$mep_store->set($iter,MEP_ID,$i,MEP_PAGE,$mep_list->attr($i,'page'),MEP_MAJ,file_maj($mep_list->filename($i)));

	$ii++;
	$w{'avancement'}->set_fraction($ii/$mep_list->nombre());
	Gtk2->main_iteration while ( Gtk2->events_pending );
    }

    $w{'avancement'}->set_text('');
    $w{'avancement'}->set_fraction(0);
    $w{'commande'}->hide();
    Gtk2->main_iteration while ( Gtk2->events_pending );
}

sub detecte_correc {
    my $cordir=localise("cr/corrections/jpg");
    $correc_store->clear();
    my @corr=();

    if(opendir(DIR, $cordir)) {
	@corr = sort { file_triable($a) cmp file_triable($b) } 
	grep { /\.jpg$/ && -f "$cordir/$_" } readdir(DIR);
	closedir DIR;
	
	for my $f (@corr) {
	    my $iter=$correc_store->append;
	    $correc_store->set($iter,CORREC_FILE,"$cordir/$f",
			       CORREC_MAJ,file_maj("$cordir/$f"),
			       CORREC_ID,file2id($f));
	}
    }

    $w{'regroupement_corriges'}->set_sensitive($#corr>=0);
}

sub detecte_analyse {
    my (%oo)=(@_);

    $w{'commande'}->show();
    my $av_text=$w{'avancement'}->get_text();
    $w{'avancement'}->set_text("Recherche des analyses effectu�es...");
    $w{'avancement'}->set_fraction(0) if(!$oo{'interne'});
    Gtk2->main_iteration while ( Gtk2->events_pending );

    my @ids_m;

    @ids_m=$an_list->maj('progres'=>sub {
	$w{'avancement'}->set_pulse_step(.1);
	$w{'avancement'}->pulse();
	Gtk2->main_iteration while ( Gtk2->events_pending );
    },
			 );

    if($oo{'premier'}) {
	@ids_m=$an_list->ids();
    }

    print "IDS_M : ".join(' ',@ids_m)."\n";

    $w{'onglet_notation'}->set_sensitive($an_list->nombre()>0);
    detecte_correc() if($an_list->nombre()>0);

    my $ii=0;

    for my $i (@ids_m) {
	# deja dans la liste ? sinon on rajoute...
	my $iter=model_id_to_iter($diag_store,DIAG_ID,$i);
	$iter=$diag_store->append if(!$iter);

	my ($eqm,$eqm_coul)=$an_list->mse_string($i,
						 $o{'seuil_eqm'},
						 'red');
	my ($sens,$sens_coul)=$an_list->sensibilite_string($i,$projet{'seuil'},
							   $o{'seuil_sens'},
							   'red');

	$diag_store->set($iter,
			 DIAG_ID,$i,
			 DIAG_ID_BACK,$an_list->couleur($i),
			 DIAG_EQM,$eqm,
			 DIAG_EQM_BACK,$eqm_coul,
			 DIAG_MAJ,file_maj($an_list->filename($i)),
			 DIAG_DELTA,$sens,
			 DIAG_DELTA_BACK,$sens_coul,
			 );

	$ii++;
	$w{'avancement'}->set_fraction(0.9*$ii/(1+$#ids_m)) if(!$oo{'interne'});
	Gtk2->main_iteration while ( Gtk2->events_pending );
    }

    # erreurs lors du traitement automatique des scans :

    $inconnu_store->clear();
    
    if($oo{'erreurs'}) {
	for my $f (@{$oo{'erreurs'}}) {
	    my $iter=$inconnu_store->append;
	    $inconnu_store->set($iter,
				INCONNU_SCAN,$f->[0],
				INCONNU_ID,$f->[1]);
	}
    }

    # resume

    my %r=$mep_list->stats($an_list);
    my $tt='';
    if($r{'incomplet'}) {
	$tt=sprintf("Saisie de %d copie(s) compl�te(s) et <span foreground=\"red\">%d copie(s) incompl�te(s)</span>",$r{'complet'},$r{'incomplet'});
    } else {
	$tt=sprintf("<span foreground=\"darkgreen\">Saisie de %d copie(s) compl�te(s)</span>",$r{'complet'});
    }
    $w{'diag_result'}->set_markup($tt);

    # ID manquants :

    for my $i (@{$r{'manque_id'}}) {
	my $iter=$inconnu_store->append;
	$inconnu_store->set($iter,
			    INCONNU_SCAN,'absent',
			    INCONNU_ID,$i);
    }
    

    $w{'avancement'}->set_text($av_text);
    $w{'avancement'}->set_fraction(0) if(!$oo{'interne'});
    $w{'commande'}->hide() if(!$oo{'interne'});
    Gtk2->main_iteration while ( Gtk2->events_pending );

}

sub set_source_tex {
    my ($importe)=@_;

    importe_source() if($importe);
    valide_source_tex();
}

sub source_latex_montre_nom {
    my $dialog = Gtk2::MessageDialog->new($w{'main_window'},
					  'destroy-with-parent',
					  'info', # message type
					  'ok', # which set of buttons?
					  "Le fichier LaTeX qui d�crit le QCM de ce projet est situ� � l'emplacement suivant :\n%s",
					  ($projet{'texsrc'} ? localise($projet{'texsrc'}) : "(aucun fichier)" ));
    $dialog->run;
    $dialog->destroy;
}

sub valide_source_tex {
    $projet{'modifie'}=1; print "* valide_source_tex\n" if($debug);
    $w{'preparation_etats'}->set_sensitive(-f localise($projet{'texsrc'}));

    if(is_local($projet{'texsrc'})) {
	$w{'edition_latex'}->show();
    } else {
	$w{'edition_latex'}->hide();
    }

    detecte_documents();
}

sub source_latex_choisir {
    my $gap=Gtk2::GladeXML->new($glade_xml,'source_latex_dialog');
    $gap->signal_autoconnect_from_package('main');
    $w{'source_latex_gap'}=$gap;
    for(qw/source_latex_dialog/) {
	$w{$_}=$gap->get_widget($_);
    }
}

sub source_latex_quit1 {
    $w{'source_latex_dialog'}->destroy();
}

sub source_latex_choixfich {
    my ($folder)=@_;
    my $gap=Gtk2::GladeXML->new($glade_xml,'source_latex_choix');
    $gap->signal_autoconnect_from_package('main');
    for(qw/source_latex_choix/) {
	$w{$_}=$gap->get_widget($_);
    }
    $w{'source_latex_choix'}->set_current_folder($folder);
}

my @modeles=();
my %modeles_i=();

sub charge_modeles {
    return if($#modeles>=0);
    opendir(DIR, $o{'rep_modeles'});
    my @ms = grep { /\.tex$/ && -f $o{'rep_modeles'}."/$_" } readdir(DIR);
    closedir DIR;
    for my $m (@ms) {
	my $d={'id'=>$m,
	       'fichier'=>$o{'rep_modeles'}."/$m",
	   };
	my $mt=$o{'rep_modeles'}."/$m";
	$mt =~ s/\.tex$/.txt/;
	if(-f $mt) {
	    open(DESC,"<:encoding(UTF-8)",$mt);
	  LIG: while(<DESC>) {
	      chomp;
	      s/\#.*//;
	      next LIG if(!$_);
	      $d->{'desc'}.=$_;
	  }
	} else {
	    $d->{'desc'}='(aucune description)';
	}
	#print "MOD : $m\n";
	push @modeles,$d;
    }
}

sub source_latex_2 {
    my %bouton;
    for (qw/new choix vide/) {
	$bouton{$_}=$w{'source_latex_gap'}->get_widget('sl_type_'.$_)->get_active();
    }
    $w{'source_latex_dialog'}->destroy();
    if($bouton{'new'}) {
	#source_latex_choixfich($o{'rep_modeles'});
	my $g=Gtk2::GladeXML->new($glade_xml,'source_latex_modele');
	$g->signal_autoconnect_from_package('main');
	for(qw/source_latex_modele modeles_liste modeles_description/) {
	    $w{$_}=$g->get_widget($_);
	}
	charge_modeles();
	my $modeles_store = Gtk2::ListStore->new ('Glib::String');
	for my $i (0..$#modeles) {
	    #print "$i->".$modeles[$i]->{'id'}."\n";
	    $modeles_store->set($modeles_store->append(),LISTE_TXT,
				$modeles[$i]->{'id'});
	    
	    $modeles_i{$modeles[$i]->{'id'}}=$i;
	}
	$w{'modeles_liste'}->set_model($modeles_store);
	my $renderer=Gtk2::CellRendererText->new;
	my $column = Gtk2::TreeViewColumn->new_with_attributes("mod�le",
							       $renderer,
							       text=> LISTE_TXT );
	$w{'modeles_liste'}->append_column ($column);
	$w{'modeles_liste'}->get_selection->signal_connect("changed",\&source_latex_mmaj);
    } elsif($bouton{'choix'}) {
	source_latex_choixfich(Glib::get_home_dir());
    } elsif($bouton{'vide'}) {
	my $sl=localise('source.tex');
	if(-e $sl) {
	    my $dialog = Gtk2::MessageDialog->new_with_markup ($w{'main_window'},
							       'destroy-with-parent',
							       'error', # message type
							       'ok', # which set of buttons?
							       sprintf("Un fichier <i>source.tex</i> existe d�j� dans le r�pertoire du projet %s. Je ne l'ai pas effac� et il servira de fichier source.",$projet{'nom'}));
	    $dialog->run;
	    $dialog->destroy;      
	    
	    $projet{'texsrc'}='source.tex';
	    set_source_tex();
	} else {
	    open(FV,">$sl");
	    close(FV);
	    $projet{'texsrc'}='source.tex';
	    set_source_tex();
	}
	
    }
}

sub source_latex_mmaj {
    my $i=$w{'modeles_liste'}->get_selection()->get_selected_rows()->get_indices();
    $w{'modeles_description'}->get_buffer->set_text($modeles[$i]->{'desc'});
}

sub source_latex_quit2 {
    $w{'source_latex_choix'}->destroy();
}

sub source_latex_quit2m {
    $w{'source_latex_modele'}->destroy();
}

sub source_latex_ok {
    my $f=$w{'source_latex_choix'}->get_filename();
    print "Source $f\n";
    $projet{'texsrc'}=$f;
    $w{'source_latex_choix'}->destroy();
    set_source_tex(1);
}

sub source_latex_okm {
    my @i=$w{'modeles_liste'}->get_selection()->get_selected_rows()->get_indices();
    $w{'source_latex_modele'}->destroy();
    if(@i) {
	$projet{'texsrc'}=$modeles[$i[0]]->{'fichier'};
	set_source_tex(1);
    }
}

# copie en changeant eventuellement d'encodage
sub copy_latex {
    my ($src,$dest)=@_;
    # 1) reperage du inputenc dans le source
    my $i='';
    open(SRC,$src);
  LIG: while(<SRC>) {
      s/%.*//;
      if(/\\usepackage\[([^\]]*)\]\{inputenc\}/) {
	  $i=$1;
	  last LIG;
      }
  }
    close(SRC);

    my $ie=get_enc($i);
    my $id=get_enc($o{'encodage_latex'});
    if($ie && $id && $ie->{'iso'} ne $id->{'iso'}) {
	print "Reencodage $ie->{'iso'} => $id->{'iso'}\n";
	open(SRC,"<:encoding($ie->{'iso'})",$src) or return('');
	open(DEST,">:encoding($id->{'iso'})",$dest) or close(SRC),return('');
	while(<SRC>) {
	    chomp;
	    s/\\usepackage\[([^\]]*)\]\{inputenc\}/\\usepackage[$id->{'inputenc'}]{inputenc}/;
	    print DEST "$_\n";
	}
	close(DEST);
	close(SRC);
	return(1);
    } else {
	return(copy($src,$dest));
    }
}

sub importe_source {
    my ($fxa,$fxb,$fb) = splitpath($projet{'texsrc'});
    my $dest=localise($fb);

    # fichier deja dans le repertoire projet...
    return() if(is_local($projet{'texsrc'},1));

    if(-f $dest) {
	my $dialog = Gtk2::MessageDialog->new ($w{'main_window'},
					       'destroy-with-parent',
					       'error', # message type
					       'yes-no', # which set of buttons?
					       "Le fichier %s existe d�j� dans le r�pertoire projet : voulez-vous �craser son ancien contenu ? Cliquez sur oui pour remplacer le fichier pr�-existant par celui que vous venez de s�lectionner, ou sur non pour annuler l'import du fichier source.",$fb);
	my $reponse=$dialog->run;
	$dialog->destroy;      

	if($reponse eq 'no') {
	    return(0);
	} 
    }

    if(copy_latex($projet{'texsrc'},$dest)) {
	$projet{'texsrc'}=$fb;
	set_source_tex();
	my $dialog = Gtk2::MessageDialog->new ($w{'main_window'},
					       'destroy-with-parent',
					       'info', # message type
					       'ok', # which set of buttons?
					       "Le fichier LaTeX a �t� copi� dans le r�pertoire projet. Vous pouvez maintenant l'�diter soit en utilisant le bouton \"�diter le fichier LaTeX\", soit directement gr�ce au logiciel de votre choix.");
	$dialog->run;
	$dialog->destroy;   
    } else {
	my $dialog = Gtk2::MessageDialog->new ($w{'main_window'},
					       'destroy-with-parent',
					       'error', # message type
					       'ok', # which set of buttons?
					       "Erreur durant la copie du fichier source : %s",$!);
	$dialog->run;
	$dialog->destroy;      
    }
}

sub edite_source {
    my $f=localise($projet{'texsrc'});
    print "Edition $f...\n";
    if(fork()==0) {
	exec($o{'tex_editor'},$f);
    }
}

sub valide_projet {
    set_source_tex();
    $w{'liste'}->set_filename($projet{'listeetudiants'});


    $mep_list=AMC::MEPList::new(localise($projet{'mep'}),
				'brut'=>1,
				'saved'=>localise($mep_saved));

    detecte_mep();

    $an_list=AMC::ANList::new(localise($projet{'cr'}),
			      'brut'=>1,
			      'saved'=>localise($an_saved));
    detecte_analyse('premier'=>1);

    print "Options correction : MB".$projet{'maj_bareme'}."\n" if($debug);
    $w{'maj_bareme'}->set_active($projet{'maj_bareme'});

    #transmet_pref($gui,'notation',\%projet);

    my $t=$w{'main_window'}->get_title();
    $t.= ' - projet '.$projet{'nom'} 
        if(!($t =~ s/-.*/- projet $projet{'nom'}/));
    $w{'main_window'}->set_title($t);

    noter_resultat();

    valide_liste('noinfo'=>1,'nomodif'=>1);
}

sub projet_ouvre {
    my ($proj,$deja)=(@_);

    if($proj) {
	
	quitte_projet();

	if(!$deja) {
	    print "Ouverture du projet $proj...\n";
	    
	    %projet=%{XMLin(fich_options($proj),SuppressEmpty => '')};
	}
	
	$projet{'nom'}=$proj;

	for my $sous ('',qw:cr cr/corrections cr/corrections/jpg cr/corrections/pdf mep scans:) {
	    my $rep=$o{'rep_projets'}."/$proj/$sous";
	    if(! -x $rep) {
		print "Creation du repertoire $rep...\n";
		mkdir($rep);
	    }
	}
    
	for my $k (keys %projet_defaut) {
	    if(! exists($projet{$k})) {
		$projet{$k}=$projet_defaut{$k};
		print "Nouveau parametre : $k\n";
	    }
	}

	#print Dumper(\%projet)."\n";
	$w{'onglets_projet'}->set_sensitive(1);

	valide_projet();

	$projet{'modifie'}='';

	# choix fichier latex si nouveau projet...
	if(! $projet{'texsrc'}) {
	    source_latex_choisir();
	}

    }
}

sub quitte_projet {
    if($projet{'nom'}) {
	
	valide_options_notation();
	
	if($projet{'modifie'}) {
	    my $dialog = Gtk2::MessageDialog->new_with_markup ($w{'main_window'},
						   'destroy-with-parent',
						   'question', # message type
						   'yes-no', # which set of buttons?
						   sprintf("Vous n'avez pas sauvegard� les options du projet <i>%s</i>, qui ont pourtant �t� modifi�es : voulez-vous le faire avant de le quitter ?",$projet{'nom'}));
	    my $reponse=$dialog->run;
	    $dialog->destroy;      
	    
	    if($reponse eq 'yes') {
		projet_sauve();
	    } 
	}
    }
}

sub quitter {
    my $ok=0;
    my $reponse='';

    quitte_projet();

    if($o{'conserve_taille'}) {
	my ($x,$y)=$w{'main_window'}->get_size();
	if(!$o{'taille_x_main'} || !$o{'taille_y_main'}
	   || $x != $o{'taille_x_main'} || $y != $o{'taille_y_main'}) {
	    $o{'taille_x_main'}=$x;
	    $o{'taille_y_main'}=$y;
	    $o{'modifie'}=1;
	    $ok=1;
	}
    }

    if($o{'modifie'}) {
	if(!$ok) {
	    my $dialog = Gtk2::MessageDialog->new_with_markup ($w{'main_window'},
							       'destroy-with-parent',
							       'question', # message type
							       'yes-no', # which set of buttons?
							       "Vous n'avez pas sauvegard� les options g�n�rales, qui ont pourtant �t� modifi�es : voulez-vous le faire avant de le quitter ?");
	    $reponse=$dialog->run;
	    $dialog->destroy;      
	}
	
	if($reponse eq 'yes' || $ok) {
	    sauve_pref_generales();
	} 
    }

    Gtk2->main_quit;
    
}

$gui->signal_autoconnect_from_package('main');

if($o{'conserve_taille'} && $o{'taille_x_main'} && $o{'taille_y_main'}) {
    $w{'main_window'}->resize($o{'taille_x_main'},$o{'taille_y_main'});
}

###

projet_ouvre($ARGV[0]);

test_commandes();

Gtk2->main();

1;

__END__

=head1 AMC-gui.pl

Interface graphique de gestion de projet de QCM automatique

=head1 SYNOPSIS

  AMC-gui.pl [projet]

=head1 OPTIONS

B<AMC-gui.pl> a un unique param�tre optionnel : le nom du projet � ouvrir
au lancement.

=head1 AUTEUR

Alexis Bienvenue <paamc@passoire.fr>

=cut

