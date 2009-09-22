#! /usr/bin/perl
#
# Copyright (C) 2009 Alexis Bienvenue <paamc@passoire.fr>
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

use AMC::Basic;
use AMC::Gui::Avancement;

use Module::Runtime qw/use_module/;

use encoding 'utf8';

my $module='CSV';
my $output='';

my $fich_notes='';
my $fich_assoc='';
my $fich_noms='';
my $noms_encodage='utf-8';
my $noms_identifiant='';

GetOptions("fich-notes=s"=>\$fich_notes,
	   "fich-assoc=s"=>\$fich_assoc,
	   "fich-noms=s"=>\$fich_noms,
	   "noms-encodage=s"=>\$noms_encodage,
	   "noms-identifiant=s"=>\$noms_identifiant,
	   "output|o=s"=>\$output,
	   );
	   

$ex = use_module("AMC::Export::$module")->new();

$ex->set_options("fich",
		 "notes"=>$fich_notes,
		 "association"=>$fich_assoc,
		 "noms"=>$fich_noms,
		 );

$ex->set_options("noms",
		 "encodage"=>$noms_encodage,
		 "identifiant"=>$noms_identifiant,
		 );

$ex->export($output);
