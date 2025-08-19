#include <sys/types.h>
#include <sys/socket.h>
#include <netdb.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <netinet/in.h>
#include <string.h>
#include <arpa/inet.h>
#include <syslog.h>
#include <fcntl.h>
#include <signal.h>
#include <errno.h>

#define PORT "9000"
#define MAXDATASIZE 100
#define DATAFILE "/var/tmp/aesdsocketdata"
#define BACKLOG 10

volatile sig_atomic_t signal_exit = 0;
int sockfd = -1;  // Make sockfd global for signal handler

void sig_handler(int signo) {
    signal_exit = 1;
    if (sockfd != -1) {
        close(sockfd); // Force accept() to fail and loop to exit
        sockfd = -1;
    }
}

void *get_in_addr(struct sockaddr *sa){
    if(sa->sa_family==AF_INET){
        return &(((struct sockaddr_in*)sa)->sin_addr);
    }
    return &(((struct sockaddr_in6*)sa)->sin6_addr);
}

int main(int argc, char *argv[]) {
    int new_fd;
    struct sockaddr_storage their_addr;
    socklen_t sin_size;
    char buf[MAXDATASIZE];
    struct addrinfo hints, *servinfo, *p;
    int yes=1;
    int rv;
    char s[INET6_ADDRSTRLEN];

    // Daemonize if requested
    if (argc > 1 && strcmp(argv[1], "-d") == 0) {
        if (daemon(0, 0) == -1) {
            perror("daemon");
            return 1;
        }
    }

    openlog("aesdsocket", LOG_PID, LOG_USER);

    struct sigaction sa;
    sa.sa_handler = sig_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);

    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_flags = AI_PASSIVE;

    if ((rv = getaddrinfo(NULL, PORT, &hints, &servinfo)) != 0){
        syslog(LOG_ERR, "getaddrinfo: %s", gai_strerror(rv));
        return 1;
    }

    for (p = servinfo; p != NULL; p = p->ai_next){
        if ((sockfd = socket(p->ai_family, p->ai_socktype, p->ai_protocol)) == -1) {
            syslog(LOG_ERR, "server: socket: %s", strerror(errno));
            continue;
        }

        if (setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(int)) == -1){
            syslog(LOG_ERR, "setsockopt: %s", strerror(errno));
            freeaddrinfo(servinfo);
            closelog();
            return 1;
        }

        if (bind(sockfd, p->ai_addr, p->ai_addrlen) == -1) {
            close(sockfd);
            syslog(LOG_ERR, "server: bind: %s", strerror(errno));
            continue;
        }

        break;
    }

    if (p == NULL){
        syslog(LOG_ERR, "server: failed to bind");
        closelog();
        return 1;
    }

    freeaddrinfo(servinfo);

    if (listen(sockfd, BACKLOG) == -1) {
        syslog(LOG_ERR, "listen: %s", strerror(errno));
        closelog();
        close(sockfd);
        return 1;
    }

    while (!signal_exit) {
        sin_size = sizeof(their_addr);
        new_fd = accept(sockfd, (struct sockaddr *)&their_addr, &sin_size);

        if (signal_exit) break;

        if (new_fd == -1) {
            if (errno != EBADF && errno != EINTR) {
                 syslog(LOG_ERR, "accept: %s", strerror(errno));
            }
            continue;
        }

        inet_ntop(their_addr.ss_family, get_in_addr((struct sockaddr *)&their_addr), s, sizeof s);
        syslog(LOG_INFO, "Accepted connection from %s", s);

        int fd = open(DATAFILE, O_WRONLY | O_CREAT | O_APPEND, 0644);
        if (fd == -1) {
            syslog(LOG_ERR, "open: %s", strerror(errno));
            close(new_fd);
            continue;
        }

        ssize_t numbytes;
        int found_nl = 0;
        while ((numbytes = recv(new_fd, buf, sizeof(buf), 0)) > 0) {
            for (ssize_t i = 0; i < numbytes; ++i) {
                if (write(fd, &buf[i], 1) != 1) {
                    syslog(LOG_ERR, "write: %s", strerror(errno));
                }
                if (buf[i] == '\n') {
                    found_nl = 1;
                }
            }
            if (found_nl) break;
        }

        close(fd);

        fd = open(DATAFILE, O_RDONLY, 0644);
        if (fd != -1) {
            char sendbuf[1024];
            ssize_t readbytes;
            while ((readbytes = read(fd, sendbuf, sizeof(sendbuf))) > 0) {
                if (send(new_fd, sendbuf, readbytes, 0) == -1) {
                    syslog(LOG_ERR, "send: %s", strerror(errno));
                }
            }
            close(fd);
        }

        syslog(LOG_INFO, "Closed connection from %s", s);
        close(new_fd);
    }

    syslog(LOG_INFO, "Caught signal, exiting");
    if (sockfd != -1) {
        close(sockfd);
    }
    remove(DATAFILE);
    closelog();

    return 0;
}
