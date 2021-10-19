#!/bin/bash

#!/bin/bash

# Set output directory
OUT_DIR=data/obseg/
[ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR

# SET VARIABLES FOR CONTAINER TO BE USED
OBSEG_VERSION=olfsegnet_cpu-latest
OBSEG_CONTAINER=$ENV_DIR/$OBSEG_VERSION
###############################################################################################################################################################

singularity="singularity exec --cleanenv --userns -B $PROJ_DIR -B $TMP_DIR:/tmp"

###############################################################################################################################################################
##### STEP 1: OLFACTORY BULB SEGMENTATION BASED ON 3D-T2w
###############################################################################################################################################################
# Define inputs
T2=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_T2w.nii.gz

# Define commands
CMD_OBSEG="python3 /olf-bulb-segmentation/run_pipeline.py --seg_dir /olf-bulb-segmentation/SegModels --loc_dir /olf-bulb-segmentation/LocModels -in $T2 -out $OUT_DIR -sid $1 -ncuda"

# Execute 
$singularity \
$OBSEG_CONTAINER \
$CMD_OBSEG