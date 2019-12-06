#!/usr/bin/perl -w

##
# © (or copyright) 2019. Triad National Security, LLC. All rights reserved.
# This program was produced under U.S. Government contract 89233218CNA000001 for Los Alamos
# National Laboratory (LANL), which is operated by Triad National Security, LLC for the U.S.
# Department of Energy/National Nuclear Security Administration. All rights in the program are
# reserved by Triad National Security, LLC, and the U.S. Department of Energy/National Nuclear
# Security Administration. The Government is granted for itself and others acting on its behalf a
# nonexclusive, paid-up, irrevocable worldwide license in this material to reproduce, prepare
# derivative works, distribute copies to the public, perform publicly and display publicly, and to permit
# others to do so.
##


#####################
## Service: HSNmon
## Script: switch_status.pl
## Usage: Pulls power/fan status from externally managed switches on OPA fabric
## Called From: hsnmon.pl
#####################

use strict;
use warnings;

require "/usr/local/hsnmon/hsnmon_init.pm";

&set_environment(0);

our %cfg;
our $switch;
our $fan;
our $ps1;
our $ps2;
our $output;

while (<STDIN>) {
   $_ =~ s/\n//g;

   #Pull switch name
   if (/retrieve switch .*,([^\ ]+)/) {
       $switch = $1;

   # Pull fan/PS1/PS2 status info
   } elsif (/Fan status:([^\ ]+)\s+PS1 Status:(.*)  PS2 Status:(.*) Temperature/) {
       $fan = $1;
       $ps1 = $2;
       $ps2 = $3;

       #Print status for current switch if not optimal
       #Fan_Status=Normal/Normal/Normal/Normal/Normal/Normal PS1_Status="ONLINE " PS2_status="NOT PRESENT"
       if ( $fan !~ /Normal\/Normal\/Normal\/Normal\/Normal\/Normal/ || ($ps1 !~ /ONLINE/ && $ps1 !~ /NOT PRESENT/) || ($ps2 !~ /ONLINE/ && $ps2 !~ /NOT PRESENT/) ) {
          $output="Switch_Status=$switch Fan_Status=$fan PS1_Status=\"$ps1\" PS2_status=\"$ps2\"\n";
          &error_write($cfg{ERROR_LOG},"hsnmon","info","$output");
       }
   }
}
