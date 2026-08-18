#!/usr/bin/env bash
#
# mayhem/build.sh — build mtr-packet's fuzz harnesses + the project's own test suite.
#
# Runs inside the commit image (mayhem/Dockerfile) as `mayhem` in /mayhem.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# mtr ships no committed `configure` (autotools generated). Regenerating it is local-only
# (aclocal/autoheader/automake/autoconf over the tree already in /mayhem) — no network needed,
# and safe to re-run (idempotent: --add-missing --copy only fills in what's missing).
./bootstrap.sh
./configure CC="$CC" --without-gtk --without-jansson --without-ncurses --without-ncursesw --without-ipinfo

# mtr-packet's constituent sources (Makefile.am mtr_packet_SOURCES), minus packet/packet.c
# (which owns main() and the CLI/capability-drop glue — not part of the fuzzed parsing surface).
# WITH_ERROR (portability/error.c) is unused on glibc/Linux: `error()` is a libc symbol here.
PKT_SRCS="packet/cmdparse.c packet/command.c packet/probe.c packet/timeval.c packet/sockaddr.c packet/construct_unix.c packet/deconstruct_unix.c packet/probe_unix.c packet/wait_unix.c"

# One pair (fuzzer + standalone reproducer) per upstream fuzz/*.c harness (added by mtr itself
# in commit f4cf5c3, "dos fixed, oss fuzz integration added"). Both link the SAME sanitized
# project sources so the fuzzed code (not just the harness) carries ASan/UBSan + DWARF<4.
build_pair() {
  local name="$1" harness="$2"
  "$CC" $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE -I. -Ipacket \
    "$harness" $PKT_SRCS -lm -o "/mayhem/$name"
  "$CC" $SANITIZER_FLAGS $DEBUG_FLAGS "$STANDALONE_FUZZ_MAIN" -I. -Ipacket \
    "$harness" $PKT_SRCS -lm -o "/mayhem/$name-standalone"
}

build_pair mtr-fuzz-ip4            fuzz/fuzz_handle_received_ip4_packet.c
build_pair mtr-fuzz-ip6            fuzz/fuzz_handle_received_ip6_packet.c
build_pair mtr-fuzz-errqueue       fuzz/fuzz_handle_error_queue_packet.c
build_pair mtr-fuzz-parse-command  fuzz/fuzz_parse_command.c

# Build (do NOT run) the project's own test suite with NORMAL flags — a separate, unsanitized
# build so mayhem/test.sh stays an honest oracle. check_PROGRAMS are automake's.
make -j"$MAYHEM_JOBS" mtr-packet-listen format-count-test CFLAGS="-g -O2 ${COVERAGE_FLAGS}"

# Additive behavioral self-test (see mayhem/selftest_cmdparse.c) for packet/cmdparse.c's
# parse_command() — needs no sockets/capabilities, unlike mtr-packet itself.
"$CC" -O2 "${COVERAGE_FLAGS}" -I. -Ipacket \
  mayhem/selftest_cmdparse.c packet/cmdparse.c -o /mayhem/mayhem-selftest-cmdparse
