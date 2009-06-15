#! /usr/bin/perl -w

package AMC::Gui::PageArea;

use Gtk2;

@ISA=("Gtk2::DrawingArea");

sub add_feuille {
    my ($self,$coul)=@_;
    bless($self,"AMC::Gui::PageArea");

    $coul='red' if(!$coul);

    $self->{'i-file'}='';
    $self->{'i-src'}='';
    $self->{'tx'}=1;
    $self->{'ty'}=1;

    $self->{'case'}='';
    $self->{'coches'}='';

    $self->{'gc'} = Gtk2::Gdk::GC->new($self->window);

    $self->{'color'}= Gtk2::Gdk::Color->parse($coul);
    $self->window->get_colormap->alloc_color($self->{'color'},TRUE,TRUE);

    return($self);
}

sub set_image {
    my ($self,$image,$lay,$coches)=@_;
    $self->{'i-file'}=$image;
    $self->{'i-src'}=Gtk2::Gdk::Pixbuf->new_from_file($image);
    $self->{'lay'}=$lay;
    $self->{'coches'}=$coches;
    $self->{'modifs'}=0;
    $self->window->show;
}

sub modifs {
    my $self=shift;
    return($self->{'modifs'});
}

sub sync {
    my $self=shift;
    $self->{'modifs'}=0;
}

sub modif {
    my $self=shift;
    $self->{'modifs'}=1;
}

sub choix {
  my ($self,$event)=(@_);

  if($self->{'lay'}->{'case'}) {
      
      if ($event->button == 1) {
	  my ($x,$y)=$event->coords;
	  print "Clic $x $y\n" if($self->{'debug'});
	  for my $i (0..$#{$self->{'lay'}->{'case'}}) {
	      
	      my $case=$self->{'lay'}->{'case'}->[$i];
	      if($x<=$case->{'xmax'}*$self->{'rx'} && $x>=$case->{'xmin'}*$self->{'rx'}
		 && $y<=$case->{'ymax'}*$self->{'ry'} && $y>=$case->{'ymin'}*$self->{'ry'}) {
		  $self->{'modifs'}=1;

		  print " -> case $i\n" if($self->{'debug'});
		  $self->{'coches'}->[$i]=!$self->{'coches'}->[$i];

		  $self->window->show;
	      }
	  }
      }

  }
  return TRUE;
}

sub expose_drawing {
    my ($self,$evenement,@donnees)=@_;  
    my $r=$self->allocation();

    return() if(!$self->{'i-src'});

    $self->{'tx'}=$r->width;
    $self->{'ty'}=$r->height;

    my $sx=$self->{'tx'}/$self->{'i-src'}->get_width;
    my $sy=$self->{'ty'}/$self->{'i-src'}->get_height;

    if($sx<$sy) {
	$self->{'ty'}=int($self->{'i-src'}->get_height*$sx);
	$sy=$self->{'ty'}/$self->{'i-src'}->get_height;
    }
    if($sx>$sy) {
	$self->{'tx'}=int($self->{'i-src'}->get_width*$sy);
	$sx=$self->{'tx'}/$self->{'i-src'}->get_width;
    }

    return() if($self->{'tx'}<=0 || $self->{'ty'}<=0);

    my $i=Gtk2::Gdk::Pixbuf->new(GDK_COLORSPACE_RGB,0,8,$self->{'tx'},$self->{'ty'});

    $self->{'i-src'}->scale($i,0,0,$self->{'tx'},$self->{'ty'},0,0,
			    $sx,$sy,
			    GDK_INTERP_BILINEAR);

    $i->render_to_drawable($self->window,
			   $self->{'gc'},
			   0,0,0,0,
			   $self->{'tx'},
			   $self->{'ty'},
			   'none',0,0);

    ## dessin des cases

    if($self->{'lay'}->{'case'}) {

	$self->{'rx'}=$self->{'tx'}/$self->{'lay'}->{'tx'};
	$self->{'ry'}=$self->{'ty'}/$self->{'lay'}->{'ty'};

	$self->{'gc'}->set_foreground($self->{'color'});

	for my $i (0..$#{$self->{'lay'}->{'case'}}) {
	    my $case=$self->{'lay'}->{'case'}->[$i];
	    my $coche=$self->{'coches'}->[$i];

	    $self->window->draw_rectangle(
					  $self->{'gc'},
					  $coche,
					  $case->{'xmin'}*$self->{'rx'},
					  $case->{'ymin'}*$self->{'ry'},
					  ($case->{'xmax'}-$case->{'xmin'})*$self->{'rx'},
					  ($case->{'ymax'}-$case->{'ymin'})*$self->{'ry'}
					  );
	    
	}
    }
}

1;
