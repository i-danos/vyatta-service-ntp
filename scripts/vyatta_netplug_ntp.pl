#! /usr/bin/perl

#----- Copyright & License -----
#
# Copyright (C) 2018-2020 AT&T Intellectual Property.
# All Rights Reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#
#----- Copyright & License -----

use lib "/opt/vyatta/share/perl5/";
use Getopt::Long;
use Vyatta::Configd;
use Vyatta::Interface;
use Vyatta::Misc;
use NetAddr::IP;
use File::Slurp;
use IPC::Run3 ('run3');

use strict;
use warnings;

my ( $operation, $dev, $proto, $addr, $vrf );

GetOptions(
    "operation=s" => \$operation,
    "dev=s"       => \$dev,
    "proto=s"     => \$proto,
    "addr=s"      => \$addr,
);

sub get_addr_from_ntp_conf {
    my ($line) = @_;

    chomp $line;
    $line =~ s/interface listen //;

    return NetAddr::IP->new($line);
}

# get the new interface line or 'interface drop all' based on the provided IP address
sub get_interface_lines {
    my ( $vrf, $ip, $afstr ) = @_;

    # We may have multiple addresses of the same AF on the interface.
    my @cmd = (
        '/opt/vyatta/sbin/vyatta_update_ntpsrcIntf.pl', "--rtinstance=$vrf",
        '--operation=set',                              "--proto=$afstr"
    );
    my @cfg_lines;
    my $err;
    run3 \@cmd, \undef, \@cfg_lines, \$err;

    for my $line (@cfg_lines) {
        next unless $line =~ /interface listen /;

        my $new_ip = get_addr_from_ntp_conf($line);

        return $line if $new_ip->version() == $ip->version();
    }
    return;
}

# Delete a listen address from chrony.conf
# case 1: if the address wasn't in chrony.conf then do nothing
# case 2: if the deleted address was in interface listen line:
#       case 2.1: if interface has other valid interface address with same AF
#          then replace address
#       case 2.2: if no other address on the interface with same AF and
#       it was the only interface line in chrony.conf
#          - replace the line with 'interface drop all'
#       case 2.3: if there are other address family listening in chrony.conf
#          - delete the address line
sub delete_listen_addr {
    my ( $filename, $addr, $afstr ) = @_;

    my @conf = read_file($filename);

    my $i   = 0;
    my $len = scalar @conf;

    my $ip = NetAddr::IP->new($addr);

    # delete the old address and add a drop all line if
    # this is the only address
    my $index;
    my $count = 0;
    while ( $i < $len ) {
        return if ( $conf[$i] =~ /interface drop/ );

        if ( $conf[$i] =~ /interface listen / ) {
            $count++;
            my $new_ip = get_addr_from_ntp_conf( $conf[$i] );
            if ( $ip eq $new_ip ) {
                $index = $i;
            }
        }
        $i++;
    }

    return unless defined($index);    # Nothing more to do - no change

    # We may have multiple addresses here.
    my @new_interface_lines = get_interface_lines( $vrf, $ip, $afstr );

    if ( $count == 1 ) {

        # add a drop all if $addr was the only entry.
        @new_interface_lines = ("interface drop all\n")
          unless scalar @new_interface_lines;
        splice @conf, $index, 1, @new_interface_lines;
    } else {

        # if there are more addresses just remove/replace the addr
        splice @conf, $index, 1, @new_interface_lines;
    }
    write_file( $filename, { atomic => 1 }, \@conf );
}

sub update_listen_addr {
    my ( $filename, $addr ) = @_;

    my @conf = read_file($filename);
    my $ip   = NetAddr::IP->new($addr);

    # Update address only if we don't have an interface listen with
    # a matching address family.
    my $index;
    my $need_delete = 0;
    my $i           = 0;
    my $len         = scalar @conf;

    while ( $i < $len ) {
        if ( $conf[$i] =~ /interface drop/ ) {
            $index       = $i;
            $need_delete = 1;
            last;
        }
        if ( $conf[$i] =~ /interface listen / ) {
            my $old_ip = get_addr_from_ntp_conf( $conf[$i] );
            if ( $ip->version() == $old_ip->version() ) {

                # no need to change address - we already have one
                return;
            }
            $index = $i + 1;    # Add after the last interface listen
        }
        $i++;
    }

    return unless defined($index);    # Nothing more to do - no change

    splice @conf, $index, $need_delete, ("interface listen $addr\n");
    write_file( $filename, { atomic => 1 }, \@conf );
    return;
}

sub restart_ntpd {
    my $ntp_path = "/run/chrony/vrf/$vrf";
    my $filename = "$ntp_path/chrony.conf";

    my @cmd = (
        "/opt/vyatta/sbin/vyatta_update_ntpsrcIntf.pl",
        "--rtinstance=$vrf", "--operation=get"
    );
    my $str;

    run3 \@cmd, \undef, \$str, \undef;

    my ( $srcIntf, $afstr ) = split /:/, $str;

    my @aflist = grep { $proto eq $_ } ( split /,/, $afstr );

    if ( ( $srcIntf eq $dev ) && ( scalar @aflist ) ) {
        if ( $operation eq "set" ) {
            update_listen_addr( $filename, $addr );
        } elsif ( $operation eq "del" ) {
            delete_listen_addr( $filename, $addr, $afstr );
        }
        run3(
            [
                "/opt/vyatta/sbin/vyatta_configure_ntp.pl",
                "--operation=restart_trigger",
                "--rtinstance=$vrf"
            ],
            \undef,
            undef, undef
        );
    }
    exit 0;
}

# find out which VRF the $dev belongs to
sub get_vrf {
    my $intf = new Vyatta::Interface($dev);
    $intf or die "Unknown interface name or type: $dev\n";
    my $vrf_name = $intf->vrf();

    return $vrf_name;
}

$vrf = get_vrf();
exit 0 unless -e "/run/chrony/vrf/$vrf/ntp.srcIntf";

restart_ntpd($operation);
exit 0;

