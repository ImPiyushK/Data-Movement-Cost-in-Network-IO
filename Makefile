# MT25076 - Makefile for Network I/O Assignment
# Roll Number: MT25076

CC = gcc
CFLAGS = -Wall -Wextra -O2 -pthread
LDFLAGS = -pthread

# Targets
TARGETS = MT25076_Part_A1_Server MT25076_Part_A1_Client \
          MT25076_Part_A2_Server MT25076_Part_A2_Client \
          MT25076_Part_A3_Server MT25076_Part_A3_Client

all: $(TARGETS)

# Two-copy implementation
MT25076_Part_A1_Server: MT25076_Part_A1_Server.c MT25076_Part_A_common.h
	$(CC) $(CFLAGS) -o $@ MT25076_Part_A1_Server.c $(LDFLAGS)

MT25076_Part_A1_Client: MT25076_Part_A1_Client.c MT25076_Part_A_common.h
	$(CC) $(CFLAGS) -o $@ MT25076_Part_A1_Client.c $(LDFLAGS)

# One-copy implementation
MT25076_Part_A2_Server: MT25076_Part_A2_Server.c MT25076_Part_A_common.h
	$(CC) $(CFLAGS) -o $@ MT25076_Part_A2_Server.c $(LDFLAGS)

MT25076_Part_A2_Client: MT25076_Part_A2_Client.c MT25076_Part_A_common.h
	$(CC) $(CFLAGS) -o $@ MT25076_Part_A2_Client.c $(LDFLAGS)

# Zero-copy implementation
MT25076_Part_A3_Server: MT25076_Part_A3_Server.c MT25076_Part_A_common.h
	$(CC) $(CFLAGS) -o $@ MT25076_Part_A3_Server.c $(LDFLAGS)

MT25076_Part_A3_Client: MT25076_Part_A3_Client.c MT25076_Part_A_common.h
	$(CC) $(CFLAGS) -o $@ MT25076_Part_A3_Client.c $(LDFLAGS)

clean:
	rm -f $(TARGETS)
	rm -f *.o

.PHONY: all clean
