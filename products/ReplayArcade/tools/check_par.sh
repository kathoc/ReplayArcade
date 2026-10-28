#!/usr/bin/env bash
# tools/check_games.sh over shards in parallel: tools/check_par.sh <ROM dir> <out.tsv> <jobs>
# Summarises the third column (pass / fail / timeout / crash) at the end.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ROMS=$1; OUT=$2; J=${3:-3}
ls "$ROMS" | sed -n 's/\.zip$//p' > "$OUT.games"
split -n r/$J -d "$OUT.games" "$OUT.shard."
for s in "$OUT".shard.??; do bash "$ROOT/tools/check_games.sh" "$ROMS" "$s.tsv" $(cat "$s") & done
wait
cat "$OUT".shard.*.tsv | sort > "$OUT"
cut -f3 "$OUT" | cut -d' ' -f1 | sort | uniq -c
