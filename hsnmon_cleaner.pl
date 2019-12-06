#!/usr/bin/perl

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
## Service: HSNMon
## Script: hsnmon_cleaner.pl
## Usage: Deletes data files from past X days (X given from config file)
## Called From: hsnmon.pl
#####################

use strict;
use warnings;
require "/usr/local/hsnmon/hsnmon_init.pm";

&set_environment(0);

our %cfg;
our $days;
our $elapsed;
our $now;
our $limit;
our @entry;
our $ctr;

$days = $ARGV[0];
if (!$days) {
   $days = $cfg{DATA_STORE_TIME};
}

$elapsed = $days * 24 * 60 * 60;
$now = `/bin/date +%s`;
$limit = $now - $elapsed;

# Delete files from before $days ago
if ($days != 0) {
   &cleanup("hsnnet");
}
exit;

########################################################################################

##
# Function: cleanup
# Arguments: hsnnet
# Desc: Look for any file names in the data directory containing "hsnnet" and delete it 
#      if older than DATA_STORE_TIME days
##
sub cleanup {
   my($f) = $_[0];

   #Look for any logs in the log directory starting with ibnet*
   @entry = split(/\n/,`/bin/ls -l --time-style +%s $cfg{LOG_DIR}/$f*`);

   $ctr=0;
   #Delete files older than $days ago
   while ($entry[$ctr]) {
      (my $perm,my $ref,my $owner,my $group,my $size,my $ts,my $file) = split(/\s+/,$entry[$ctr]);
    
      if ($limit > $ts) {
      `/bin/rm -f $file`;
      }
      $ctr++;
   }
}
