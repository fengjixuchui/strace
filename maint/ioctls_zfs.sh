#!/bin/sh -efu
#
# Scrape out ioctls from an OpenZFS tree.
# This should only be needed for getting new definitions,
# since OpenZFS is committed to this ABI.
#
# Copyright (c) 2021 The strace developers.
# All rights reserved
#
# SPDX-License-Identifier: LGPL-2.1-or-later

[ -n "$1" ] && cd "$1" || {
	echo "Usage: $0 <path to OpenZFS clone>" >&2
	exit 1
}

ZVER="$(sed '/^Version:[[:space:]]*/!d;s///;q' META)"

source=
executable=
cleanup() {
	trap - EXIT
	rm -f "$source" "$executable"
	exit "$@"
}

trap 'cleanup $?' EXIT
trap 'cleanup 1' HUP PIPE INT QUIT TERM

source="$(mktemp --suffix .c)"
executable="$(mktemp)"

obtain()
{
	local file regexp repl
	file="$1"; shift
	regexp="$1"; shift
	repl='printf("{ \\"'"$file"'\\", \\"\1\\", 0, 0x%04X, 0 },\\n", \1);'
	sed -En "s@$regexp@$repl@p" -- "$file" |
		grep -Ev '_IOC_(BASE|FIRST|LAST|PLATFORM)'
}

{
	zfs_h='include/sys/fs/zfs.h'
	kstat_h='lib/libspl/include/sys/kstat.h'

	cat <<-EOF
		#include <stdio.h>
		#include <$zfs_h>
		#include <$kstat_h>
		int main() {
	EOF

	obtain "$zfs_h" '^[[:space:]]*(ZFS_IOC_[^,[:space:]]+).*'
	obtain "$kstat_h" '^#define[[:space:]]+(KSTAT_IOC_[^[:space:]]+).*'

	echo '}'
} > "$source"

cc -I. -isystem include -isystem lib/libspl/include "$source" -o "$executable"

cat <<-EOF
	/* Generated by ${0##*/} from OpenZFS version $ZVER; do not edit. */
	{ "include/sys/fs/zfs.h", "BLKZNAME", _IOC_READ, (0x12 << 8) | 125, 256 },
EOF

"$executable"