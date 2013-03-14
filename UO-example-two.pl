#! /usr/bin/perl -i
# sogo_import_avelsieve_rules.pl
# Ron Yacketta (yacketrj at potsdam dot edu)
# 08/23/2012 - Convert Avelsieve rules into SOGo format

use Data::Dump "dd";
use Getopt::Long qw(:config auto_abbrev bundling auto_version);
use File::Basename;
use File::Path;
use File::Copy;
use DBI;
use JSON::XS;
use Net::Sieve::Script;

my $filename = basename($0);
my $num_args = scalar(@ARGV);
my $USERS    = "";
my $dbhost;
my $dbname;
my $dbuser;
my $dbpass;
my $cca;
my $add;
my $DEBUG;

GetOptions(
    'db|d=s'       => \$dbname,
    'user|u=s'     => \$dbuser,
    'cca|c=s'      => \$cca,
    'add|a=s'      => \$add,
    'password|p=s' => \$dbpass,
    'server|s=s'   => \$dbhost,
    'verbose|v'    => \$DEBUG,
    'help|h|?'     => \&help,
    '<>'           => \&help,
);

if ( !$num_args ) { help(); }

if ( $cca && $add ) { help(); }

sub help {
    print "$filename usage:\n";
    print " $filename [--db|-d] DataBase Name\n";
    print " $filename [--user|-u]  DB User\n";
    print " $filename [--password|-p]  DB User password\n";
    print " $filename [--server|-s] DB server\n";
    print " $filename [--cca|-c]  Import rules for existing user\n";
    print " $filename [--add|-a]  Add user to sogo and import rules\n";
    print " $filename [--verbose|-v]  Debug / Verbose output\n";
    print " $filename [--help|--h]    Print usage/help information.\n";
    exit;
}

my $user;
my $sdir       = "/var/sqdata";
my $home       = "/mnt/home/";
my $dir        = ".sieve/";
my $sfile      = "phpscript.sieve";
my $sogo_sieve = "sogo.sieve";

sub load_profiles {
    my @users = ();
    if ($cca) {
	if ( lc($cca) eq 'all'  ) {
		opendir (DIR,$home) or die "Cannot opendir $home: $!\n";
                my @dirs = grep {
               				/^[^\.]/ &&                                     # no dots
                                        !/lost\+found/ &&
                                        !/\.[^.]+$/ 
                                } readdir (DIR);
		closedir (DIR);
                foreach (@dirs){
			push (@users,$_);
                }		
		dd(@users) if $DEBUG;
	} else {	
        	@users = split( /\,/, $cca );
	}
    }
    if ($add) {
        @users = split( /\,/, $add );
    }
    return sort(@users);
}

sub cleanup {
    my $s = shift;
    $s =~ s/"//g;
    $s =~ s/^://g;
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;
    $s =~ s/^allof$/all/;
    $s =~ s/^anyof$/any/;
    return $s;
}

sub fix_to_cc {
    my $s = shift;
    if ( $s =~ m/\[\"to\" \"cc\"\]/ ) {
        $s = "to_or_cc";
    }
    else {
        $s = cleanup($s);
        $s =~ s/sender/from/;
    }
    return $s;
}

sub user_exists {
	my $user = shift;
	my $ret = 0;
	my $db_h = DBI->connect( "DBI:Pg:dbname=$dbname;host=$dbhost", "$dbuser", "$dbpass", { 'RaiseError' => 1 } );
        my $sth = $db_h->prepare("select c_uid from sogo_user_profile where c_uid='$user'");
        $sth->execute;
	$ret = $sth->rows;
	$sth->finish;
	return $ret;
}

sub parse_sieve_rule_file {

    my $raw  = "";
    my $js   = JSON::XS->new->allow_nonref;
    my %data = ();
    my $user = shift;

    # Pull in all the sieve rules
    seek( FH, 0, 0 );

    while (<FH>) {
        next if $_ =~ m/START_SIEVE_RULE.+END_SIEVE_RULE/;
        next if $_ =~ m/^#|^\s/;
        $raw .= $_;
    }

    my $db_h = DBI->connect( "DBI:Pg:dbname=$dbname;host=$dbhost", "$dbuser", "$dbpass", { 'RaiseError' => 1 } );

    unless ($db_h) {
        $! = 2;
        die("DB [$dbhost:$dbname] Connection problem\n");
    }

#    if( user_exists($user) ) {
#	print "Loading prefs for $user\n" if $DEBUG;
#        my $sth = $db_h->prepare("select c_defaults from sogo_user_profile where c_uid='$user'");
#        $sth->execute;
#	my $ref = $sth->fetchrow_arrayref();
#	dd($ref) if $DEBUG;
#        $data = $js->decode( @{$ref} );
#        $sth->finish;
#    }
#    else {
#        my $sth = $db_h->prepare('insert into sogo_user_profile VALUES (?)');
#        $sth->execute($user);
#        $sth->finish;
#
#    }

	unless( user_exists($user) ) {
        	my $sth = $db_h->prepare('insert into sogo_user_profile VALUES (?)');
        	$sth->execute($user);
        	$sth->finish;
    	} else {
       		print "Loading prefs for $user\n" if $DEBUG;
        	my $sth = $db_h->prepare("select c_defaults from sogo_user_profile where c_uid='$user'");
        	$sth->execute;
       		my $ref = $sth->fetchrow_arrayref();
       		dd($ref) if $DEBUG;
        	$data = $js->decode( @{$ref} );
        	$sth->finish;
	}



    my $script = Net::Sieve::Script->new($raw);

    #	@SOGoSieveFilters =	[
    #                                  {
    #                                    'actions' => [
    #                                                   {
    #                                                     'argument' => 'TESTING',
    #                                                     'method' => 'fileinto'
    #                                                   }
    #                                                 ],
    #                                    'name' => 'Testing',
    #                                    'match' => 'any',
    #                                    'rules' => [
    #                                                 {
    #                                                   'operator' => 'contains',
    #                                                   'value' => 'joe.user@domain.com',
    #                                                   'field' => 'from'
    #                                                 }
    #                                               ]
    #                                  },
    #                                  {
    #                                    'actions' => [
    #                                                   {
    #                                                     'argument' => 'TESTING',
    #                                                     'method' => 'fileinto'
    #                                                   },
    #                                                   {
    #                                                     'argument' => undef,
    #                                                     'method' => 'stop'
    #                                                   }
    #                                                 ],
    #                                    'name' => 'Another Test',
    #                                    'match' => 'any',
    #                                    'rules' => [
    #                                                 {
    #                                                   'operator' => 'contains',
    #                                                   'value' => 'fred.user@domain.edu',
    #                                                   'field' => 'from'
    #                                                 }
    #                                               ]
    #                                  }
    #				]
    my @r;
    my %t;
    my $field;
    my $header;
    foreach my $rule ( sort { $a->priority() <=> $b->priority() } @{ $script->rules() } ) {
        next if ( not defined $rule->conditions() );
        my $p = 0;
        %t = ();

        #Process 'actions'
        #{
        # fileinto  "ezProxy";
        # stop;
        #}
        foreach my $action ( @{ $rule->actions() } ) {
            next if ( !$action->command );
            my $a = $action->param;

            #$a =~ s/\./\//g;
            my $m = $action->command;
            if ( defined $action->param ) {
                $t{'actions'}[$p] = {
                    'method'   => cleanup($m),
                    'argument' => cleanup($a)
                };
            }
            else {
                $t{'actions'}[$p] = { 'method' => cleanup($m) };
            }

            $p++;
        }
        $t{'active'} = 1;

        # Process multiple 'conditions' for this rule
        # (address :contains ["to", "cc"] "rt-users@lists.bestpractical.com",
        # address :contains "From" "rt-users@lists.bestpractical.com")
        if ( defined $rule->conditions()->{'condition'} ) {
            my $o = 0;
            $t{'match'} = cleanup( $rule->conditions()->{'test'} );
            foreach my $cond ( @{ $rule->conditions()->{'condition'} } ) {
                next if ( not defined $cond->{'key_list'} );
                $t{'name'} = cleanup( $cond->{'key_list'} );
                $t{'rules'}[$o] = {
                    'operator' => lc cleanup( $cond->{'match_type'} ),
                    'value'    => lc cleanup( $cond->{'key_list'} )
                };
                if ( $rcond->{'test'} eq "header" ) {
                    $field                             = lc $cond->{'test'};
                    $header                            = lc $cond->{'header_list'};
                    $t{'rules'}[$o]->{'field'}         = fix_to_cc($field);
                    $t{'rules'}[$o]->{'custom_header'} = cleanup($header);
                }
                else {
                    $field = lc $cond->{'header_list'};
                    $t{'rules'}[$o]->{'field'} = fix_to_cc($field);
                }
                $o++;
            }
        }
        else {
            $t{'match'} = "any";
            $t{'name'}  = cleanup( $rule->conditions->{'key_list'} );
            $t{'rules'} = [
                {
                    'operator' => lc cleanup( $rule->conditions->{'match_type'} ),
                    'value'    => lc cleanup( $rule->conditions->{'key_list'} )
                }
            ];
            if ( $rule->conditions->{'test'} eq "header" ) {
                $field                            = lc $rule->conditions->{'test'};
                $header                           = lc $rule->conditions->{'header_list'};
                $t{'rules'}[0]->{'field'}         = fix_to_cc($field);
                $t{'rules'}[0]->{'custom_header'} = cleanup($header);
            }
            else {
                $field = lc $rule->conditions->{'header_list'};
                $t{'rules'}[0]->{'field'} = fix_to_cc($field);
            }
        }
        push( @r, {%t} );
    }
    $data->{'SOGoSieveFilters'} = \@r;
    print "Sieve  Rules :\n" if $DEBUG;
    dd($data) if $DEBUG;
    print "\nJSON Encoded Sieve Rules :\n" if $DEBUG;
    dd($js->encode($data)) if $DEBUG;
    $sth = $db_h->prepare( "update sogo_user_profile set c_defaults=E'" . $js->encode($data) . "' where c_uid='$user'" );
    $sth->execute or die "Cannot connect: $DBI::errstr\n";
    $db_h->disconnect();
}

sub process_sm_rules {
    my @users = load_profiles();
    print "Convert & Importing :\n";
    foreach $user (@users) {
    	open( FH, "<$home$user/$dir$sfile" ) or next ; #warn "Could not open file $home$user/$dir$sfile: $!\n";
    	print "\t $user : $home$user/$dir$sfile\n";
        parse_sieve_rule_file($user);
        close(FH);
    }
}

process_sm_rules();
