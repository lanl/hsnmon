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
## Script: hsnmon_init.pm
## Usage: Loads configuration values into HSNmon scripts (loads default values if not custum)
## Called From: hsnmon scripts
#####################

unshift (@INC, "/usr/bin");
use strict;
use warnings;

# Using Syslog  module
use Sys::Syslog;

our %cfg;
our $ENV;

##
# Function: set_environment
# Arguments: 1(output config to syslog) OR 0 no output
# Desc: Load config if config file exists
##
sub set_environment {

   my $out_config = $_[0];
 
   $ENV{HOME} = "/root";
   $ENV{USER} = "root";

   unless (open(CFG,"</etc/sysconfig/hsnmon.conf")) {
      &config_error_write("info","hsnmon: Error opening /etc/sysconfig/hsnmon.conf for READ: $!","EXIT");
   }

   &read_config($out_config);
}

#=========================================  

##
# Function: read_config
# Arguments: 1(output config to syslog) OR 0 no output
# Desc: Loads config file, else default.
##
sub read_config {

   my $out_config = $_[0];

   $cfg{DEBUG} = 0;
   $cfg{FABRICNAME} = "fabric";
   $cfg{DATA_STORE_TIME} = 7;
   $cfg{LOG_DIR} = "/var/log/hsnmon";
   $cfg{LOCAL_DIR} = "/usr/local/hsnmon";
   $cfg{SWEEP_TIME} = 1800;
   $cfg{ENABLE_ERRORS} = 1;
   $cfg{INCLUDE_ERROR} = "LinkWidthDnGradeTxActive;LinkWidthDnGradeRxActive;CongDiscards;LinkQualityIndicator;LocalLinkIntegrityErrors;RcvErrors;ExcessiveBufferOverruns;LinkDowned;UncorrectableErrors;FMConfigErrors;XmitConstraintErrors;RcvConstraintErrors;RcvSwitchRelayErrors";
   $cfg{ENABLE_LINK_REPORT} = 1;
   $cfg{MAX_ERRORS} = 20;
   $cfg{ERROR_LOG} = "syslog";
   $cfg{ENABLE_PERFORMANCE} = 1;
   $cfg{PERFORMANCE_LOG} = "syslog";
   $cfg{INCLUDE_PERFORMANCE} = "XmitDataMB;RcvDataMB;XmitWait";
   $cfg{FF_MAX_PARALLEL} = 20;
   $cfg{ENABLE_PERFSCOPE} = 0;
   $cfg{DATA_POLL_RATE} = 1; # in seconds
   $cfg{AMQP_FILE} = "/etc/sysconfig/hsnmon_rmq.yml";

   while (<CFG>) {
      if (!(/^#/ || !(/\w/))) {
         chomp;
         (my $k,my $v) = split(/ /,$_,2);
         $cfg{$k} = $v;
         if ($cfg{DEBUG} && $out_config == 1) { &config_error_write("info","Configuration: $k = $v","none"); }
      }
   }
}
#=========================================  

##
# Function: error_write
# Arguments: error_out location (syslog or file), syslog program name, syslog type, message
# Desc: Writes output to syslog or filename
##
sub error_write {
   my $location = $_[0];
   my $program = $_[1];
   my $type = $_[2];
   my $msg_out = $_[3];
   my $output;

   if ($cfg{DEBUG}) {
      print "$msg_out\n";
   } else {
      if ($location eq "syslog") {
         openlog("$program", 'cons,pid', 'user');
         syslog("$type", "$msg_out");
         closelog();
      }
      else {
         unless (open(my $output,'>>',$location)) {
            &error_write("syslog","hsnmon","info","Cannot open $location for Write: $!")
         }

         print $output $msg_out;
         close $output;
      }
   }
}

##
# Function: config_error_write
# Arguments: syslog type, syslog message, additional notice
# Desc: Writes config information to syslog for user during DEBUG mode
##
sub config_error_write {
   my($type) = $_[0];
   my($msg) = $_[1];
   my($more) = $_[2];

   my $title = "hsnmon";

   if ($more eq "EXIT") { $msg .= " Exiting!"; }

   openlog("$title", 'cons,pid', 'user');
   syslog("$type", "$msg");
   closelog();

   if ($more eq "EXIT") {
      exit;
   }
}

##
# Function: clear_counters
# Desc: Dumps and clears counters
##
sub hsn_counters{

   # delete old counter file
   unlink "$cfg{LOG_DIR}/opa_counters.log";

   # save the counter values
   my $pipe_status = `/usr/sbin/opaextractperf >$cfg{LOG_DIR}/opa_counters.log 2>/dev/null; echo \${PIPESTATUS[0]}`;

   # send error message if it fails
   chomp $pipe_status;
   if ( $pipe_status ) {
      &error_write( $cfg{ERROR_LOG},"hsnmon","info","opaextractperf failing, investigate output" ); 
   }

   # clear the counters
   system("/usr/sbin/opareport -C &> /dev/null");
}

##
# Function: validate_procs
# Desc: Verify that the correct processes are running
##
sub validate_procs{

   # ptree finds all subprocesses of the PID passed to it
   # this allows us to audit the number of processes
   my $sub_procs = `$cfg{LOCAL_DIR}/ptree.sh $$`;
   my $hsnmon = "hsnmon.pl";
   my $get_port = "get_port";
   my $send_to_rmq = "send_to_rmq.py";


   # Get the number of hsnmon.pl processes
   my $num_hsnmon = () = $sub_procs =~ /$hsnmon/g;
   my $num_get_count = () = $sub_procs =~ /$get_port/g;
   my $num_send_to = () = $send_to_rmq =~ /$send_to_rmq/g;

   # Check that hsnmon.pl forked and has get_counters as a sub-process
   if ( $cfg{ENABLE_PERFSCOPE} && ( $num_get_count != 2 || $num_hsnmon != 1 || $num_send_to !=1 )){
      &error_write( $cfg{ERROR_LOG},"hsnmon","info","Hsnmon in a weird state [$num_get_count:$num_hsnmon]: the process tree looks like: $sub_procs" ); 
      return 1;

   # Check that hsnmon.pl forked and has get_counters as a sub-process
   } elsif ( !$cfg{ENABLE_PERFSCOPE} && ($num_get_count != 0 || $num_hsnmon != 1 )){
      &error_write( $cfg{ERROR_LOG},"hsnmon","info","Hsnmon in a weird state [$num_get_count:$num_hsnmon]: the process tree looks like: $sub_procs" ); 
      return 1;
   } 
   if ( $cfg{DEBUG} ) { &error_write( $cfg{ERROR_LOG},"hsnmon","info","hsnmon in a happy state" ); }
   

   return 0;
}

1;
