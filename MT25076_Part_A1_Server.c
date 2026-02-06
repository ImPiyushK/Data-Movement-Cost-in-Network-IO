/*
 * ----------------------------------------------------------------------------
 * AI USAGE DECLARATION
 * ----------------------------------------------------------------------------
 *
 * Components utilizing AI:
 * - Implementation of Two-Copy Server logic.
 * - Multi-threaded client handling.
 *
 *
 * Verification:
 * The generated code was manually reviewed, compiled, and tested.
 * ----------------------------------------------------------------------------
 */
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
    
    /* Prepare based on mode: If server is Sender, allocate message. If specific receiver, allocate buffer. */
    char *buf = NULL;
    Message *msg = NULL;
    size_t buf_size = 0;
    
    if (args->is_sender) {
        msg = allocate_message(message_size);
        if (!msg) {
            fprintf(stderr, "[Server] failed to allocate msg\n");
            close(client_fd);
            free(args);
            return NULL;
        }
        buf = serialize_message(msg, &buf_size);
        if (!buf) {
            free_message(msg);
            close(client_fd);
            free(args);
            return NULL;
        }
    } else {
        /* Receiver mode: Alloc receive buffer */
        buf = (char*)malloc(message_size);
        buf_size = message_size;
        if (!buf) {
            close(client_fd);
            free(args);
            return NULL;
        }
    }
    
    unsigned long long total_bytes = 0;
    unsigned long long total_messages = 0;
    
    /* Loop until disconnect or error */
    while (server_running) {
        ssize_t ret;
        if (args->is_sender) {
             ret = send(client_fd, buf, buf_size, 0);
        } else {
             ret = recv(client_fd, buf, buf_size, MSG_WAITALL);
        }
        
        if (ret <= 0) {
            if (ret < 0 && errno != EPIPE && errno != ECONNRESET) {
               // perror("[Server] IO Error");
            }
            break;
        }
        total_bytes += ret;
        total_messages++;
    }
    
    printf("[Server] Thread %d (%s): Transferred %llu bytes (%llu messages)\n", 
           args->thread_id, args->is_sender ? "Sender" : "Receiver", total_bytes, total_messages);
    
    if (args->is_sender) {
        free(buf);
        free_message(msg);
    } else {
        free(buf);
    }
    close(client_fd);
    free(args);
    return NULL;
}

int main(int argc, char *argv[]) {
    int port = DEFAULT_PORT;
    size_t message_size = 1024;  /* Default 1KB */
    int is_sender = 1; /* Default: Server is sender */
    
    /* Parse arguments */
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-p") == 0 && i + 1 < argc) {
            port = atoi(argv[++i]);
        } else if (strcmp(argv[i], "-s") == 0 && i + 1 < argc) {
            message_size = parse_size(argv[++i]);
        } else if (strcmp(argv[i], "-m") == 0 && i + 1 < argc) {
             if (strcmp(argv[++i], "sender") == 0) is_sender = 1;
             else is_sender = 0;
        } else if (strcmp(argv[i], "-h") == 0) {
            printf("Usage: %s [-p port] [-s message_size] [-m sender|receiver]\n", argv[0]);
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
    
    printf("[Server A1 - Two-Copy] Listening on port %d, message size: %zu bytes, Mode: %s\n", 
           port, message_size, is_sender ? "SENDER" : "RECEIVER");
    
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
        
        // printf("[Server] Accepted connection\n");
        
        /* Create thread to handle client */
        ServerThreadArgs *args = (ServerThreadArgs*)malloc(sizeof(ServerThreadArgs));
        args->client_fd = client_fd;
        args->thread_id = thread_id++;
        args->message_size = message_size;
        args->is_sender = is_sender;
        
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
