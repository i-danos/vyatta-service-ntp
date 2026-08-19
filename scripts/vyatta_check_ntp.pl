#!/usr/bin/perl

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

# Check the candidate configuration to see if ntp should be started.
# There must be at least one IP address configured and one ntp server.
# Interfaces that get addresses from dhcp are not considered here because
# the dhcp client handles (re)starting chronyd on its own.
#
# Return 0 if ok to start chronyd; return 1 otherwise.

use strict;
use warnings;

use Vyatta::Interface;
use Vyatta::Config;

sub get_ntp_srv_count {
    my $cfg = new Vyatta::Config;
    $cfg->setLevel('system ntp');

    my @srv = $cfg->listNodes('server');
    return scalar( @srv );
}

sub get_address_count {
    return scalar( keys Vyatta::Interface::get_cfg_addresses() );
}

exit(1) if ( get_ntp_srv_count() == 0 );
exit(1) if ( get_address_count() == 0 );
exit(0);
