/* MT25076 - Part A3: Zero-Copy Client Implementation
 * Connects to zero-copy server and receives data
 */

#include "MT25076_Part_A_common.h"
#include <sys/uio.h>
#include <linux/errqueue.h>

#ifndef SO_ZEROCOPY
#define SO_ZEROCOPY 60
#endif

#ifndef MSG_ZEROCOPY
#define MSG_ZEROCOPY 0x4000000
#endif

/* Poll error queue for zerocopy completion notifications */
static int poll_zerocopy_completion(int fd) {
    char control[CMSG_SPACE(sizeof(struct sock_extended_err) + sizeof(uint32_t))];
    struct msghdr msg = {0};
    msg.msg_control = control;
    msg.msg_controllen = sizeof(control);
    
    int ret = recvmsg(fd, &msg, MSG_ERRQUEUE);
    if (ret < 0) {
        if (errno == EAGAIN || errno == EWOULDBLOCK) {
            return 0;  /* No notification yet */
        }
        return -1;
    }
    
    /* Process completion notification */
    struct cmsghdr *cmsg;
    for (cmsg = CMSG_FIRSTHDR(&msg); cmsg; cmsg = CMSG_NXTHDR(&msg, cmsg)) {
        if (cmsg->cmsg_level == SOL_IP && cmsg->cmsg_type == IP_RECVERR) {
            struct sock_extended_err *serr = (struct sock_extended_err*)CMSG_DATA(cmsg);
            if (serr->ee_errno == 0 && serr->ee_origin == SO_EE_ORIGIN_ZEROCOPY) {
                /* Success - zerocopy completion */
                return 1;
            }
        }
    }
    return 0;
}


volatile sig_atomic_t client_running = 1;

void handle_signal(int sig) {
    (void)sig;
    client_running = 0;
}

void* client_thread(void *arg) {
    ClientConfig *config = (ClientConfig*)arg;
    
    /* Create socket */
    int sock_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (sock_fd < 0) {
        perror("[Client] socket");
        return NULL;
    }
    
    set_socket_options(sock_fd);
    
    struct sockaddr_in server_addr = {0};
    server_addr.sin_family = AF_INET;
    server_addr.sin_port = htons(config->port);
    if (inet_pton(AF_INET, config->server_ip, &server_addr.sin_addr) <= 0) {
        fprintf(stderr, "[Client] Invalid address: %s\n", config->server_ip);
        close(sock_fd);
        return NULL;
    }
    
    if (connect(sock_fd, (struct sockaddr*)&server_addr, sizeof(server_addr)) < 0) {
        perror("[Client] connect");
        close(sock_fd);
        return NULL;
    }
    
    printf("[Client] Thread %d: Connected to %s:%d\n", 
           config->thread_id, config->server_ip, config->port);
    
    /* Prepare objects */
    char *recv_buf = NULL;
    Message *msg = NULL;
    struct iovec iov[NUM_FIELDS];
    struct msghdr msgh = {0};
    size_t buf_size = 0;
    unsigned long pending_completions = 0;
    
    if (config->is_sender) {
        /* Enable Zero-Copy on socket */
        int optval = 1;
        if (setsockopt(sock_fd, SOL_SOCKET, SO_ZEROCOPY, &optval, sizeof(optval)) < 0) {
            perror("[Client] setsockopt SO_ZEROCOPY");
            /* proceed? usually fatal for "Zero Copy" impl, but we can try without flag if OS fails, but task requires it. */
        }
        
        msg = allocate_message(config->message_size);
        if (!msg) {
             close(sock_fd);
             return NULL;
        }
        for (int i = 0; i < NUM_FIELDS; i++) {
            iov[i].iov_base = msg->fields[i];
            iov[i].iov_len = msg->field_sizes[i];
        }
        msgh.msg_iov = iov;
        msgh.msg_iovlen = NUM_FIELDS;
        
    } else {
        /* Receiver: Standard Buffer */
        recv_buf = (char*)malloc(config->message_size);
        buf_size = config->message_size;
        if (!recv_buf) {
            fprintf(stderr, "[Client] Alloc failed\n");
            close(sock_fd);
            return NULL;
        }
    }
    
    double start_time = get_time_sec();
    double end_time = start_time + config->duration;
    double first_msg_time = 0;
    double last_msg_time = 0;
    
    config->bytes_sent = 0;
    config->messages_sent = 0;
    
    /* Loop for fixed duration */
    while (client_running && get_time_sec() < end_time) {
        double msg_start = get_time_us();
        ssize_t ret;
        
        if (config->is_sender) {
             /* Zero-copy Send */
             ret = sendmsg(sock_fd, &msgh, MSG_ZEROCOPY);
             if (ret <= 0) {
                 if (ret < 0 && errno == ENOBUFS) {
                     /* Drain completions and retry */
                     while (poll_zerocopy_completion(sock_fd) > 0) pending_completions--;
                     continue;
                 }
             }
        } else {
             /* Receive */
             ret = recv(sock_fd, recv_buf, buf_size, MSG_WAITALL);
        }
        
        if (ret <= 0) {
            if (ret < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != ENOBUFS) {
               // perror("[Client] IO error");
            }
            if (ret == 0) break; // closed
            if (ret < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) continue;
            if (ret < 0) break; // other error
        } else {
            /* Success */
            if (config->is_sender) {
                pending_completions++;
                 if (pending_completions > 16) {
                    while (poll_zerocopy_completion(sock_fd) > 0) pending_completions--;
                 }
            }
            
            double msg_end = get_time_us();
            if (config->messages_sent == 0) first_msg_time = msg_end - msg_start;
            last_msg_time = msg_end - msg_start;
            
            config->bytes_sent += ret;
            config->messages_sent++;
        }
    }
    
    /* Drain remaining completions if sender */
    if (config->is_sender) {
        while (pending_completions > 0 && poll_zerocopy_completion(sock_fd) > 0) {
            pending_completions--;
        }
    }
    
    double actual_duration = get_time_sec() - start_time;
    
    /* Calculate throughput (Gbps) */
    config->throughput_gbps = (config->bytes_sent * 8.0) / (actual_duration * 1e9);
    
    /* Calculate average latency */
    config->latency_us = (first_msg_time + last_msg_time) / 2.0;
    
    printf("[Client] Thread %d (%s): Transferred %llu bytes (%llu msgs) in %.2f sec, "
           "Throughput: %.3f Gbps, Latency: %.2f us\n",
           config->thread_id, config->is_sender ? "Sender" : "Receiver",
           config->bytes_sent, config->messages_sent,
           actual_duration, config->throughput_gbps, config->latency_us);
    
    if (config->is_sender) {
        free_message(msg);
    } else {
        free(recv_buf);
    }
    close(sock_fd);
    return NULL;
}

int main(int argc, char *argv[]) {
    char *server_ip = "127.0.0.1";
    int port = DEFAULT_PORT;
    size_t message_size = 1024;
    int num_threads = 1;
    int duration = DEFAULT_DURATION;
    int is_sender = 0; /* Default Receiver for A3 client */

    /* Parse arguments */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-i") == 0 && i + 1 < argc) {
            server_ip = argv[++i];
        } else if (strcmp(argv[i], "-p") == 0 && i + 1 < argc) {
            port = atoi(argv[++i]);
        } else if (strcmp(argv[i], "-s") == 0 && i + 1 < argc) {
            message_size = parse_size(argv[++i]);
        } else if (strcmp(argv[i], "-t") == 0 && i + 1 < argc) {
            num_threads = atoi(argv[++i]);
        } else if (strcmp(argv[i], "-d") == 0 && i + 1 < argc) {
            duration = atoi(argv[++i]);
        } else if (strcmp(argv[i], "-m") == 0 && i + 1 < argc) {
            if (strcmp(argv[++i], "sender") == 0) is_sender = 1;
            else is_sender = 0;
        } else if (strcmp(argv[i], "-h") == 0) {
            printf("Usage: %s [-i ip] [-p port] [-s size] [-t threads] [-d duration] [-m sender|receiver]\n", argv[0]);
            return 0;
        }
    }
    
    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);
    
    printf("[Client A3 - Zero-Copy] Connecting to %s:%d\n", server_ip, port);
    printf("[Client A3] Mode: %s, Message size: %zu bytes, Threads: %d, Duration: %d sec\n",
           is_sender ? "SENDER" : "RECEIVER", message_size, num_threads, duration);
    
    /* Allocate thread configs */
    pthread_t *threads = (pthread_t*)malloc(num_threads * sizeof(pthread_t));
    ClientConfig *configs = (ClientConfig*)malloc(num_threads * sizeof(ClientConfig));
    
    /* Start client threads */
    for (int i = 0; i < num_threads; i++) {
        configs[i].thread_id = i;
        configs[i].server_ip = server_ip;
        configs[i].port = port;
        configs[i].message_size = message_size;
        configs[i].duration = duration;
        configs[i].is_sender = is_sender;
        configs[i].bytes_sent = 0;
        configs[i].messages_sent = 0;
        
        if (pthread_create(&threads[i], NULL, client_thread, &configs[i]) != 0) {
            perror("pthread_create");
            configs[i].bytes_sent = 0;
        }
    }
    
    /* Wait for all threads */
    for (int i = 0; i < num_threads; i++) {
        pthread_join(threads[i], NULL);
    }
    
    /* Aggregate results */
    double total_throughput = 0;
    double avg_latency = 0;
    unsigned long long total_bytes = 0;
    unsigned long long total_messages = 0;
    int valid_threads = 0;
    
    for (int i = 0; i < num_threads; i++) {
        if (configs[i].bytes_sent > 0) {
            total_throughput += configs[i].throughput_gbps;
            avg_latency += configs[i].latency_us;
            total_bytes += configs[i].bytes_sent;
            total_messages += configs[i].messages_sent;
            valid_threads++;
        }
    }
    
    if (valid_threads > 0) {
        avg_latency /= valid_threads;
    }
    
    /* Print summary in CSV-parseable format */
    printf("\n=== RESULTS ===\n");
    printf("TYPE,zero_copy\n");
    printf("MESSAGE_SIZE,%zu\n", message_size);
    printf("THREADS,%d\n", num_threads);
    printf("TOTAL_BYTES,%llu\n", total_bytes);
    printf("TOTAL_MESSAGES,%llu\n", total_messages);
    printf("THROUGHPUT_GBPS,%.6f\n", total_throughput);
    printf("LATENCY_US,%.2f\n", avg_latency);
    
    free(threads);
    free(configs);
    
    printf("[Client A3] Complete\n");
    return 0;
}
