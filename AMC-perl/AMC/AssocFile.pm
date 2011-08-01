#
# Copyright (C) 2009-2010 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::AssocFile;

use AMC::Basic;

use IO::File;
use XML::Simple;
use Data::Dumper;

my $VERSION=1;

my %type_ok=('auto'=>1,
	     'manuel'=>1);

sub new {
    my ($f,%o)=@_;
    my $self={'file'=>$f,
	      'a'=>{'copie'=>{},
		    'liste_key'=>'', # cle dans la liste de noms utilisee pour identifier les noms
		    'notes_id'=>'', # code d'identification auto
		    'version'=>$VERSION,
		},
	      'maj'=>0,
	      'encodage'=>'utf-8',
	  };

    for (keys %o) {
	$self->{$_}=$o{$_} if(defined($self->{$_}));
	$self->{'a'}->{$_}=$o{$_} if(defined($self->{'a'}->{$_}));
    }

    bless $self;
    return($self);
}

sub load {
    my $self=shift;
    my $a='';
    
    if(-s $self->{'file'}) {
	my $i=IO::File->new($self->{'file'},"<:encoding(".$self->{'encodage'}.")");
	$a=XMLin($i,'ForceArray'=>1,'KeyAttr'=>['id']);
	if(ref($a->{'copie'}) ne 'HASH') {
	    $a->{'copie'}={};
	}
	$i->close();
    }

    my $ok=1;
    for (qw/version liste_key notes_id/) {
	if(defined($self->{'a'}->{$_}) && ($self->{'a'}->{$_})
	   && (!defined($a->{$_}) || ($self->{'a'}->{$_} ne $a->{$_})) ) {
	    debug "*** variable mismatch in associations file: $_ = $self->{'a'}->{$_} | $a->{$_}\n";
	    $ok=0;
	}
    }
    if($ok) {
	$self->{'a'}=$a;
	$self->{'maj'}=0;
    }
    return($ok);
}

sub save {
    my $self=shift;

    my $i=IO::File->new($self->{'file'},">:encoding(".$self->{'encodage'}.")");
    XMLout($self->{'a'},
	   'OutputFile'=>$i,'RootName'=>'association',
	   'XMLDecl'=>'<?xml version="1.0" encoding="'.$self->{'encodage'}.'" standalone="yes"?>',
	   'KeyAttr'=>['id']);
    $i->close();
}

sub print {
    my $self=shift;

    print Dumper($self->{'a'});
}

sub get_param {
    my ($self,$p)=@_;
    print STDERR "[ASSOC] no parameter value: $p\n" if(!defined($self->{'a'}->{$p}));
    return($self->{'a'}->{$p});
}

sub get {
    my ($self,$type,$copie)=@_;
    die "Unknown type : $type" if(!$type_ok{$type});
    return($self->{'a'}->{'copie'}->{$copie}->{$type});
}

sub effectif {
    my ($self,$copie)=@_;
    my $e=$self->{'a'}->{'copie'}->{$copie};
    my $v=($e->{'manuel'} ? $e->{'manuel'} : $e->{'auto'});
    return($v && ($v eq 'NONE') ? '' : $v );
}

sub counts {
    my ($self)=@_;
    my ($auto,$man,$both)=(0,0,0);
    for my $c ($self->ids()) {
	my $e=$self->{'a'}->{'copie'}->{$c};
	$man++ if($e->{'manuel'});
	$auto++ if($e->{'auto'});
	$both++ if($e->{'auto'} && $e->{'manuel'});
    }
    return($auto,$man,$both);
}

sub maj { # actualisation des donnees induites
    my ($self)=@_;
    if(!$self->{'maj'}) {
	# liste des codes associes avec nb de sources
	$self->{'dest'}={};
	for($self->ids()) {
	    my $k=$self->effectif($_);
	    push @{$self->{'dest'}->{$k}},$_ if($k);
	}

	$self->{'maj'}=1;
    }
}

sub inverse {
    my ($self,$id)=@_;
    return() if(!$id);
    $self->maj();
    if($self->{'dest'}->{$id}) {
	return(@{$self->{'dest'}->{$id}});
    } else {
	#print STDERR Dumper($self->{'dest'});
	return();
    }
}

sub etat { # 0: aucune assoc 1: une assoc valide 2: une assoc multiple
    my ($self,$copie)=@_;
    $self->maj();
    my $d=$self->effectif($copie);
    if($d) {
	return($#{$self->{'dest'}->{$d}} == 0 ? 1 : 2);
    } else {
	return(0);
    }
}

sub set {
    my ($self,$type,$copie,$valeur)=@_;
    die "Unknown type : $type" if(!$type_ok{$type});
    $self->{'a'}->{'copie'}->{$copie}->{$type}=$valeur;
    $self->{'maj'}=0;
}

sub ids {
    my ($self)=@_;

    return(keys %{$self->{'a'}->{'copie'}});
}

sub efface {
    my ($self,$type,$copie)=@_;
    if(defined($self->{'a'}->{'copie'}->{$copie}->{$type})) {
	delete($self->{'a'}->{'copie'}->{$copie}->{$type});
	$self->{'maj'}=0;
    }
}

sub clear {
    my ($self,$type)=@_;
    die "Unknown type : $type" if(!$type_ok{$type});
    
    for my $i ($self->ids()) {
	delete($self->{'a'}->{'copie'}->{$i}->{$type});
    }
    $self->{'maj'}=0;
}

1;


