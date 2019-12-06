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


# For reference compiling with support for the opamgt api, see:
# https://www.intel.com/content/dam/support/us/en/documents/network-and-i-o/fabric-products/Intel_OPA_MGT_API_PG_J68876_v4_0.pdf
CC=gcc
CFLAGS=-DIB_STACK_OPENIB -I/usr/include/opamgt -g\
	-pedantic -Wall -std=c99 -fstrict-aliasing\
	-Wstrict-aliasing -Wextra -Wstrict-prototypes\
	 -Wmissing-prototypes -Wshadow

LIBS=-lopamgt

SOURCES := $(shell ls *.c)

APPS := $(SOURCES:%.c=%)

.PHONY: all
all: $(APPS)

% : %.c
	$(CC) $(CFLAGS) $^ -o $@ $(LIBS)

.PHONY: clean
clean:
	rm -rf $(APPS)
