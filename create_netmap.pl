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
## Script: create_netmap.pl
## Usage: Reformats OPA links output from opareport
## Called From: hsnmon.pl
#####################

use strict;
use warnings;

our $SPEED="";
our $SGUID="";
our $SPORT="";
our $STYPE="";
our $SDEVICE="";
our $DGUID="";
our $DPORT="";
our $DTYPE="";
our $DDEVICE="";

#100g  0x001175010163186c   FI    1     <-> 0x001175010262ecce   SW    35    ("kit008 hfi1_0            " - "core1                    ")
printf("%-5s %-20s %-5s %-5s <-> %-20s %-5s %-5s \(\"%-25s\" - \"%-25s\"\)\n", "SPEED", "SGUID", "STYPE", "SPORT" ,"DGUID", "DTYPE", "DPORT", "SDEVICE", "DDEVICE"); 

while (<STDIN>) {
   $_ =~ s/\n//g;
   $_ =~ s/\s+/ /g;
   if ($_ =~ /^([0-9a-z]+) (0x.*) (\d+) ([A-Z]{2}) (.*)/) {
      $SPEED=$1;
      $SGUID=$2;
      $SPORT=$3;
      $STYPE=$4;
      $SDEVICE=$5;
      printf("%-5s %-20s %-5s %-5s", $SPEED, $SGUID, $STYPE, $SPORT);
   } elsif ($_ =~ /^<-> (0x.*) (\d+) ([A-Z]{2}) (.*)/) {
      $DGUID=$1;
      $DPORT=$2;
      $DTYPE=$3;
      $DDEVICE=$4;
      printf(" <-> %-20s %-5s %-5s \(\"%-25s\" - \"%-25s\"\)\n", $DGUID, $DTYPE, $DPORT, $SDEVICE, $DDEVICE);
      printf("%-5s %-20s %-5s %-5s <-> %-20s %-5s %-5s \(\"%-25s\" - \"%-25s\"\)\n", $SPEED, $DGUID, $DTYPE, $DPORT, $SGUID, $STYPE, $SPORT, $DDEVICE, $SDEVICE);
   }
}
exit;
