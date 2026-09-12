#!/usr/bin/env python3
"""Exercise the actual patched Darwin receive functions before runtime builds."""

from pathlib import Path
import subprocess
import sys
import tempfile


PRELUDE = r'''
#include <assert.h>
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>
#define unlikely(x) (x)
#define render_log(...) ((void)0)
#define proxy_log(...) ((void)0)
struct render_context_socket_header { uint32_t length; };
struct render_socket { int fd; bool is_seqpacket; };
struct proxy_socket { int fd; bool is_seqpacket; };
'''

HARNESS = r'''
static int open_fds(void) {
    int count = 0;
    for (int fd = 0; fd < 1024; fd++) count += fcntl(fd, F_GETFD) >= 0;
    return count;
}
static void run_case(uint32_t length, int payload, int passed_fds,
                     int header_bytes, bool expected) {
    fprintf(stderr, "case length=%u payload=%d fds=%d header=%d\n",
            length, payload, passed_fds, header_bytes);
    int pair[2];
    assert(socketpair(AF_UNIX, SOCK_STREAM, 0, pair) == 0);
    int original = open("/dev/null", O_RDONLY);
    assert(original >= 0);
    pid_t child = fork();
    assert(child >= 0);
    if (!child) {
        close(pair[0]);
        uint32_t header = htonl(length);
        char control[CMSG_SPACE(16 * sizeof(int))] = {0};
        struct iovec iov = { .iov_base = &header, .iov_len = 1 };
        struct msghdr message = { .msg_iov = &iov, .msg_iovlen = 1 };
        if (passed_fds) {
            message.msg_control = control;
            message.msg_controllen = CMSG_SPACE(passed_fds * sizeof(int));
            struct cmsghdr *cmsg = CMSG_FIRSTHDR(&message);
            cmsg->cmsg_level = SOL_SOCKET;
            cmsg->cmsg_type = SCM_RIGHTS;
            cmsg->cmsg_len = CMSG_LEN(passed_fds * sizeof(int));
            for (int i = 0; i < passed_fds; i++)
                ((int *)CMSG_DATA(cmsg))[i] = original;
        }
        if (header_bytes) assert(sendmsg(pair[1], &message, 0) == 1);
        for (int i = 1; i < header_bytes; i++) {
            usleep(1000);
            if (write(pair[1], (char *)&header + i, 1) < 0) _exit(0);
        }
        for (int i = 0; i < payload; i++) {
            usleep(1000);
            if (write(pair[1], "x", 1) < 0) _exit(0);
        }
        close(pair[1]);
        _exit(0);
    }
    close(pair[1]);
    const int before = open_fds();
    char data[8] = {0};
    char control[CMSG_SPACE(8 * sizeof(int))] = {0};
    struct iovec iov = { .iov_base = data, .iov_len = sizeof(data) };
    struct msghdr message = { .msg_iov = &iov, .msg_iovlen = 1,
                             .msg_control = control, .msg_controllen = sizeof(control) };
    struct SOCKET_TYPE socket = { .fd = pair[0], .is_seqpacket = false };
    size_t received = 0;
    bool result = RECEIVE_CALL;
    assert(result == expected);
    if (result) {
        assert(memcmp(data, "xxxxxxxx", length) == 0);
        int count;
        const int *fds = get_received_fds(&message, &count);
        assert(count == passed_fds);
        for (int i = 0; i < count; i++) {
            assert(fcntl(fds[i], F_GETFD) & FD_CLOEXEC);
            close(fds[i]);
        }
    }
    const int after = open_fds();
    if (after != before) fprintf(stderr, "fd count before=%d after=%d\n", before, after);
    assert(after == before);
    close(pair[0]);
    close(original);
    int status;
    assert(waitpid(child, &status, 0) == child);
}
int main(void) {
    alarm(15);
    run_case(8, 8, 1, 4, true);  /* fragmented header/data with fd */
    run_case(8, 8, 0, 4, true);
    run_case(8, 0, 0, 0, false); /* immediate EOF */
    run_case(8, 0, 1, 2, false); /* truncated header closes fd */
    run_case(8, 3, 1, 4, false); /* truncated body closes fd */
    run_case(0, 0, 1, 4, false);
    run_case(9, 0, 1, 4, false); /* oversized length */
    run_case(UINT32_MAX, 0, 1, 4, false);
    run_case(8, 8, 16, 4, false); /* truncated ancillary data closes fds */
    SHORT_REPLY_CASE
    puts("SOCKET_TYPE fragmented/EOF/bounds/fd tests passed");
}
'''


def main() -> None:
    source = Path(sys.argv[1])
    with tempfile.TemporaryDirectory(prefix="venus-socket-test.") as directory:
        directory = Path(directory)
        for kind, relative in (("render", "server/render_socket.c"),
                               ("proxy", "src/proxy/proxy_socket.c")):
            code = (source / relative).read_text()
            # Compile the exact production helper and receive function bodies.
            cloexec = code[code.index("static int\n" + kind + "_socket_set_cloexec"):
                           code.index("#endif")]
            start = code.index("static const int *\nget_received_fds")
            end = code.index("static bool\n" + kind + "_socket_receive_", start)
            receive = (f'{kind}_socket_recvmsg(&socket, &message, &received)'
                       if kind == "render" else f'{kind}_socket_recvmsg(&socket, &message)')
            harness = HARNESS.replace("SOCKET_TYPE", kind + "_socket")
            harness = harness.replace("RECEIVE_CALL", receive)
            harness = harness.replace("SHORT_REPLY_CASE", 'run_case(4, 4, 1, 4, false);'
                                      if kind == "proxy" else 'run_case(4, 4, 1, 4, true);')
            unit = directory / (kind + '.c')
            unit.write_text(PRELUDE + cloexec + code[start:end] + harness)
            executable = directory / kind
            subprocess.run(['cc', '-std=c11', '-O2', '-Wall', str(unit), '-o', str(executable)],
                           check=True)
            subprocess.run([str(executable)], check=True, timeout=20)


if __name__ == '__main__':
    main()
