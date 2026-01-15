#!/bin/sh

LIPE_IO500_DIR=$1
TIMESTAMP=$2
LIPE_SCAN_CONFIG=lipe_scan_io500
LIPE_SCAN_CONFIG_TEMPLATE=${LIPE_SCAN_CONFIG}.json.template

# Run lipe_scan in parallel for each MDT
for path in `df -t lustre | grep mdt | awk '{print $1}'`; do
	MY_MDT_PATH=$path
	MY_MDT=$(basename $MY_MDT_PATH)

	# Generate lipe_scan config file for this MDT
	sed -e "s|@MY_MDT@|$MY_MDT_PATH|" \
	  -e "s|@TS@|$TIMESTAMP|" ${LIPE_IO500_DIR}/${LIPE_SCAN_CONFIG_TEMPLATE} \
	  > ${LIPE_IO500_DIR}/${LIPE_SCAN_CONFIG}_${MY_MDT}_config.json

	# Execute lipe_scan with generated config
	lipe_scan --thread-number=96 \
	  --config-file=${LIPE_IO500_DIR}/${LIPE_SCAN_CONFIG}_${MY_MDT}_config.json \
	  --result-file=${LIPE_IO500_DIR}/${LIPE_SCAN_CONFIG}_${MY_MDT}_result.json \
          --workspace=${LIPE_IO500_DIR} &
done
wait

# Cleanup
[ -d "${LIPE_IO500_DIR}/find_group" ] && rm -rf "${LIPE_IO500_DIR}/find_group"
