#! /usr/bin/perl

#----- Copyright & License -----
#
# Copyright (C) 2017-2019 AT&T Intellectual Property.
# All Rights Reserved.
#
# Copyright (c) 2014-2017 by Brocade Communications Systems, Inc.
# All rights reserved.
#
# SPDX-License-Identifier: GPL-2.0-only
#
#----- Copyright & License -----

#
# Generate contents of ntp.srcIntf - Source interface configuration
#

use strict;
use warnings;
use lib "/opt/vyatta/share/perl5";
use File::Slurp;
use Getopt::Long;
use Vyatta::Configd;
use Fcntl;

my ( $operation, $rtinstance, $proto, $path, $chvrf_str );

GetOptions(
    "operation=s"  => \$operation,
    "rtinstance=s" => \$rtinstance,
    "proto=s@"     => \$proto,
);

my %protoset;
if ( $proto && scalar @$proto ) {
    %protoset = map { $_ => 1 } split( /,/, join( ',', @$proto ) );
}

$rtinstance = 'default' unless defined $rtinstance;

my $ntp_path        = "/run/chrony/vrf/$rtinstance";
my $ntp_srcIntfFile = "ntp.srcIntf";

if ( $rtinstance eq 'default' ) {
    $path      = "system ntp source-interface";
    $chvrf_str = "";
} else {
    $path = "routing routing-instance $rtinstance system ntp source-interface";
    $chvrf_str = "/usr/sbin/chvrf $rtinstance";
}

#Get source interface for NTP
sub get_src_addrs {
    my $ifname = shift;
    my ( $ipaddr, $ip6addr );
    my $cmd = "$chvrf_str ip addr show scope global dev $ifname";

    open my $ipcmd, '-|'
      or exec $cmd
      or die "ip addr command failed: $!";
    while (<$ipcmd>) {
        my ( $proto_addr, $ifaddr ) = split;
        next unless ( $proto_addr =~ /inet/ );
        my ($addr) = ( $ifaddr =~ /([^\/]+)/ );
        if ( $proto_addr eq 'inet' ) {
            next if defined($ipaddr);
            $ipaddr = $addr;
        } elsif ( $proto_addr eq 'inet6' ) {
            next if defined($ip6addr);
            $ip6addr = $addr;
        }
    }
    close $ipcmd;

    return ( $ipaddr, $ip6addr );
}

sub srcIntf_get() {
    my $filename = "$ntp_path/$ntp_srcIntfFile";
    my $row      = read_file($filename);

    print $row;
}

my $cfg = Vyatta::Configd::Client->new();
my $db  = $Vyatta::Configd::Client::AUTO;

sub srcIntf_set() {
    if ( $cfg->node_exists( $db, $path ) ) {
        my @intfcfg = $cfg->get("$path");
        my $srcIntf = $intfcfg[0];
        my $has_addr;
        if ( defined($srcIntf) ) {
            my $filename = "$ntp_path/$ntp_srcIntfFile";
            sysopen( my $fh, $filename, O_RDWR | O_CREAT, 0600 )
              or die "$filename cannot be open. $!";
            print $fh "$srcIntf:" . join(',', @$proto);
            my ( $src_ipaddr, $src_ip6addr ) = get_src_addrs($srcIntf);

            if ( ( $protoset{'inet'} ) && defined($src_ipaddr) ) {
                print "bindacqaddress $src_ipaddr\n";
                $has_addr = 1;
            }
            if ( ( $protoset{'inet6'} ) && defined($src_ip6addr) ) {
                print "bindacqaddress $src_ip6addr\n";
                $has_addr = 1;
            }
            close($fh);
        }
    } else {
        unlink "$ntp_path/$ntp_srcIntfFile";
    }
}

srcIntf_get() if ($operation eq 'get');
srcIntf_set() if ($operation eq 'set');

exit 0;
