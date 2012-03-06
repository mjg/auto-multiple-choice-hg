#
# Copyright (C) 2012 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::Filter::register;

use AMC::Basic;

sub new {
    my $class = shift;
    my $self={};
    bless ($self, $class);
    return $self;
}

sub name {
  return("empty");
}

sub configure {
  my ($self,$options_project);
}

sub description {
  return("Base class Filter");
}

sub file_patterns {
  return();
}

sub doc_url {
  return("");
}

sub needs_latex_package {
  return();
}

sub needs_command {
  return();
}

sub needs_font {
  return([{'type'=>'fontconfig',
	   'family'=>[]}, # <--  needs one of the fonts in the list
	 ]);
}

##############################################################

sub missing_latex_packages {
  my ($self)=@_;
  my @mp=();
  for my $p ($self->needs_latex_package()) {
    my $ok=0;
    open KW,"-|","kpsewhich","-all","$p.sty";
    while(<FC>) { chomp();$ok=1 if(/./); }
    close(KW);
    push @mp,$p if(!$ok);
  }
  return(@mp);
}

sub missing_commands {
  my ($self)=@_;
  my @mc=();
  for my $c ($self->needs_command()) {
    push @mc,$c if(!commande_accessible($c));
  }
  return(@mc);
}

sub missing_fonts {
  my ($self)=@_;
  my @mf=();
  my $fonts=$self->needs_font;
  for my $spec (@$fonts) {
    if($spec->{'type'} =~ /fontconfig/i && @{$spec->{'family'}}) {
      if(commande_accessible("fc-list")) {
	my $ok=0;
	for my $f (@{$spec->{'family'}}) {
	  open FC,"-|","fc-list",$f,"family";
	  while(<FC>) { chomp();$ok=1 if(/./); }
	  close FC;
	}
	push @mf,$spec if(!$ok);
      }
    }
  }
  return(@mf);
}

1;
