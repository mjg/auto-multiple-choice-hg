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

package AMC::Export::CSV;

use AMC::Basic;
use AMC::Export;

@ISA=("AMC::Export");

sub new {
    my $class = shift;
    my $self  = $class->SUPER::new();
    $self->{'out.encodage'}='utf-8';
    $self->{'out.separateur'}=",";
    $self->{'out.decimal'}=",";
    $self->{'out.entoure'}="\"";
    $self->{'out.cochees'}="";
    bless ($self, $class);
    return $self;
}

sub parse_num {
    my ($self,$n)=@_;
    if($self->{'out.decimal'} ne '.') {
	$n =~ s/\./$self->{'out.decimal'}/;
    }
    return($self->parse_string($n));
}

sub parse_string {
    my ($self,$s)=@_;
    if($self->{'out.entoure'}) {
	$s =~ s/$self->{'out.entoure'}/$self->{'out.entoure'}$self->{'out.entoure'}/g;
	$s=$self->{'out.entoure'}.$s.$self->{'out.entoure'};
    }
    return($s);
}

sub export {
    my ($self,$fichier)=@_;
    my $sep=$self->{'out.separateur'};

    $sep="\t" if($sep =~ /^tab$/i);

    $self->pre_process();

    open(OUT,">:encoding(".$self->{'out.encodage'}.")",$fichier);

    my @comp_keys;

    if($self->{'out.cochees'}) {
	@comp_keys=map { ($_,"TICKED:$_") } @{$self->{'keys'}};
	$self->{'out.entoure'}="\"" if(!$self->{'out.entoure'});
    } else {
	@comp_keys=@{$self->{'keys'}};
    }

    my @cont=();

    if($self->{'liste_key'}) { 
	push @cont,'_ASSOC_';
	print OUT $self->parse_string("A:".$self->{'liste_key'}).$sep;
    }

    push @cont,(qw/_NOM_ _NOTE_ _ID_/,@comp_keys,@{$self->{'codes'}});

    print OUT join($sep,
		   map  { $self->parse_string($_) }
		   (map { translate_column_title($_); } ("nom","note","copie"),
		    @comp_keys,
		    @{$self->{'codes'}}))."\n";
    
    for my $etu (@{$self->{'copies'}}) {
	print OUT join($sep,
		       map { 
			   my $k=$_;
			   my $c=$self->{'c'}->{$etu}->{$k};
			   if($k =~ /^_(NOM|ASSOC)_$/) {
			       $c=$self->parse_string($c);
			   } elsif($k =~ /^_ID_$/) {
			       $c=$self->parse_string(translate_id_name($c));
			   } elsif($k =~ /^TICKED:/) {
			       $c=$self->parse_string($c);
			   } else {
			       $c=$self->parse_num($c) if($c ne '');
			   }
			   $c 
		       } @cont)."\n";
    }
    
    close(OUT);
}

1;
