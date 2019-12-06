© (or copyright) 2019. Triad National Security, LLC. All rights reserved.
This program was produced under U.S. Government contract 89233218CNA000001 for Los Alamos
National Laboratory (LANL), which is operated by Triad National Security, LLC for the U.S.
Department of Energy/National Nuclear Security Administration. All rights in the program are
reserved by Triad National Security, LLC, and the U.S. Department of Energy/National Nuclear
Security Administration. The Government is granted for itself and others acting on its behalf a
nonexclusive, paid-up, irrevocable worldwide license in this material to reproduce, prepare
derivative works, distribute copies to the public, perform publicly and display publicly, and to permit
others to do so.


### Files

create_netmap.pl		Creates link map showing connections on the fabric
get_port_counters		Polls the PA/SA and prints out data counters when a new image arrives
hsn_links.pl			Determines if any OPA links are not performing as expected
hsnmon				Init script for running hsnmon
hsnmon_cleaner.pl		Log cleaner for hsnmon (clears log directory)
hsnmon_log			Logrotate.d file for rotating /var/log/hsnmon/hsnnet_perf (if sending perf logs to file)
hsnmon.conf			Config file for hsnmon
hsnmon_rmq.yml			Config file for sending AMQP (for send_to_rmq.py)
hsnmon_init.pm			Initialization script for hsnmon to load config file
hsnmon.pl			Main daemon for hsnmon (calls other scripts)
hsnmon.service			Systemd unit file for hsnmon
hsn_rosetta.pl			Parses OPA counters and records errors
send_to_rmq.py			Reads from stdin and sends line by line to RabbitMQ.  Optionally sends entire file.
send_if_diff.sh			Sends the output of a command via AMQP if the command produces different output from previous time
switch_status.pl		Queries the externally managed switches for hardware information
opamon.conf			Example opamon.conf to use for hsnmon (required to pull counters)
hsnmon.1.gz:                    Man page file
License				License file for hsnmon outside of LANL
README				This README file

### Requirements:
1) Linux (RHEL 6/7 equivalent) environment running OPA fabric manager as master for fabric (can run on additioanl linux systems as standby for failover)
2) Required RPMs: opa-fastfabric
3) Optional RPMs: python2-pika, opa-libopamgt (required for high frequency performance monitoring)
3) opamon.conf (Intel's opamon config file) to enable counters in FM (and to clear errors).

### How to run hsnmon
1) Install RPM hsnmon-X.rpm
2) Configure config file at /etc/sysconfig/hsnmon.conf (sample file at /usr/local/hsnmon/hsnmon.conf.sample)
3) Run: "/usr/libexec/hsnmon start" to start hsnmon

```
Usage: /usr/libexec/hsnmon {start|stop|status|dst-start|dst-stop|pause|clear-counters|help}
Parameters:
start            - Start or resume hsnmon (DST mode, if enabled, will resume)

stop             - Stop hsnmon (DST mode, if enabled, will remain enabled)

status           - Report current status of hsnmon

dst-start        - Enables DST Mode
                 - Disables error logging ONLY (if enabled)
                 - Performance/fabric monitoring will continue (if enabled)
                 - DST mode can be enabled with or without hsnmon running

dst-stop         - Disables DST Mode
                 - Resumes error logging if enabled
                 - Clears counters
                 - DST mode can be disabled with or without hsnmon running

pause            - Disables/halts hsnmon from executing, upon resume (start), will clear counters

clear-counters   - Clears all counters

help, -h, --help - Displays this usage information
```


### DST: Dedicated Service Time

DST mode can be used when the high speed fabric is reserved for administrative work or maintenance.  
(i.e. hardware being replaced, fabric being tested, nodes being added/removed in large 
groups that will alert, etc.).  This mode will prevent the fabric errors from reporting due 
to what ever work is going on during this DST.  The daemon though will continue to run to 
collect counters during this time. Note that sleep cycle for hsnmon will continue as
normal but when service wakes up to check errors, if DST mode enabled, will ignore the
error checking.


### OPA Link Analysis
For determining issues with links on the fabric, hsnmon makes use of the following OPA command:
```
/usr/sbin/opalinkanalysis -T /path/to/topology.xml verifylinks 
```

This gives an output of any link issues on the OPA fabric including missing links, unexpected links, misconfigured links, etc.
hsnmon will report the following message if there are any issues found using the above command:
```
hsnmon[]: Link Report: 0 Missing, 1 Unexpected, 1 Misconnected, 0 Duplicate, 1 Different
```
hsnmon will then report details about the above output (which cables are missing, etc.)


### opamon.conf


This config file is part of Intel's FM monitoring suite (not part of hsnmon!). This file is, however, required for hsnmon to query the counters
from the fabric manager on the system.   An example file to use with hsnmon is located at:
```
/usr/local/hsnmon/opamon.conf.example
```

To use this file in production, move it to:
```
/etc/sysconfig/opa/
```


### hsnmon.conf

This config file is the primary config file for hsnmon.  It is used for configuring hsnmon's log and file paths, debug mode, log rotation, sweep interval, et cetera.
Most of hsnmon's configurable knobs are located here.

### hsnmon_rmq.yml

This config file is used with the high frequency performance monitoring module in hsnmon.  This enables AMQP traffic, and it supports 
certificate based authentication, as well as username/password.  This is used solely by send_to_rmq.py which provides a general
purpose interface for sending AMQP traffic either from STDIN or a file. This module will not work without a working AMQP message broker, such as RabbitMQ.

Example:
```
echo "test123" | ./send_to_rmq.py --config ./myconf.yml
```

This High Speed Network (HSN) monitoring service for OPA fabrics was developed at the Los Alamos National Laboratory 
High Performance Computing Division (LANL HPC) and is locally grown and maintained. 
