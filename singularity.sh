#!/bin/bash

FS="$1"
NUM_FS="$2"
shift 2

MNT_ID=$((OMPI_COMM_WORLD_RANK % NUM_FS))

singularity exec --bind "/${FS}_${MNT_ID}:/${FS}" "$@"
