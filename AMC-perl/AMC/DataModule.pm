# -*- perl -*-
#
# Copyright (C) 2011 Alexis Bienvenue <paamc@passoire.fr>
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

package AMC::DataModule;

# AMC::DataModule is the base class for modules written to be loaded
# by AMC::Data.

# A module XXX is a SQLite database that contains at least a
# 'variable' table for internal use, associated with methods written
# for a AMC::DataModule::XXX class. The tables version number is
# stored in the variable table.

use AMC::Basic;

# a AMC::DataModule object is a branch of a AMC::Data object, and
# stores its root in $self->{'data'}

sub new {
    my ($class,$data,%oo)=@_;

    my $self=
      {
       'data'=>$data,
       'name'=>'',
       'statements'=>{},
      };

    for(keys %oo) {
	$self->{$_}=$oo{$_} if(exists($self->{$_}));
    }

    if(!$self->{'name'} && $class =~ /::([^:]+)$/) {
	$self->{'name'}=$1;
    }	

    bless($self,$class);

    $self->define_statements;
    debug "Checking database version...";
    $self->version_check;

    return $self;
}

# dbh returns the DBI object corresponding to the SQLite session
# associated with the module.

sub dbh {
    my ($self)=@_;
    return $self->{'data'}->dbh;
}

# table($table_subname) gives a table name to use for some particular
# module data.
#
# table($table_subname,$module_name) gives the table name
# corresponding to another module

sub table {
    my ($self,$table_subname,$module_name)=@_;
    $module_name=$self->{'name'} if(!$module_name);
    return($module_name.".".$module_name."_".$table_subname);
}


# sql_quote($string) can be used to quote a string before including it
# in a SQL query.

sub sql_quote {
    my ($self,$string)=@_;
    return($self->{'data'}->sql_quote($string));
}

# sql_do($sql,@bind) executes the SQL query $sql, replacing ? by the
# elements of @bind.

sub sql_do {
    my ($self,$sql)=@_;
    $self->{'data'}->sql_do($sql);
}

# sql_single($sql,@bind) calls the SQL query $sql (SQL string or
# statement prepared by DBI) and returns a single value answer. In the
# query, ? are replaced by the values from @bind.

sub sql_single {
    my ($self,$sql,@bind)=@_;
    my $x=$self->dbh->selectrow_arrayref($sql,{},@bind);
    if($x) {
	return($x->[0]);
    } else {
	return(undef);
    }
}

# same as sql_single, but returns an array with all the rows of the first
# column (in fact there is often one only column in the query result)
# of the result.

sub sql_list {
    my ($self,$sql,@bind)=@_;
    my $x=$self->dbh->selectcol_arrayref($sql,{},@bind);
    if($x) {
	return(@$x);
    } else {
	return(undef);
    }
}

# same as sql_single, but returns an array with all the columns of the first
# row of the result.

sub sql_row {
    my ($self,$sql,@bind)=@_;
    my $x=$self->dbh->selectrow_arrayref($sql,{},@bind);
    if($x) {
	return(@$x);
    } else {
	return(undef);
    }
}

# _embedded versions of the last two methods embeds these methods in a
# read transaction

sub sql_single_embedded {
    my ($self,$sql,@bind)=@_;
    $self->begin_read_transaction;
    my $r=$self->sql_single($sql,@bind);
    $self->end_transaction;
    return($r);
}

sub sql_list_embedded {
    my ($self,$sql,@bind)=@_;
    $self->begin_read_transaction;
    my @r=$self->sql_list($sql,@bind);
    $self->end_transaction;
    return(@r);
}

# define_statements defines all the SQL statements often used by the
# module - it is to be overloaded by inherited AMC::DataModule::XXX classes.

sub define_statements {
}

# statement($sid) returns a prepared statement from the SQL string
# named with ID $sid, defined by define_statements. The statement is
# prepared only once, and only prepared if used.

sub statement {
    my ($self,$sid)=@_;
    my $s=$self->{'statements'}->{$sid};
    if($s->{'s'}) {
	return($s->{'s'});
    } elsif($s->{'sql'}) {
      debug "Preparing statement $sid";
	$s->{'s'}=$self->dbh->prepare($s->{'sql'});
	return($s->{'s'});
    } else {
	debug_and_stderr("Undefined SQL statement: $sid");
    }
}

# query($query,@bind) calls the SQL query named $query (see the
# available query names in the define_statements function) and returns
# a single value answer. In the query statement, ? are replaced by the
# values from @bind.

sub query {
    my ($self,$query,@bind)=@_;
    return($self->sql_single($self->statement($query),@bind));
}

# same as query, but returns an array with all the rows of the first
# column (in fact there is often one only column in the query result)
# of the result.

sub query_list {
    my ($self,$query,@bind)=@_;
    return($self->sql_list($self->statement($query),@bind));
}

# begin_transaction begins a transaction in immediate mode, to be used
# to eventually write to the database.

sub begin_transaction {
    my ($self,$key)=@_;
    my $time;
    $key='----' if(!defined($key));
    debug "Opening RW transaction for $self->{'name'} [$key]...";
    $time=time;
    $self->{'data'}->begin_transaction;
    $time=time-$time;
    debug "[$key] <-> $self->{'name'}";
    if($time>1) {
      debug_and_stderr "[$key] Waited for database RW lock $time seconds";
    }
}

# begin_read_transaction begins a transaction for reading data.

sub begin_read_transaction {
    my ($self,$key)=@_;
    my $time;
    $key='----' if(!defined($key));
    debug "Opening RO transaction for $self->{'name'} [$key]...";
    $time=time;
    $self->{'data'}->begin_read_transaction;
    $time=time-$time;
    debug "[$key] <-  $self->{'name'}";
    if($time>1) {
      debug_and_stderr "[$key] Waited for database R lock $time seconds";
    }
}

# end_transaction end the transaction.

sub end_transaction {
    my ($self,$key)=@_;
    $key='----' if(!defined($key));
    debug "Closing transaction for $self->{'name'}...";
    $self->{'data'}->end_transaction;
    debug "[$key]  X  $self->{'name'}";
}

# variable($name) returns the value of variable $name, stored in the
# table variable in the module database.
#
# variable($name,$value) sets the value of variable $name.

sub variable {
    my ($self,$name,$value)=@_;
    my $vt=$self->table("variables");
    my $x=$self->dbh->selectrow_arrayref("SELECT value FROM $vt WHERE name=".
					 $self->sql_quote($name));
    if(defined($value)) {
	if($x) {
	    $self->sql_do("UPDATE $vt SET value=".
			  $self->sql_quote($value)." WHERE name=".
			  $self->sql_quote($name));
	} else {
	    $self->sql_do("INSERT INTO $vt (name,value) VALUES (".
			  $self->sql_quote($name).",".
			  $self->sql_quote($value).")");
	}
    } else {
	return($x->[0]);
    }
}

# The same, but embedded in a SQL transaction

sub variable_transaction {
    my ($self,$name,$value)=@_;
    my $vt=$self->table("variables");
    $self->begin_read_transaction('vTRS');
    my $x=$self->dbh->selectrow_arrayref("SELECT value FROM $vt WHERE name=".
					 $self->sql_quote($name));
    $self->end_transaction('vTRS');
    if(defined($value) && $value ne $x->[0]) {
      $self->begin_transaction('sTRS');
      if($x) {
	$self->sql_do("UPDATE $vt SET value=".
		      $self->sql_quote($value)." WHERE name=".
		      $self->sql_quote($name));
      } else {
	$self->sql_do("INSERT INTO $vt (name,value) VALUES (".
		      $self->sql_quote($name).",".
		      $self->sql_quote($value).")");
      }
      $self->end_transaction('sTRS');
    } else {
	return($x->[0]);
    }
}

# clear_variables clear all variables values that are not used
# internally by the module (keeps the 'version' variable, for
# exemple).

sub clear_variables {
  my ($self)=@_;
  $self->sql_do("DELETE FROM ".$self->table("variables")." WHERE name != 'version'");
}

# version_check upgrades the module database to the last version.

sub version_check {
    my ($self)=@_;
    my $vt=$self->table("variables");

    # First try with only a read transaction, so that the process is
    # not blocked if someone else is using the database.
    $self->begin_read_transaction('rVAR');
    my @vt=$self->{'data'}->sql_tables("%".$self->{'name'}."_variables");
    $self->end_transaction('rVAR');
    if(!@vt) {
      # opens a RW transaction only if necessary
      $self->begin_transaction('tVAR');
      my @vt=$self->{'data'}->sql_tables("%".$self->{'name'}."_variables");
      debug "Empty database: creating variables table";
      $self->sql_do("CREATE TABLE $vt (name TEXT, value TEXT)");
      $self->variable('version','0');
      $self->end_transaction('tVAR');
    } else {
      debug "variables table present.";
    }

    my $vu=$self->variable_transaction('version');
    my $v_before=$vu;
    my $v;
    debug "Database version: $vu";
    do {
	$v=$vu;
	$vu=$self->version_upgrade($v);
	debug("Updated data module ".$self->{'name'}." from version $v to $vu")
	  if($vu);
    } while($vu);
    $self->variable_transaction('version',$v) if($v != $v_before);
}

# version_upgrade($v) is to be overloaded by AMC::DataModule::XXX
# classes. Called with argument $v, it has to upgrade the database
# from version $v and return the version number after upgrade. If $v
# is the latest version, version_upgrade must return a false value.

sub version_upgrade {
    my ($self,$old_version)=@_;
    return('');
}

1;
