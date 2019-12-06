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
## Script: hsnmon.pl
## Usage: Calls hsnmon processes to look for errors/performance counters on fabric
##        Runs as daemon
## Called From: hsnmon init
#####################

use strict;
use warnings;
require "/usr/local/hsnmon/hsnmon_init.pm";

use Sys::Syslog;
use Time::Local;


&set_environment(1);

# Save and dump counters
if ( @ARGV && $ARGV[0] eq "hsn_counters" ) {
   &hsn_counters();
   exit;
}

# Save and dump counters
if ( @ARGV && $ARGV[0] eq "validate_procs" ) {
   &validate_procs();
   exit;
}


# Start hsnmon as daemon
&daemonize();

our %cfg;
our $dst_file="/etc/hsnmon_dst";
our $pause_file="/etc/hsnmon_pause";
our $dst=0;
our $start_msg;
our $date;
our $swdiff;
our $addedSW;
our $removedSW;
our $filename;
our $file_content;
our $chassisping;
our $switchping;
our $linkerrors;
our $linkreport;
our @cable_list;
our $cable;
my $perf_init = 0;

$ENV{FF_MAX_PARALLEL} = $cfg{FF_MAX_PARALLEL};

# Loop until hsnmon process killed
while (1) {

   # Check if hsnmon paused, pause 1 second before checking again
   if ( -e $pause_file ) {
      sleep (1);

   } else {

      # Gather fabric status output - following two lines replace former script (fabric_status.sh)
      system("/usr/sbin/opareport > $cfg{LOG_DIR}/opafabricreport 2>/dev/null");
      system("/usr/sbin/opainfo > $cfg{LOG_DIR}/opamasterinfo 2>/dev/null");

      #Determine if system is master SM, continue if it is
      my $master=`/usr/bin/cat $cfg{LOG_DIR}/opafabricreport | /usr/bin/grep Master | /usr/bin/awk '{print \$2}' | /usr/bin/sed -r s/0x//g`;
      my $server=`/usr/bin/cat $cfg{LOG_DIR}/opamasterinfo | /usr/bin/grep PortGID | /usr/bin/awk -F':' '{print \$4}'`;
      if ( $server eq $master ) {

         # Send message that hsnmon loop is starting with/without DST mode
         if ( -e $dst_file ) {
            $start_msg = "Starting HSNmon Loop...DST Mode Enabled";
         } else {
            $start_msg = "Starting HSNmon Loop...";
         }
         &error_write($cfg{ERROR_LOG},"hsnmon","info",$start_msg);
         $date=`/bin/date +%Y%m%d%H%M`;

         # Generate map of fabric
         system("/usr/sbin/opareport -o links | $cfg{LOCAL_DIR}/create_netmap.pl | /usr/bin/awk 'NR == 1; NR > 1 {print \$0 | \"sort -k9 -k4 -n\"}' &> $cfg{LOG_DIR}/hsnnet_map");
	 system("/bin/cp $cfg{LOG_DIR}/hsnnet_map $cfg{LOG_DIR}/hsnnet_map.$date >& /dev/null");

         # Delete *net_* files older than DATA_STORE_TIME days
         system("$cfg{LOCAL_DIR}/hsnmon_cleaner.pl >& /dev/null");

         # Generate Host list
         system("/usr/sbin/opareport -o lids | /bin/grep FI | /bin/sort -k 5 > $cfg{LOG_DIR}/host_list");

         if ( $cfg{DEBUG} ) { &error_write($cfg{ERROR_LOG},"hsnmon","info","Looking for switch changes..."); }

         # Generate switch list, report if any changes
         system("/bin/cp -f $cfg{LOG_DIR}/switch_list $cfg{LOG_DIR}/switch_list.prev >& /dev/null");
         system("/usr/sbin/opareport -o lids | /bin/grep SW | /bin/sort -k 5 > $cfg{LOG_DIR}/switch_list");
         $swdiff=`/usr/bin/diff $cfg{LOG_DIR}/switch_list.prev $cfg{LOG_DIR}/switch_list | /usr/bin/wc -l`;
         if ( $swdiff != 0 ) {
            $addedSW=`/usr/bin/diff $cfg{LOG_DIR}/switch_list.prev $cfg{LOG_DIR}/switch_list | /bin/grep SW | /bin/grep ">"  | /usr/bin/awk -F'SW' '{print \$2 " (Added)"}' | /usr/bin/tr '\n' ', '`;
            $removedSW=`/usr/bin/diff $cfg{LOG_DIR}/switch_list.prev $cfg{LOG_DIR}/switch_list | /bin/grep SW | /bin/grep "<"  | /usr/bin/awk -F'SW' '{print \$2 " (Removed)"}' | /usr/bin/tr '\n' ', '`;
            &error_write($cfg{ERROR_LOG},"hsnmon","info","Switch count differs, please check switch(es) ( $addedSW $removedSW ) for issues");
         } else {
            &error_write($cfg{ERROR_LOG},"hsnmon","info","No Switch Differences this run");
         }

         # Send the linear forwarding table to RMQ
         if( $cfg{ENABLE_PERFSCOPE} ) {
            system("$cfg{LOCAL_DIR}/send_if_diff.sh \"/usr/sbin/opareport -o linear\" \"linear\" $cfg{LOG_DIR} $cfg{LOCAL_DIR} $cfg{AMQP_FILE}");
         }

         # Check ping status of switches and chassis
         $chassisping=`/usr/sbin/opapingall -C -p -F $cfg{CHASSIS_FILE} | /bin/grep -v "is alive" | /usr/bin/awk -F':' '{print \$1}' | /usr/bin/tr '\n' ', '`;
         $switchping=`/usr/sbin/opaswitchadmin -L $cfg{SWITCHES_FILE} ping | /bin/grep FAILED | /bin/grep switchping | /usr/bin/awk -F' ' '{print \$10}' | /usr/bin/awk -F',' '{print \$2}' | /usr/bin/tr '\n' ', '`;
         if ( $chassisping || $switchping ) {
            &error_write($cfg{ERROR_LOG},"hsnmon","info","Switches not pinging, please check switch(es) ( $chassisping $switchping ) for issues");
         }

         # Check switch status (call switch_status to report any bad switch hardware) and clear opafastfabric temp logs
         system("/usr/sbin/opaswitchadmin -c -L $cfg{SWITCHES_FILE} info | $cfg{LOCAL_DIR}/switch_status.pl");

         if ( $cfg{DEBUG} ) { &error_write($cfg{ERROR_LOG},"hsnmon","info","Looking for HSN Errors..."); }

         if ( $cfg{DEBUG} ) { &error_write($cfg{ERROR_LOG},"hsnmon","info","Pulling and clearing counters..."); }

         #Pull Counters from OPA and clear them
         &hsn_counters();

         # Determine if opaextractperf output the same, exit if different
	 system("/usr/bin/cat $cfg{LOG_DIR}/opa_counters.log | /usr/bin/head -1 > $cfg{LOG_DIR}/opaextractperf-format");
         if ( `/usr/bin/diff $cfg{LOG_DIR}/opaextractperf-format $cfg{LOG_DIR}/opaextractperf-expected | /usr/bin/wc -l` != 0) {
            &error_write($cfg{ERROR_LOG},"hsnmon","info","Format of opaextractperf has changed, please contact hpc3-network\@lanl.gov");
            system("/usr/libexec/hsnmon stop");
            exit;
         }

         # Find errors if enabled, Gather Performance Counters if enabled
         if ( $cfg{ENABLE_ERRORS} == 1 ) {

            #Check to see if port counters were pulled from fabric manager, error if not
            $filename="$cfg{LOG_DIR}/opa_counters.log";
            $file_content=`/bin/cat $filename | /usr/bin/wc -l`;

            if (-e $filename && $file_content != 0) {
               system("/bin/cat $filename | $cfg{LOCAL_DIR}/hsn_rosetta.pl >& /dev/null");
            } else {
               &error_write("syslog","hsnmon","info","OPA Counters not found at $cfg{LOG_DIR}/opa_counters.log - Check opaextractperf output");
            }
         }

         if( $cfg{ENABLE_PERFSCOPE} && !$perf_init ){
            $perf_init = 1;

            #parent
            my $pid;
            if( $pid = fork ) {
               &error_write($cfg{ERROR_LOG},"hsnmon","info", "Successfully forked to create hsnperf process");

            # child
            } elsif (defined $pid) {
               if ( $cfg{DEBUG} ) {
                  &error_write($cfg{ERROR_LOG},"hsnmon","info","Pulling and clearing counters in separate process (PID=$pid)...");
               }

               my $sleep_t = 1;
               my $amqp_err = 0;
               my $last_t = time();
               my $cur_t = $last_t;
               my $output = '';
               my $cmd = "$cfg{LOCAL_DIR}/get_port_counters $cfg{DATA_POLL_RATE} 2>/dev/null | $cfg{LOCAL_DIR}/send_to_rmq.py --config $cfg{AMQP_FILE}";

               # this section is used for error handling for both polling the fabric for performance counters and for sending the data to RabbitMQ
               # get_port_counters is a long-running command, and in theory should be able to run indefinitely - the same is true of send_to_rmq.py
               # however, a number of conditions might cause this to fail a single time, a few times in a row, or indefinitely
               # no need to explain each situation in detail, just know that the following loop is designed to handle each of those three situations
               # somewhat intelligently - it will try to run the command if it can and if it fails repeatedly in a short period of time, then it will 
               # throttle back the attempt frequency and send error messages to syslog
               while (1) {

                  # skip perfscope stuff if no config file (either running on a service node or file got removed somehow)
                  if ( ! -f $cfg{AMQP_FILE} ){
                     &error_write($cfg{ERROR_LOG},"hsnmon","info","Config file for send_to_rmq.py is missing! Investigate!  [$cfg{AMQP_FILE}]");
                     sleep(3600);
                  } elsif ( $output ) {
                     $cur_t = time();
                     &error_write($cfg{ERROR_LOG},"hsnmon","info","Error with cmd [$cmd] - $output\n");
                     $output = "";

                     # less than 2s is too frequent to fail - not good
                     if ($cur_t - $last_t < 2) {
                        $amqp_err += 1;
                        $sleep_t *= 2;
                     }
                     # greater than 60s between failures means that the problem has probably fixed itself, reset counters
                     if ($cur_t - $last_t > 60) {
                        $amqp_err = 0;
                        $sleep_t = 1;
                     }
                     # has failed a few times in a row.... better give it a rest and come back later
                     if ($amqp_err > 4){
                        &error_write($cfg{ERROR_LOG},"hsnmon","info","AMQP has failed $amqp_err times recently, sleeping for 1 hour\n"); 
                        $sleep_t = 3600;
                     }
                     $last_t = $cur_t;
                     sleep($sleep_t);

                  } else {

                     # get stderr of send_to_rmq.py
                     $output = `$cmd`;
                     sleep(10);
                  }
                  &error_write($cfg{ERROR_LOG},"hsnmon","info","get_port_counters | send_to_rmq.py process died early... restarting");
                  &error_write($cfg{ERROR_LOG},"hsnmon","info","Error with cmd dying early: [$cmd] - out:$output\n");
               }

            # error
            } else {
               &error_write($cfg{ERROR_LOG},"hsnmon","info","Error forking! $!");
            }
         }


         # Look for link issues on fabric if error checking is enabled
         unless ( -e $dst_file ) {
            if ( $cfg{ENABLE_LINK_REPORT} == 1 ) {
               $linkerrors=`/usr/sbin/opalinkanalysis -T $cfg{TOPOLOGY_FILE} verifylinks | /bin/grep -i Missing | /bin/grep -i Unexpected | /bin/grep -i Misconnected | /bin/grep -i Duplicate | /bin/grep -i Different`;
               $linkreport="Link Report: $linkerrors";
               &error_write($cfg{ERROR_LOG},"hsnmon","info",$linkreport);

               # Output cable details from link report
               @cable_list=`/usr/sbin/opalinkanalysis -T $cfg{TOPOLOGY_FILE} verifylinks | /usr/bin/grep -v CableLabel | /usr/bin/grep -A2 "Cable: " --no-group-separator | /usr/bin/sed -r "s/Cable/Check Cable/g" | /usr/bin/sed -r "s/,.*//g" | /usr/bin/awk '{ printf "%s", \$0; if (NR % 3 == 0) print ""; else printf " " }' | /usr/bin/sed -r "s/\\s+/ /g"`;

               foreach $cable (@cable_list) {
                  &error_write($cfg{ERROR_LOG},"hsnmon","info","$cable");
               }
            }
         }

         # validate the hsnmon process tree
         &validate_procs();

         # hsnmon run complete
         &error_write($cfg{ERROR_LOG},"hsnmon","info","HSNmon run complete, sleeping...");

      # System is not primary FM, report and sleep
      } else {
         &error_write($cfg{ERROR_LOG},"hsnmon","info","System is not master fabric manager, sleeping...");
      }

      # Sleep until next itteration
      sleep ($cfg{SWEEP_TIME});
   }
}

exit;

#Create fork for hsnmon.pl
sub daemonize {
   POSIX::setsid or die "setsid: $!";
   my $pid = fork ();
   if ($pid < 0) {
      die "fork: $!";
   } elsif ($pid) {
      exit 0;
   }
   chdir "/";
   umask 0;
   foreach (0 .. (POSIX::sysconf (&POSIX::_SC_OPEN_MAX) || 1024))
      { POSIX::close $_ }
   open (STDIN, "</dev/null");
   open (STDOUT, ">/dev/null");
   open (STDERR, ">&STDOUT");
}
