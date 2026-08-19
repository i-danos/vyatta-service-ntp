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

# Render "system ntp" into a chrony configuration.
#
# Debian 13 dropped NTP Classic: it is no longer packaged, upstream stopped
# releasing it, and the copy DANOS carried was a local build of 4.2.8p15.
# chrony is Debian's default time daemon and covers what the CLI exposes.
#
# Two leaves have no chrony equivalent and are marked deprecated in the YANG:
#   - server ... preempt: ntpd's preemptable associations have no counterpart
#     in chrony's source selection model.
#   - syslog <class> type <type>: ntpd's logconfig takes a class x type
#     matrix; chrony's "log" directive is a fixed set of switches and cannot
#     express the same granularity.
# Both are ignored here rather than approximated, so that the running
# configuration never claims to do something it does not do.

use strict;
use warnings;
use lib "/opt/vyatta/share/perl5";

use Vyatta::Config;
use Getopt::Long;
use Vyatta::Misc qw(valid_ip_addr valid_ipv6_addr);

my ($rtinstance);

GetOptions( "rtinstance=s" => \$rtinstance, );

$rtinstance = 'default' unless defined $rtinstance;

# Emit the static preamble from the base configuration, stopping where the
# generated server list begins.
while ( my $line = <STDIN> ) {
    last if ( $line =~ /^server/ );
    print $line;
}

my $cfg = new Vyatta::Config;
if ( $rtinstance eq 'default' ) {
    $cfg->setLevel("system ntp");
} else {
    $cfg->setLevel("routing routing-instance $rtinstance system ntp");
}

my %proto = ();

foreach my $server ( $cfg->listNodes("server") ) {
    my @opts = ('iburst');

    my $af = $cfg->returnValue("server $server address-family");
    if ( defined($af) ) {
        if ( $af eq "ipv6" ) {
            push @opts, 'ipv6';
            $proto{'inet6'} = 1;
        } else {
            push @opts, 'ipv4';
            $proto{'inet'} = 1;
        }
    } else {
        if ( valid_ip_addr($server) ) {
            $proto{'inet'} = 1;
        } elsif ( valid_ipv6_addr($server) ) {
            $proto{'inet6'} = 1;
        } else {

            # Possibly a DNS name - enable both.
            $proto{'inet'}  = 1;
            $proto{'inet6'} = 1;
        }
    }

    # Same spelling as ntpd for both of these.
    for my $property (qw(noselect prefer)) {
        push @opts, $property if ( $cfg->exists("server $server $property") );
    }

    push @opts, 'key ' . $cfg->returnValue("server $server keyid")
      if ( $cfg->exists("server $server keyid") );

    print "server $server ", join( ' ', @opts ), "\n";
}

my $proto_arg = "";
if ( keys %proto ) {
    $proto_arg = "--proto=" . join( ',', ( keys %proto ) );
}

# Source interface
print
`/opt/vyatta/sbin/vyatta_update_ntpsrcIntf.pl --rtinstance=$rtinstance --operation=set $proto_arg`;

print "keyfile /run/chrony/vrf/$rtinstance/chrony.keys\n";

if ( $cfg->exists("statistics") ) {
    print "\nlogdir /var/log/chrony\n";
    print "log measurements statistics tracking\n\n";
}

exit 0;
