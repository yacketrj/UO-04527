#!/usr/bin/perl
# Ron Yacketta (yacketrj at potsdam dot edu)
# 08/23/2009 - Added creation of /mnt/webuser/CCA directory with symlink to /mnt/home/CCA/web 


use strict;
use Getopt::Long;
use File::Copy;
use POTS::LDAP;
use POTS::Log;
use POTS::Time;
use POTS::Mail;
use File::Path;

$SIG{__WARN__} = sub { print @_; syslog_msg(@_); };
$SIG{__DIE__} = sub { print @_; syslog_msg(@_); exit 1; };

my $HOMEVOL  = '/mnt/home';
my $WEBVOL   = '/mnt/webusers';
my $SHAREVOL = '/mnt/shares';
my $GROUPF   = '/mnt/web/swap/group';
my $CPF      = '/opt/bin/cpf';
my $LOGF     = "/var/log/fubar.log";
my $sys_au   = "sys_au_group";
my $sys_du   = "sys_du_group";
my $sys_ru   = "sys_ru_group";

my $script_name = $0;
$script_name =~ s/.*\///;

my $num_args = scalar(@ARGV);
my $add;
my $add_list;
my $delete;
my $delete_list;
my $dry_run;
my $help;
my $max_changes;
my $purge;
my $purge_list;
my $rename;
my $rename_list;
my $verbose;
GetOptions(
    "add"           => \$add,
    "add-list=s"    => \$add_list,
    "delete"        => \$delete,
    "delete-list=s" => \$delete_list,
    "dry-run"       => \$dry_run,
    "help"          => \$help,
    "max-changes=i" => \$max_changes,
    "purge"         => \$purge,
    "purge-list=s"  => \$purge_list,
    "rename"        => \$rename,
    "rename-list=s" => \$rename_list,
    "verbose"       => \$verbose,
);

if ( $help || !$num_args ) {
    print "Usage:\n";
    print " $script_name --add [--add-list=user1,user2,user3]\n";
    print " $script_name --delete [--delete-list=user1,user2,user3]\n";
    print " $script_name --rename [--rename-list=user1,user2,user3]\n";
    print " more options: [--max-changes=x] [--verbose] [--dry-run]\n";
    exit;
}

my $ldap = admin_bind();

# add users
if ( $add || $add_list ) {
    my @members;
    if ($add_list) {
        @members = split( /,/, $add_list );
    }
    else {
        @members = group_get_users( $ldap, $sys_au );
    }

    # add homedir and link to backup set
    my $i = 0;
    foreach my $uid (@members) {
        $i++;
        if ( !user_chk( $ldap, $uid ) ) { output("au $uid -> ERROR: user does not exist in ldap"); next; }
        my ( $ret0, $msg0 ) = adduser_home( $uid, $HOMEVOL ) if ( !$dry_run );
        output("au $uid home -> $msg0");
        my ( $ret1, $msg1 ) = adduser_web( $uid, $WEBVOL ) if ( !$dry_run );
        output("au $msg1");
        if ( $ret0 + $ret1 >= 2 && !$add_list ) {
            user_mod_groupdel( $ldap, $uid, $sys_au ) if ( !$dry_run );
        }
        last if ( $max_changes && $i == $max_changes );
    }
}

# delete users
if ( $delete || $delete_list ) {
    my @members;
    if ($delete_list) {
        @members = split( /,/, $delete_list );
    }
    else {
        @members = group_get_users( $ldap, $sys_du );
    }

    # move home and web to $uid.delete and remove $uid from share groups
    my $i = 0;
    foreach my $uid (@members) {
        $i++;
        my ( $ret0, $msg0 ) = deluser_home( $uid, $HOMEVOL ) if ( !$dry_run );
        output("du $uid home -> $msg0");
        my ( $ret1, $msg1 ) = deluser_web( $uid, $WEBVOL ) if ( !$dry_run );
        output("du $uid web -> $msg1");

        #		my ($ret2,$msg2) = deluser_shares($uid,$GROUPF) if (!$dry_run);
        my $ret2 = 1 if ( !$dry_run );

        #		output("du $uid shares -> $msg2");
        if ( $ret0 + $ret1 + $ret2 == 3 && !$delete_list ) {
            user_mod_groupdel( $ldap, $uid, $sys_du ) if ( !$dry_run );
        }
        last if ( $max_changes && $i == $max_changes );
    }
}

# really delete
if ( $purge || $purge_list ) {
    if ($purge_list) {
        my %members;
        foreach ( split( /,/, $purge_list ) ) {
            $members{$_} = 1;
        }
        purge( $HOMEVOL, \%members );
        purge( $WEBVOL,  \%members );
    }
    else {
        purge($HOMEVOL);
        purge($WEBVOL);
    }
}

# rename users
if ($rename) {
    my @members;
    if ($rename_list) {
        @members = split( /,/, $rename_list );
    }
    else {
        @members = group_get_users( $ldap, $sys_ru );
    }

    # rename home and web from $uidLast to $uid and rename in group file
    my $i = 0;
    foreach my $uid (@members) {
        $i++;
        if ( !user_chk( $ldap, $uid ) ) { output("ru $uid -> E: user does not exist in ldap"); next; }
        my @search = generic_search( $ldap, "ou=People", "uid=$uid", "uidLast" );
        my $uid_last;
        foreach (@search) {
            $uid_last = $$_{'uidLast'};
            last;
        }
        my ( $ret0, $msg0 ) = renuser_home( $uid, $uid_last, $HOMEVOL ) if ( !$dry_run );
        output("ru $uid home -> $msg0");
        my ( $ret1, $msg1 ) = renuser_web( $uid, $uid_last, $WEBVOL, $HOMEVOL ) if ( !$dry_run );
        output("ru $uid web -> $msg1");
        my ( $ret2, $msg2 ) = renuser_shares( $uid, $uid_last, $GROUPF ) if ( !$dry_run );
        output("ru $uid shares -> $msg2");
        if ( $ret0 + $ret1 + $ret2 >= 3 && !$rename_list ) {
            user_mod_groupdel( $ldap, $uid, $sys_ru ) if ( !$dry_run );
        }
        last if ( $max_changes && $i == $max_changes );
    }
}

unbind($ldap);

############# END MAIN #############

sub output {
    my $msg = shift;
    print "$msg\n" if ($verbose);
    log_msg( $LOGF, $msg ) if ( !$dry_run );
    syslog_msg($msg) if ( !$dry_run );
}

sub purge {
    my $vol    = shift;
    my $uidref = shift;

    opendir( DIR, $vol ) or die "Cannot opendir $vol: $!\n";
    while ( my $atom = readdir(DIR) ) {
        if ( $atom =~ m/^\./ ) { next; }
        if ( $atom =~ m/\.delete/ ) {
            my $uid = $atom;
            $uid =~ s/\.delete//;
            my $data = "$vol/$atom";

            # check against allowed uids if we restricted to purge_list
            if ($uidref) {
                if ( !exists( $$uidref{$uid} ) ) {
                    next;
                }
            }

            my $msg = "purge $uid: ";
            if ( !$dry_run ) {
                my $ret = system( "rm", "-rf", $data );
                if ($ret) {
                    output( $msg . "ERROR: deleting data $data failed" );
                }
                else {
                    output( $msg . "deleted data $data" );
                }
            }
            else {
                output($msg);
            }
        }
    }
    closedir(DIR);
}

sub adduser_home {
    my $uid      = shift;
    my $home_vol = shift;
    if ( -d "$home_vol/$uid" ) {
        return ( 1, "W: $home_vol/$uid already exists" );
    }
    if ( system( "/bin/cp", "-R", "/etc/skel", "$home_vol/$uid" ) ) {
        return ( 0, "E: copy /etc/skel to $home_vol/$uid failed" );
    }
    if ( system( "/bin/chown", "-R", "$uid:100", "$home_vol/$uid" ) ) {
        return ( 0, "E: chown $uid:100 $home_vol/$uid failed" );
    }
    if ( system( "/bin/chmod", "-R", "700", "$home_vol/$uid" ) ) {
        return ( 0, "E: chmod $home_vol/$uid failed" );
    }
    if ( system( "/opt/bin/backuplinker.pl", "home", "$uid" ) ) {
        return ( 0, "E: backuplinker.pl failed" );
    }

    return ( 1, "$home_vol/$uid" );
}

sub adduser_web {
    my $uid     = shift;
    my $web_vol = shift;

    if ( -l "$HOMEVOL/$uid/web" && -d "$web_vol/$uid" ) {
        return ( 1, "W: $HOMEVOL/$uid/web already exists" );
    }

    unless ( -d "$web_vol/$uid" ) {
        if ( !mkdir("$web_vol/$uid") ) {
            return ( 0, "E: mkdir $web_vol/$uid : $!" );
        }
        if ( system( "/bin/chown", "-R", "$uid", "$web_vol/$uid" ) ) {
            return ( 0, "E: chown -R $uid $web_vol/$uid failed" );
        }
    }

    unless ( -l "$HOMEVOL/$uid/web" ) {
        if ( !symlink( "$WEBVOL/$uid", "$HOMEVOL/$uid/web" ) ) {
            return ( 0, "E: symlink $web_vol/$uid $HOMEVOL/$uid/web : $!" );
        }
    }

    return ( 1, "linked $HOMEVOL/$uid/web to $web_vol/$uid" );
}

sub deluser_home {
    my $uid      = shift;
    my $home_vol = shift;
    if ( !-e "$home_vol/$uid" ) {
        return ( 1, "I: $home_vol/$uid does not exist" );
    }
    my $del_dir = "$home_vol/$uid.delete";
    if ( -e $del_dir ) {
        $del_dir = uncollide_filename($del_dir);
    }
    if ( !move( "$home_vol/$uid", $del_dir ) ) {
        return ( 0, "E: move $home_vol/$uid to $del_dir failed" );
    }
    return ( 1, $del_dir );
}

sub deluser_shares {
    my $uid        = shift;
    my $group_file = shift;

    # determine if user is in any groups to begin with
    if ( !`grep $uid $group_file` ) {
        return ( 1, "I: $uid has no share access" );
    }

    # remove from groups
    my @groups;
    my @groups_removed;
    open( GF, $group_file ) or return ( 0, "E: could not open $group_file: $!" );
    while (<GF>) {
        chomp;
        my $group_cur = $_;
        my ( $gname, $x, $gnum, $members_cur ) = split( /:/, $group_cur );
        my (@members_cur) = split( /,/, $members_cur );
        my @members_new;
        foreach (@members_cur) {
            if ( $_ ne $uid ) {
                push( @members_new, $_ );
            }
            else {
                push( @groups_removed, $gname );    # for logging
            }
        }
        my $members_new = join( ',', @members_new );
        my $group_new = join( ':', ( $gname, $x, $gnum, $members_new ) );
        push( @groups, $group_new );
    }
    close(GF);

    # create new group file
    my $group_file_new = "$group_file.wam";
    open( NGF, ">$group_file_new" ) or return ( 0, "E: could not write $group_file_new: $!\n" );
    foreach (@groups) {
        print NGF "$_\n";
    }
    close(NGF);

    # copy staging file into place, cpf will pick up the changes
    if ( !copy( $group_file_new, $group_file ) ) {
        return ( 0, "E: cannot copy $group_file_new to $group_file" );
    }

    return ( 1, "@groups_removed" );
}

sub deluser_web {
    my $uid     = shift;
    my $web_vol = shift;
    if ( !-e "$web_vol/$uid" ) {
        return ( 1, "I: $web_vol/$uid does not exist" );
    }
    my $del_dir = "$web_vol/$uid.delete";
    if ( -e $del_dir ) {
        $del_dir = uncollide_filename($del_dir);
    }
    if ( !move( "$web_vol/$uid", $del_dir ) ) {
        return ( 0, "E: move $web_vol/$uid to $del_dir failed" );
    }
    return ( 1, "$del_dir" );
}

sub renuser_home {
    my $uid_new  = shift;
    my $uid_old  = shift;
    my $home_vol = shift;

    #	# much too intensive search for uid_old
    #	if (!$uid_old){
    #		output("ru $uid_new -> W: scanning $home_vol for old uid");
    #		my ($name,$passwd,$uidnewn,$gidnewn,$quota,$comment,$gcos,$dir,$shell,$expire) = getpwnam($uid_new);
    #		opendir (DIR,$home_vol) or die "Cannot opendir $home_vol: $!\n";
    #		while (my $atom = readdir(DIR)){
    #			if ($atom =~ m/^\./){ next; }
    #			if ($atom =~ m/\.move|\.delete|\.purge|\.oops/){ next; }
    #			my ($dev,$ino,$mode,$nlink,$uidoldn,$gidoldn,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat("$home_vol/$atom/");
    #			if ($uidoldn == $uidnewn){
    #				$uid_old = $atom;
    #				last;
    #			}
    #		}
    #		closedir (DIR);
    #	}
    #

    if ( !$uid_old ) {
        return ( 0, "E: previous uid could not be determined" );
    }
    if ( $uid_old eq $uid_new ) {
        return ( 1, "W: old name $uid_old and new name $uid_new are identical" );
    }

    if ( -e "$home_vol/$uid_new" ) {
        return ( 1, "W: $home_vol/$uid_new already exists" );
    }
    if ( !-e "$home_vol/$uid_old" ) {
        return ( 1, "W: old home $home_vol/$uid_old does not exist" );
    }
    if ( !move( "$home_vol/$uid_old", "$home_vol/$uid_new" ) ) {
        return ( 0, "E: move $home_vol/$uid_old to $home_vol/$uid_new failed" );
    }

    # this creates links to backups under the new name, but orphans their access to their stuff under the old name
    if ( system( "rm", "-rf", "$home_vol/$uid_new/_backup" ) ) {
        return ( 0, "E: could not remove $home_vol/$uid_new/_backup" );
    }
    if ( system( "/opt/bin/backuplinker.pl", "home", "$uid_new" ) ) {
        return ( 0, "E: backuplinker.pl failed" );
    }
    return ( 1, "$home_vol/$uid_old to $home_vol/$uid_new" );
}

sub renuser_shares {
    my $uid_new    = shift;
    my $uid_old    = shift;
    my $group_file = shift;

    # determine if user is in any groups to begin with
    if ( !`grep $uid_old $group_file` ) {
        return ( 1, "W: $uid_old has no share access" );
    }

    # remove from groups
    my @groups;
    my @groups_renamed;
    open( GF, $group_file ) or return ( 0, "E: could not open $group_file: $!" );
    while (<GF>) {
        chomp;
        my $group_cur = $_;
        my ( $gname, $x, $gnum, $members_cur ) = split( /:/, $group_cur );
        my (@members_cur) = split( /,/, $members_cur );
        my @members_new;
        foreach (@members_cur) {
            if ( $_ ne $uid_old ) {
                push( @members_new, $_ );
            }
            else {
                push( @members_new,    $uid_new );
                push( @groups_renamed, $gname );     # for logging
            }
        }
        my $members_new = join( ',', @members_new );
        my $group_new = join( ':', ( $gname, $x, $gnum, $members_new ) );
        push( @groups, $group_new );
    }
    close(GF);

    # create new group file
    my $group_file_new = "$group_file.wam";
    open( NGF, ">$group_file_new" ) or return ( 0, "E: could not write $group_file_new: $!\n" );
    foreach (@groups) {
        print NGF "$_\n";
    }
    close(NGF);

    # copy new group file into place, cpf will pick up the changes
    if ( !copy( $group_file_new, $group_file ) ) {
        return ( 0, "E: cannot copy $group_file_new to $group_file" );
    }

    return ( 1, "@groups_renamed" );
}

sub renuser_web {
    my $uid_new  = shift;
    my $uid_old  = shift;
    my $web_vol  = shift;
    my $home_vol = shift;

    if ( $uid_old eq $uid_new ) {
        return ( 1, "W: old name $uid_old and new name $uid_new are identical" );
    }
    if ( -e "$web_vol/$uid_new" ) {
        return ( 1, "W: $web_vol/$uid_new already exists" );
    }
    if ( !-e "$web_vol/$uid_old" ) {
        return ( 1, "W: old webuser $web_vol/$uid_old does not exist" );
    }
    if ( !move( "$web_vol/$uid_old", "$web_vol/$uid_new" ) ) {
        return ( 0, "E: move $web_vol/$uid_old to $web_vol/$uid_new failed" );
    }

    # fix web symlink on user home assuming they have not renamed it
    if ( -l "$home_vol/$uid_new/web" ) {
        unlink("$home_vol/$uid_new/web");
        symlink( "$web_vol/$uid_new", "$home_vol/$uid_new/web" );
    }
    return ( 1, "$web_vol/$uid_old to $web_vol/$uid_new" );
}

sub uncollide_filename {
    my $file = shift;
    if ( -e $file ) {
        my $new_file = $file;
        my $i        = 1;
        while ( -e $new_file ) {
            $new_file = $file . ".$i";
            $i++;
        }
        $file = $new_file;
    }
    return $file;
}
