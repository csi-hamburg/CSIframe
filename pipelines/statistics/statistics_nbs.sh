#!/usr/bin/env bash
set -x

###################################################################################################################
# Network-based statistic                                                                                         #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [manual preparation]                                                                                          #
#       - hypothesis directory in data/statistics with design_matrix.txt, contrast_matrix and files.txt           #
#   [pipelines which need to be run first]                                                                        #
#       - fba levels 1-4                                                                                          #
#   [container]                                                                                                   #
#       - mrtrix3-3.0.2.sif                                                                                       #
###################################################################################################################

# Define subject array

input_subject_array=($@)

# Define environment
#########################
module load parallel

container_mrtrix3=mrtrix3-3.0.2      
export SINGULARITYENV_MRTRIX_TMPFILE_DIR=$TMP_DIR

singularity_mrtrix3="singularity run --cleanenv --userns \
    -B . \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    $ENV_DIR/$container_mrtrix3" 

#########################
# TFCE
#########################

STATISTICS_DIR=$DATA_DIR/statistics/${MODIFIER}
[ ! -d $STATISTICS_DIR ] && mkdir -p $STATISTICS_DIR && echo "Please setup $STATISTICS_DIR with 'design_matrix.txt' and 'files.txt'" && exit 0

# Input
#########################
DESIGN_MATRIX=$STATISTICS_DIR/design.txt
CONTRAST=$STATISTICS_DIR/contrast.txt
FILES=$STATISTICS_DIR/files.txt

[ ! -d $STATISTICS_DIR/output/ ] && mkdir -p $STATISTICS_DIR/output/ 

# Command
#########################
CMD_NBS="connectomestats $FILES tfnbs $DESIGN_MATRIX $CONTRAST $STATISTICS_DIR/output/ -force"


# Execution
#########################
$singularity_mrtrix3 $CMD_NBS
