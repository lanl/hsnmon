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
## Service: HSNMon
## Script: hsn_rosetta.pl
## Usage: Parses error and performance counters to report
## Called From: hsnmon.pl
#####################

use strict;
use warnings;

require "/usr/local/hsnmon/hsnmon_init.pm";

use Sys::Syslog;
use Time::Local;

#           "NodeDesc", "",
#           "SystemImageGUID", "",
#           "PortNum", "",
#           "LinkSpeedActive", "",
#           "LinkWidthDnGradeTxActive", "",
#           "LinkWidthDnGradeRxActive", "",
#           "XmitDataMB", "",
#           "XmitData", "",
#           "XmitPkts", "",
#           "MulticastXmitPkts", "",
#           "RcvDataMB", "",
#           "RcvData", "",
#           "RcvPkts", "",
#           "MulticastRcvPkts", "",
#           "XmitWait", "",
#           "CongDiscards", "",
#           "XmitTimeCong", "",
#           "MarkFECN", "",
#           "RcvFECN", "",
#           "RcvBECN", "",
#           "RcvBubble", "",
#           "XmitWastedBW", "",
#           "XmitWaitData", "",
#           "LinkQualityIndicator", "",
#           "LocalLinkIntegrityErrors", "",
#           "RcvErrors", "",
#           "ExcessiveBufferOverruns", "",
#           "LinkErrorRecovery", "",
#           "LinkDowned", "",
#           "UncorrectableErrors", "",
#           "FMConfigErrors", "",
#           "XmitConstraintErrors", "",
#           "RcvConstraintErrors", "",
#           "RcvSwitchRelayErrors", "",
#           "XmitDiscards", "",
#           "RcvRemotePhysicalErrors", ""

&set_environment(0);

our %cfg;
our $hsnmap = "$cfg{LOG_DIR}/hsnnet_map";
our $host = `/bin/uname -n | /bin/sed -r 's/\\..*//g'`;
our $latest = "$cfg{LOG_DIR}/errorlist-latest";
our $perfout = "$cfg{LOG_DIR}/hsnnet_perf";
our $dst_file = "/etc/hsnmon_dst";

# Define array of errors pulled from "opaextractperf"
our @errors=();

our $num_error=0;
our $sdev="";
our $sguid="";
our $sport="";
our $ddev_port="";
our $msg="";
our $xmit="";
our $rcv="";
our $wait="";

chomp($host);

while (<STDIN>) {
   $_ =~ s/\n//g;

   # Pull in counter names from opaextractperf
   if (/NodeDesc/) {
      @errors = split /;/, $_;
 
   # Pull in counters
   } else { 
      my $i=0;
      my @error_counters = split /;/, $_;

      while ($i<=$#error_counters) {
 
	 #Device name
         if ($errors[$i] =~ /NodeDesc/) {
            $sdev=$error_counters[$i];
            $msg="$sdev ";

         #Source GUID
         } elsif ($errors[$i] =~ /SystemImageGUID/) {
            $sguid=$error_counters[$i];
         
         #Source Port Number
         } elsif ($errors[$i] =~ /PortNum/) {
            $sport=$error_counters[$i];
            $msg .= "Port $sport:";

         # LinkWidthDnGradeTxActive (Don't report if 4)
         } elsif (($errors[$i] =~ /LinkWidthDnGradeTxActive/) && ($cfg{INCLUDE_ERROR} =~ /$errors[$i]/)){
            if ($error_counters[$i] ne "4") {
               $msg .= " [$errors[$i] == $error_counters[$i]]";
            }

         # LinkWidthDnGradeRxActive (Don't report if 4)
         } elsif (($errors[$i] =~ /LinkWidthDnGradeRxActive/) && ($cfg{INCLUDE_ERROR} =~ /$errors[$i]/)){
            if ($error_counters[$i] ne "4") {
               $msg .= " [$errors[$i] == $error_counters[$i]]";
            }

         # XmitDataMB
         } elsif (($errors[$i] =~ /XmitDataMB/) && ($cfg{INCLUDE_PERFORMANCE} =~ /$errors[$i]/)) {
            $xmit=$error_counters[$i];

         # RcvDataMB
         } elsif (($errors[$i] =~ /RcvDataMB/) && ($cfg{INCLUDE_PERFORMANCE} =~ /$errors[$i]/)){
            $rcv=$error_counters[$i];

         # XmitWait
         } elsif (($errors[$i] =~ /XmitWait/) && ($cfg{INCLUDE_PERFORMANCE} =~ /$errors[$i]/)){
            $wait=$error_counters[$i];

         # LinkQualityIndicator (Don't report if 5)
         } elsif (($errors[$i] =~ /LinkQualityIndicator/) && ($cfg{INCLUDE_ERROR} =~ /$errors[$i]/)){
            if ($error_counters[$i] ne "5") {
               $msg .= " [$errors[$i] == $error_counters[$i]]";
            }

         # If error provided in config file, add to error line
         } else {
            if (($error_counters[$i] ne "0") && ($cfg{INCLUDE_ERROR} =~ /$errors[$i]/)) {
               $msg .= " [$errors[$i] == $error_counters[$i]]";
            }
         }
         $i++;
      }
      if (($msg =~ /.*\[.* == .*\].*/) && ($cfg{ENABLE_ERRORS} == 1) && ($sport ne "0")) {

         my $ddev_port = &get_remote($sdev,$sport);
         if ($ddev_port) {
            $msg .= " - ($ddev_port)";
         } else {
            $ddev_port = "remote device not found";
            $msg .= " - ($ddev_port)";
         }
         
         unless ( -e $dst_file ) {
               &error_write($cfg{ERROR_LOG},"hsnmon","info","$msg");
               $num_error++;
         }
      }
      if ($cfg{ENABLE_PERFORMANCE} == 1) {
         &performance_write($sdev,$sport,$wait,$xmit,$rcv);
      }
   }
}

unless ( -e $dst_file ) {
   if ($cfg{ENABLE_ERRORS} == 1) {

      if ($num_error == 0) {
         &error_write($cfg{ERROR_LOG},"hsnmon","info","No OPA Errors this run");
      } elsif ($num_error > $cfg{MAX_ERRORS}) {
         &errors_alert();
      }
   }
}

exit;

###########################################################

##
# Function: errors_alert
# Arguments: none
# Desc: Send Syslog/Zenoss event warning of many devices reporting errors,set by limit in config
##
sub errors_alert {
   my $errorMsg = "hsnmon has reported many devices with errors";
   if ($cfg{DEBUG}) { 
      print "$errorMsg\n";   
   } else {
      &error_write($cfg{ERROR_LOG},"hsnmon","info","$errorMsg");
   }
}

##
# Function: performance_write
# Arguments: d=device, p=port, w=wait_counters, x=xmit_counters, r=receive_counters
# Desc: Format performance counters into message to store for each device on the fabric
##
sub performance_write {
   my($d) = $_[0];
   my($p) = $_[1];
   my($w) = $_[2];
   my($x) = $_[3];
   my($r) = $_[4];
   my($perf) = "";
   my($date) = `/bin/date`;
   chomp($date);

   $perf = "fabric=$cfg{FABRICNAME} device=\"$d\" port=$p";
   if ($cfg{INCLUDE_PERFORMANCE} =~ /XmitDataMB/) {
      $perf .= " XmitDataMB=$x";
   }
   if ($cfg{INCLUDE_PERFORMANCE} =~ /RcvDataMB/) {
      $perf .= " RcvDataMB=$r";
   }
   if ($cfg{INCLUDE_PERFORMANCE} =~ /XmitWait/) {
      $perf .= " XmitWait=$w";
   }

   if ($cfg{DEBUG}) {
      print "$perf\n";
   } else {
      if ($cfg{PERFORMANCE_LOG} eq "syslog") {
         openlog("hsnnet_perf", 'cons,pid', 'user');
         syslog("info", "$perf");
         closelog();
      } else {
         my $output;
         unless (open($output,'>>',$cfg{PERFORMANCE_LOG})) {
            &error_write("syslog","hsnmon","info","Cannot open $cfg{PERFORMANCE_LOG} for Write: $!")
         }

         print $output "$date $perf\n";
         close $output;
      }
   }
}

##
# Function: get_remote
# Arguments: d=device, p=port
# Desc: Looks for remote device on given source device/port in hsnnet_map, returns none if none found (missing)
##
sub get_remote {
   my($d) = $_[0];
   my($p) = $_[1];
   my($remote) = "";
   my($rd) = "";
   my($rp) = "";

   #100g  0x001175010163186c   FI    1     <-> 0x001175010262ecce   SW    35    ("kit008 hfi1_0            " - "core1                    ")

   # Look for source device in hsnnet_map with port given
   $rd = `/bin/grep -E "^[0-9a-z]+\\s+0x[a-z0-9]+\\s+[A-Z]{2}\\s+$p\\s+.*\\(\\"$d\\s+.*" $hsnmap | /bin/awk -F\\" '{print \$4}'`;
   $rp = `/bin/grep -E "^[0-9a-z]+\\s+0x[a-z0-9]+\\s+[A-Z]{2}\\s+$p\\s+.*\\(\\"$d\\s+.*" $hsnmap | /bin/awk -F' ' '{print \$8}'`; 
   
   chomp($rd);
   chomp($rp);
   $rd =~ s/\s+/ /g; 
   
   if($rd ne "") {
      $remote = "$rd Port $rp";
      $remote =~ s/\s+/ /g;
   } 
   return ($remote);
}
