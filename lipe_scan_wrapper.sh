#!/bin/sh

## Input arguments:
## $0 <DATAFILE_DIR> -newer <TIMESTAMP_FILE> -size <SIZE>c -name "<PATTERN>"
## e.g.
## $0 /exafs/io500/datafiles/2025.05.10-09.18.25 -newer ./results/2025.05.10-09.18.25/timestampfile -size 3901c -name "*01*"

LIPE_SCAN=/tmp/io500/lipe_scan_io500.sh
LIPE_IO500_DIR=/tmp/io500
IO500_RESULT_DIR=$(dirname $3)
LIPE_SCAN_RESULT_DIR=${IO500_RESULT_DIR}/lipe_scan_results

TIMESTAMP_FILE=$3
TIMESTAMP=$((`date "+%s" -r $TIMESTAMP_FILE` * 1000))
EXA_USER=root
EXA_MDS=ai400x2-2-vm[1-4]

mkdir $LIPE_SCAN_RESULT_DIR
# Run lipe_scan on all MDTs across MDS nodes
clush -l ${EXA_USER} -w ${EXA_MDS} ${LIPE_SCAN} ${LIPE_IO500_DIR} ${TIMESTAMP}

# Retrieve all config and result JSON files into local directory
clush -l ${EXA_USER} -w ${EXA_MDS} --rcopy ${LIPE_IO500_DIR}/*.json --dest=${LIPE_SCAN_RESULT_DIR}

# Sum matched and scanned counts across all result files
MATCHED_TOTAL=0
SCANNED_TOTAL=0

for file in $LIPE_SCAN_RESULT_DIR/*/*_result.json; do
  MATCHED=$(grep -A2 '"name":"matched"' "$file" | grep '"count":' | awk -F ':' '{print $2}' | tr -d ' ,')
  SCANNED=$(grep -A2 '"name":"scanned"' "$file" | grep '"count":' | awk -F ':' '{print $2}' | tr -d ' ,')

  MATCHED_TOTAL=$((MATCHED_TOTAL + MATCHED))
  SCANNED_TOTAL=$((SCANNED_TOTAL + SCANNED))
done

echo "MATCHED ${MATCHED_TOTAL}/${SCANNED_TOTAL}"
