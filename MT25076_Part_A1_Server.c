/* MT25076 - Part A1: Two-Copy Server Implementation
 * Uses send()/recv() socket primitives - baseline two-copy mechanism
 * 
 * Two copies occur:
 * 1. User space -> Kernel socket buffer (send() system call)
 * 2. Kernel socket buffer -> NIC DMA buffer (handled by kernel)
 */

#include "MT25076_Part_A_common.h"

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
    
    /* Serialize message for sending */
    size_t buf_size;
    char *send_buf = serialize_message(msg, &buf_size);
    if (!send_buf) {
        fprintf(stderr, "[Server] Thread %d: Failed to serialize message\n", args->thread_id);
        free_message(msg);
        close(client_fd);
        free(args);
        return NULL;
    }
    
    unsigned long long total_bytes = 0;
    unsigned long long total_messages = 0;
    
    /* Send messages continuously until client disconnects */
    while (server_running) {
        /* Two-copy: User buffer -> kernel buffer (copy 1) */
        ssize_t sent = send(client_fd, send_buf, buf_size, 0);
        if (sent <= 0) {
            if (sent < 0 && errno != EPIPE && errno != ECONNRESET) {
                perror("[Server] send");
            }
            break;
        }
        total_bytes += sent;
        total_messages++;
    }
    
    printf("[Server] Thread %d: Sent %llu bytes (%llu messages)\n", 
           args->thread_id, total_bytes, total_messages);
    
    free(send_buf);
    free_message(msg);
    close(client_fd);
    free(args);
    return NULL;
}

int main(int argc, char *argv[]) {
    int port = DEFAULT_PORT;
    size_t message_size = 1024;  /* Default 1KB */
    
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
    
    printf("[Server A1 - Two-Copy] Listening on port %d, message size: %zu bytes\n", 
           port, message_size);
    printf("[Server A1] Two copies: (1) send() user->kernel, (2) kernel->NIC DMA\n");
    
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
    printf("[Server A1] Shutdown complete\n");
    return 0;
}
