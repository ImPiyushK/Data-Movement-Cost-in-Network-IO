/* MT25076 - Part A3: Zero-Copy Client Implementation
 * Connects to zero-copy server and receives data
 */

#include "MT25076_Part_A_common.h"
#include <sys/uio.h>

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
    
    /* Allocate receive buffers */
    size_t per_field = config->message_size / NUM_FIELDS;
    size_t remainder = config->message_size % NUM_FIELDS;
    
    char *recv_bufs[NUM_FIELDS];
    struct iovec iov[NUM_FIELDS];
    
    for (int i = 0; i < NUM_FIELDS; i++) {
        size_t field_size = per_field + (i < (int)remainder ? 1 : 0);
        recv_bufs[i] = (char*)malloc(field_size);
        if (!recv_bufs[i]) {
            for (int j = 0; j < i; j++) free(recv_bufs[j]);
            close(sock_fd);
            return NULL;
        }
        iov[i].iov_base = recv_bufs[i];
        iov[i].iov_len = field_size;
    }
    
    struct msghdr msgh = {0};
    msgh.msg_iov = iov;
    msgh.msg_iovlen = NUM_FIELDS;
    
    double start_time = get_time_sec();
    double end_time = start_time + config->duration;
    double first_msg_time = 0;
    double last_msg_time = 0;
    
    config->bytes_sent = 0;
    config->messages_sent = 0;
    
    /* Receive data continuously for fixed duration */
    while (client_running && get_time_sec() < end_time) {
        double msg_start = get_time_us();
        
        ssize_t received = recvmsg(sock_fd, &msgh, 0);
        if (received <= 0) {
            if (received < 0) perror("[Client] recvmsg");
            break;
        }
        
        double msg_end = get_time_us();
        
        if (config->messages_sent == 0) {
            first_msg_time = msg_end - msg_start;
        }
        last_msg_time = msg_end - msg_start;
        
        config->bytes_sent += received;
        config->messages_sent++;
    }
    
    double actual_duration = get_time_sec() - start_time;
    
    /* Calculate throughput (Gbps) */
    config->throughput_gbps = (config->bytes_sent * 8.0) / (actual_duration * 1e9);
    
    /* Calculate average latency */
    config->latency_us = (first_msg_time + last_msg_time) / 2.0;
    
    printf("[Client] Thread %d: Received %llu bytes (%llu msgs) in %.2f sec, "
           "Throughput: %.3f Gbps, Latency: %.2f us\n",
           config->thread_id, config->bytes_sent, config->messages_sent,
           actual_duration, config->throughput_gbps, config->latency_us);
    
    for (int i = 0; i < NUM_FIELDS; i++) {
        free(recv_bufs[i]);
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
        } else if (strcmp(argv[i], "-h") == 0) {
            printf("Usage: %s [-i ip] [-p port] [-s size] [-t threads] [-d duration]\n", argv[0]);
            printf("  -i ip        Server IP (default: 127.0.0.1)\n");
            printf("  -p port      Port number (default: %d)\n", DEFAULT_PORT);
            printf("  -s size      Message size, e.g., 1K, 4K, 1M (default: 1K)\n");
            printf("  -t threads   Number of client threads (default: 1)\n");
            printf("  -d duration  Test duration in seconds (default: %d)\n", DEFAULT_DURATION);
            return 0;
        }
    }
    
    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);
    
    printf("[Client A3 - Zero-Copy] Connecting to %s:%d\n", server_ip, port);
    printf("[Client A3] Message size: %zu bytes, Threads: %d, Duration: %d sec\n",
           message_size, num_threads, duration);
    
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
