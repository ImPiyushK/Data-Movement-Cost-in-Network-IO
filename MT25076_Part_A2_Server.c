/* MT25076 - Part A2: One-Copy Server Implementation
 * Uses sendmsg() with iovec for scatter-gather I/O
 * 
 * One copy is eliminated by using iovec to send multiple buffers
 * directly without first copying them into a contiguous buffer.
 * 
 * Copy flow:
 * - User space buffers (8 fields) -> kernel via single sendmsg()
 * - Eliminates intermediate user-space buffer concatenation
 */

#include "MT25076_Part_A_common.h"
#include <sys/uio.h>

volatile sig_atomic_t server_running = 1;

void handle_signal(int sig) {
    (void)sig;
    server_running = 0;
}

void* handle_client(void *arg) {
    ServerThreadArgs *args = (ServerThreadArgs*)arg;
    int client_fd = args->client_fd;
    size_t message_size = args->message_size;
    
    printf("[Server] Thread %d: Handling client, message size: %zu bytes\n", 
           args->thread_id, message_size);
    
    /* Create message with 8 heap-allocated fields */
    Message *msg = allocate_message(message_size);
    if (!msg) {
        fprintf(stderr, "[Server] Thread %d: Failed to allocate message\n", args->thread_id);
        close(client_fd);
        free(args);
        return NULL;
    }
    
    /* Setup iovec array for scatter-gather I/O */
    struct iovec iov[NUM_FIELDS];
    for (int i = 0; i < NUM_FIELDS; i++) {
        iov[i].iov_base = msg->fields[i];
        iov[i].iov_len = msg->field_sizes[i];
    }
    
    /* Setup message header */
    struct msghdr msgh = {0};
    msgh.msg_iov = iov;
    msgh.msg_iovlen = NUM_FIELDS;
    
    unsigned long long total_bytes = 0;
    unsigned long long total_messages = 0;
    
    /* Calculate expected message size */
    size_t expected_size = 0;
    for (int i = 0; i < NUM_FIELDS; i++) {
        expected_size += msg->field_sizes[i];
    }
    
    /* Send messages continuously until client disconnects */
    while (server_running) {
        /* One-copy: sendmsg() gathers from multiple buffers without 
         * intermediate user-space concatenation */
        ssize_t sent = sendmsg(client_fd, &msgh, 0);
        if (sent <= 0) {
            if (sent < 0 && errno != EPIPE && errno != ECONNRESET) {
                perror("[Server] sendmsg");
            }
            break;
        }
        total_bytes += sent;
        total_messages++;
    }
    
    printf("[Server] Thread %d: Sent %llu bytes (%llu messages)\n", 
           args->thread_id, total_bytes, total_messages);
    
    free_message(msg);
    close(client_fd);
    free(args);
    return NULL;
}

int main(int argc, char *argv[]) {
    int port = DEFAULT_PORT;
    size_t message_size = 1024;
    
    /* Parse arguments */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-p") == 0 && i + 1 < argc) {
            port = atoi(argv[++i]);
        } else if (strcmp(argv[i], "-s") == 0 && i + 1 < argc) {
            message_size = parse_size(argv[++i]);
        } else if (strcmp(argv[i], "-h") == 0) {
            printf("Usage: %s [-p port] [-s message_size]\n", argv[0]);
            printf("  -p port          Port number (default: %d)\n", DEFAULT_PORT);
            printf("  -s message_size  Message size, e.g., 1K, 4K, 1M (default: 1K)\n");
            return 0;
        }
    }
    
    signal(SIGINT, handle_signal);
    signal(SIGTERM, handle_signal);
    signal(SIGPIPE, SIG_IGN);
    
    /* Create socket */
    int server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) {
        perror("socket");
        return 1;
    }
    
    set_socket_options(server_fd);
    
    struct sockaddr_in addr = {0};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port = htons(port);
    
    if (bind(server_fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        perror("bind");
        close(server_fd);
        return 1;
    }
    
    if (listen(server_fd, BACKLOG) < 0) {
        perror("listen");
        close(server_fd);
        return 1;
    }
    
    printf("[Server A2 - One-Copy] Listening on port %d, message size: %zu bytes\n", 
           port, message_size);
    printf("[Server A2] Uses sendmsg() with iovec - eliminates user-space buffer concatenation\n");
    
    int thread_id = 0;
    while (server_running) {
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);
        
        int client_fd = accept(server_fd, (struct sockaddr*)&client_addr, &client_len);
        if (client_fd < 0) {
            if (errno == EINTR) continue;
            perror("accept");
            break;
        }
        
        set_socket_options(client_fd);
        
        printf("[Server] Accepted connection from %s:%d\n",
               inet_ntoa(client_addr.sin_addr), ntohs(client_addr.sin_port));
        
        /* Create thread to handle client */
        ServerThreadArgs *args = (ServerThreadArgs*)malloc(sizeof(ServerThreadArgs));
        args->client_fd = client_fd;
        args->thread_id = thread_id++;
        args->message_size = message_size;
        
        pthread_t tid;
        if (pthread_create(&tid, NULL, handle_client, args) != 0) {
            perror("pthread_create");
            free(args);
            close(client_fd);
        } else {
            pthread_detach(tid);
        }
    }
    
    close(server_fd);
    printf("[Server A2] Shutdown complete\n");
    return 0;
}
