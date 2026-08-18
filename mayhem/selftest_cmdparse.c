/*
 * mayhem/selftest_cmdparse.c — additive behavioral self-test for packet/cmdparse.c's
 * parse_command(), the same command-parsing entry point mtr-fuzz-parse-command fuzzes and
 * mtr-packet's real IPC protocol relies on. Exists so mayhem/test.sh has a positive, printed-
 * output assertion: mtr-packet itself needs CAP_NET_RAW just to initialize (it opens raw
 * sockets eagerly at startup, even for capability queries that don't need one), which the
 * unprivileged docker-build sandbox that runs mayhem/test.sh does not grant, so it can't be
 * used as the IPC-protocol oracle here. parse_command() needs no sockets/capabilities at all.
 */
#include <stdio.h>
#include <string.h>

#include "cmdparse.h"

int main(void)
{
    struct command_t command;
    char input[] = "42 check-support feature version";

    memset(&command, 0, sizeof(command));
    if (parse_command(&command, input) != 0) {
        printf("parse-failed\n");
        return 1;
    }

    printf("token=%d name=%s argc=%d arg0-name=%s arg0-value=%s\n",
           command.token, command.command_name, command.argument_count,
           command.argument_name[0], command.argument_value[0]);
    return 0;
}
