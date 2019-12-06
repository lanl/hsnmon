#!/bin/bash

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


####################
# Service: HSNmon
# Script: send_if_diff.sh
# Usage: Sends a file that is the output of a command
# if there is a difference from the last run.  File is
# sent to RabbitMQ.
# Called From: hsnmon/hsnmon.pl
# example: send_if_diff.sh "/usr/sbin/opareport -o linear" linear
####################

DUMP_CMD=$1 			# some command that writes a string to stdout
FILE_ID=$2				# some unique identifier to be part of the file name, and used as a header in the file stream to RMQ
LOG_DIR=$3				# directory that files will be stored in
LOCAL_DIR=$4			# directory of local directory
CONF=$5					# AMQP CONF
LAST=opa_"$FILE_ID"_last.log		# last run is stored here for comparasin
CURRENT=opa_"$FILE_ID"_current.log	# current run is stored here for comparasin

# If no historical file exists, dump a copy and send it
if [ ! -f $LOG_DIR/$CURRENT ]; then

	# Dump linear forwarding table and save
	echo "$($DUMP_CMD)" > $LOG_DIR/$CURRENT

	# Send file via rabbitmq
	$LOCAL_DIR/send_to_rmq.py --config "$CONF" --file_header "$FILE_ID:" --send_file $LOG_DIR/$CURRENT
	exit 1
fi

# Save old linear forwarding table
mv $LOG_DIR/$CURRENT $LOG_DIR/$LAST

# Dump linear forwarding table and save
echo "$($DUMP_CMD)" > $LOG_DIR/$CURRENT

# If nothing changed, send a message saying so
if [ $(diff $LOG_DIR/$CURRENT $LOG_DIR/$LAST | wc -l) == 0 ]; then
	echo "$FILE_ID:no_change" | $LOCAL_DIR/send_to_rmq.py --config "$CONF"

# Otherwise send the file
else
	$LOCAL_DIR/send_to_rmq.py --config "$CONF" --file_header "$FILE_ID:" --send_file $LOG_DIR/$CURRENT
fi
