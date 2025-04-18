#!/usr/bin/env bash
# Tags: no-object-storage, no-random-settings, no-parallel
set -eo pipefail

CURDIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=../shell_config.sh
. "$CURDIR"/../shell_config.sh

QUERY_ID=$(${CLICKHOUSE_CLIENT} -q "select lower(hex(reverse(reinterpretAsString(generateUUIDv4()))))")

${CLICKHOUSE_CLIENT} -q "DROP TABLE IF EXISTS lazy_mark_test;"
${CLICKHOUSE_CLIENT} <<EOF
CREATE TABLE lazy_mark_test
(
  n0 UInt64,
  n1 UInt64,
  n2 UInt64,
  n3 UInt64,
  n4 UInt64,
  n5 UInt64,
  n6 UInt64,
  n7 UInt64,
  n8 UInt64,
  n9 UInt64
)
ENGINE = MergeTree
ORDER BY n0 SETTINGS min_bytes_for_wide_part = 0, ratio_of_defaults_for_sparse_serialization = 1;
EOF

${CLICKHOUSE_CLIENT} -q "SYSTEM STOP MERGES lazy_mark_test"
${CLICKHOUSE_CLIENT} -q "INSERT INTO lazy_mark_test select number, number % 3, number % 5, number % 10, number % 13, number % 15, number % 17, number % 18, number % 22, number % 25 from numbers(1000000)"
${CLICKHOUSE_CLIENT} -q "SYSTEM DROP MARK CACHE"
# max_threads=1 is needed because otherwise OpenedFileCache makes ProfileEvents['FileOpen'] nondeterministic
# (usually all threads access the file at overlapping times, and the file is opened just once;
#  but sometimes a thread is much slower than others and ends opening the same file a second time)
${CLICKHOUSE_CLIENT} --log_queries=1 --query_id "${QUERY_ID}" -q "SELECT * FROM lazy_mark_test WHERE n3==11 SETTINGS load_marks_asynchronously=0, max_threads=1"
${CLICKHOUSE_CLIENT} -q "SYSTEM FLUSH LOGS query_log"

# Expect 2 open files: n3 marks and n3 data.
${CLICKHOUSE_CLIENT} -q "select ProfileEvents['FileOpen'] from system.query_log where query_id = '${QUERY_ID}' and type = 'QueryFinish' and current_database = currentDatabase()"
