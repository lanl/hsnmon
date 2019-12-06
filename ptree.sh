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


##
# Service: hsnmon 
# Script: ptree.sh
# Usage: given a PID, this recursively walks the process tree
# processes and prints child processes to stdout
## 

ptree(){

    if [ -z "$1" ]; then
	echo "no pid given"
        return 0
    fi
    PID=$1
    CMD="pgrep -P $PID -a"
    OUTPUT=$($CMD)

    # base case
    if [ -z "$OUTPUT" ]; then
        return 0
    fi

    # iterate over each child
    while IFS= read -r LINE;do
        echo "$LINE"

        # Recursively call ptree on each child
        PID_RECUR=$(echo "$LINE" | awk '{print $1}')
        ptree "$PID_RECUR"
    done < <(printf '%s\n' "$OUTPUT")
}

ptree $1
