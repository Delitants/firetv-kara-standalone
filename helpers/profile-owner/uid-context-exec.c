#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

static void fail(const char *operation)
{
    fprintf(stderr, "%s: %s\n", operation, strerror(errno));
    exit(111);
}

int main(int argc, char **argv)
{
    char *end = NULL;
    long parsed_uid;
    int context_fd;
    size_t context_length;

    if (argc < 5) {
        fprintf(stderr, "usage: %s UID CONTEXT PROGRAM ARG0 [ARG ...]\n", argv[0]);
        return 64;
    }

    errno = 0;
    parsed_uid = strtol(argv[1], &end, 10);
    if (errno != 0 || end == argv[1] || *end != '\0' || parsed_uid < 1 || parsed_uid > 2147483647L) {
        fprintf(stderr, "invalid UID: %s\n", argv[1]);
        return 64;
    }

    context_fd = open("/proc/self/attr/current", O_WRONLY | O_CLOEXEC);
    if (context_fd < 0)
        fail("open SELinux context");

    if (setgroups(0, NULL) < 0)
        fail("setgroups");
    if (setresgid((gid_t)parsed_uid, (gid_t)parsed_uid, (gid_t)parsed_uid) < 0)
        fail("setresgid");
    if (setresuid((uid_t)parsed_uid, (uid_t)parsed_uid, (uid_t)parsed_uid) < 0)
        fail("setresuid");

    context_length = strlen(argv[2]) + 1;
    if (write(context_fd, argv[2], context_length) != (ssize_t)context_length)
        fail("set SELinux context");
    if (close(context_fd) < 0)
        fail("close SELinux context");

    execv(argv[3], &argv[4]);
    fail("execv");
    return 111;
}
