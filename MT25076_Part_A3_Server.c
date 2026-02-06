/* MT25076 - Part A3: Zero-Copy Server Implementation
 * Uses sendmsg() with MSG_ZEROCOPY flag
 * 
 * Zero-copy mechanism:
 * - Kernel pins user pages instead of copying
 * - DMA directly from user buffer to NIC
 * - Requires polling error queue for completion notifications
 * 
 * Kernel behavior:
 * User Buffer -> [Pin pages] -> NIC DMA (no CPU copy)
 *            |
 *            +-> [Completion notification via error queue]
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

volatile sig_atomic_t server_running = 1;

void handle_signal(int sig) {
    (void)sig;
    server_running = 0;
}

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
    struct iovec iov[NUM_FIELDS];
    struct msghdr msgh = {0};
    unsigned long pending_completions = 0;
    
    if (args->is_sender) {
        /* Enable zero-copy on socket */
        int optval = 1;
        if (setsockopt(client_fd, SOL_SOCKET, SO_ZEROCOPY, &optval, sizeof(optval)) < 0) {
            perror("[Server] setsockopt SO_ZEROCOPY");
            /* Continue without zerocopy if not supported? */
        }
        msg = allocate_message(message_size);
        if (!msg) {
            fprintf(stderr, "[Server] failed to allocate msg\n");
            close(client_fd);
            free(args);
            return NULL;
        }
        /* Setup iovec */
        for (int i = 0; i < NUM_FIELDS; i++) {
            iov[i].iov_base = msg->fields[i];
            iov[i].iov_len = msg->field_sizes[i];
        }
        msgh.msg_iov = iov;
        msgh.msg_iovlen = NUM_FIELDS;
    } else {
        /* Receiver mode */
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
    
    /* Loop until disconnect */
    while (server_running) {
        ssize_t ret;
        
        if (args->is_sender) {
             /* Zero-copy Send */
             ret = sendmsg(client_fd, &msgh, MSG_ZEROCOPY);
             if (ret <= 0) {
                 if (ret < 0 && errno == ENOBUFS) {
                    while (poll_zerocopy_completion(client_fd) > 0) pending_completions--;
                    continue;
                 }
             }
        } else {
             /* Receiver */
             ret = recv(client_fd, buf, buf_size, MSG_WAITALL);
        }
        
        if (ret <= 0) {
            if (ret < 0 && errno != EPIPE && errno != ECONNRESET && errno != ENOBUFS && errno != EAGAIN) {
               // perror("[Server] IO error");
            }
            if (ret == 0) break;
            if (ret < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) continue;
            if (ret < 0 && errno != ENOBUFS) break; 
        } else {
            /* Success path */
            if (args->is_sender) {
                 pending_completions++;
                 if (pending_completions > 16) {
                    while (poll_zerocopy_completion(client_fd) > 0) pending_completions--;
                 }
            }
            total_bytes += ret;
            total_messages++;
        }
    }
    
    /* Drain remaining completions */
    if (args->is_sender) {
        while (pending_completions > 0 && poll_zerocopy_completion(client_fd) > 0) {
            pending_completions--;
        }
    }
    
    printf("[Server] Thread %d (%s): Transferred %llu bytes (%llu messages)\n", 
           args->thread_id, args->is_sender ? "Sender" : "Receiver", total_bytes, total_messages);
    
    if (args->is_sender) {
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
    size_t message_size = 1024;
    int is_sender = 1; /* Default: Server is Sender */
    
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
    
    printf("[Server A3 - Zero-Copy] Listening on port %d, message size: %zu bytes, Mode: %s\n", 
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
        
        // printf("[Server] Accepted connection from %s:%d\n", ...);
        
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
    printf("[Server A3] Shutdown complete\n");
    return 0;
}
