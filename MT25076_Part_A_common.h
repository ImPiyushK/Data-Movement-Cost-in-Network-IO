/* MT25076 - Common Header for Network I/O Assignment */
#ifndef MT25076_COMMON_H
#define MT25076_COMMON_H

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <errno.h>
#include <time.h>
#include <signal.h>
#include <sys/time.h>
#include <linux/errqueue.h>

/* Configuration */
#define DEFAULT_PORT 8888
#define DEFAULT_DURATION 10  /* seconds */
#define NUM_FIELDS 8
#define BACKLOG 128

/* Message structure with 8 dynamically allocated string fields */
typedef struct {
    char *fields[NUM_FIELDS];
    size_t field_sizes[NUM_FIELDS];
} Message;

/* Client configuration */
typedef struct {
    int thread_id;
    char *server_ip;
    int port;
    size_t message_size;
    int duration;
    /* Results */
    double throughput_gbps;
    double latency_us;
    unsigned long long bytes_sent;
    unsigned long long messages_sent;
} ClientConfig;

/* Server thread arguments */
typedef struct {
    int client_fd;
    int thread_id;
    size_t message_size;
} ServerThreadArgs;

/* Utility functions */
static inline double get_time_us(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec * 1e6 + tv.tv_usec;
}

static inline double get_time_sec(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec + tv.tv_usec / 1e6;
}

/* Allocate message with specified total size distributed across fields */
static inline Message* allocate_message(size_t total_size) {
    Message *msg = (Message*)malloc(sizeof(Message));
    if (!msg) return NULL;
    
    size_t per_field = total_size / NUM_FIELDS;
    size_t remainder = total_size % NUM_FIELDS;
    
    for (int i = 0; i < NUM_FIELDS; i++) {
        size_t field_size = per_field + (i < (int)remainder ? 1 : 0);
        msg->fields[i] = (char*)malloc(field_size);
        if (!msg->fields[i]) {
            for (int j = 0; j < i; j++) free(msg->fields[j]);
            free(msg);
            return NULL;
        }
        /* Fill with pattern */
        memset(msg->fields[i], 'A' + i, field_size);
        msg->field_sizes[i] = field_size;
    }
    return msg;
}

/* Free message */
static inline void free_message(Message *msg) {
    if (!msg) return;
    for (int i = 0; i < NUM_FIELDS; i++) {
        free(msg->fields[i]);
    }
    free(msg);
}

/* Serialize message into a contiguous buffer */
static inline char* serialize_message(Message *msg, size_t *out_size) {
    size_t total = 0;
    for (int i = 0; i < NUM_FIELDS; i++) {
        total += msg->field_sizes[i];
    }
    
    char *buf = (char*)malloc(total);
    if (!buf) return NULL;
    
    size_t offset = 0;
    for (int i = 0; i < NUM_FIELDS; i++) {
        memcpy(buf + offset, msg->fields[i], msg->field_sizes[i]);
        offset += msg->field_sizes[i];
    }
    
    *out_size = total;
    return buf;
}

/* Set socket options for performance */
static inline void set_socket_options(int fd) {
    int optval = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &optval, sizeof(optval));
    setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &optval, sizeof(optval));
    
    /* Increase buffer sizes */
    int bufsize = 4 * 1024 * 1024;
    setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &bufsize, sizeof(bufsize));
    setsockopt(fd, SOL_SOCKET, SO_RCVBUF, &bufsize, sizeof(bufsize));
}

/* Parse command line for message size */
static inline size_t parse_size(const char *str) {
    size_t size = 0;
    char suffix = 0;
    sscanf(str, "%zu%c", &size, &suffix);
    switch (suffix) {
        case 'K': case 'k': size *= 1024; break;
        case 'M': case 'm': size *= 1024 * 1024; break;
        case 'G': case 'g': size *= 1024 * 1024 * 1024; break;
    }
    return size > 0 ? size : 1024;  /* Default 1KB */
}

#endif /* MT25076_COMMON_H */
