#!/usr/bin/env bash
set -x

###################################################################################################################
# Connectivity-based fixel enhancement                                                                            #
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

[ ! -d $FBA_GROUP_DIR ] && mkdir -p $FBA_GROUP_DIR
singularity_mrtrix3="singularity run --cleanenv --userns \
    -B . \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    $ENV_DIR/$container_mrtrix3" 

#########################
# CFE
#########################

FBA_DIR=$DATA_DIR/fba
FBA_GROUP_DIR=$DATA_DIR/fba/derivatives
STATISTICS_DIR=$DATA_DIR/statistics/$MODIFIER
[ ! -d $STATISTICS_DIR ] && mkdir -p $STATISTICS_DIR && echo "Please setup $STATISTICS_DIR with 'design_matrix.txt' and 'files.txt'" && exit 0

# Input
#########################
FD_SMOOTH_DIR=$FBA_GROUP_DIR/fd_smooth
LOG_FC_SMOOTH_DIR=$FBA_GROUP_DIR/log_fc_smooth
FDC_SMOOTH_DIR=$FBA_GROUP_DIR/fdc_smooth
MATRIX_DIR=$FBA_GROUP_DIR/matrix
DESIGN_MATRIX=$STATISTICS_DIR/design_matrix.txt
FILES=$STATISTICS_DIR/files.txt
CONTRAST=$STATISTICS_DIR/contrast_matrix.txt

# Output
#########################

# Command
#########################
CMD_CFE_FD="fixelcfestats $FD_SMOOTH_DIR $FILES $DESIGN_MATRIX $CONTRAST $MATRIX_DIR $STATISTICS_DIR/stats_fd/"
CMD_CFE_LOG_FC="fixelcfestats $LOG_FC_SMOOTH_DIR $FILES $DESIGN_MATRIX $CONTRAST $MATRIX_DIR $STATISTICS_DIR/stats_log_fc/"
CMD_CFE_FDC="fixelcfestats $FDC_SMOOTH_DIR $FILES $DESIGN_MATRIX $CONTRAST $MATRIX_DIR $STATISTICS_DIR/stats_fdc/"

# Execution
#########################
$singularity_mrtrix3 $CMD_CFE_FD
$singularity_mrtrix3 $CMD_CFE_LOG_FC
$singularity_mrtrix3 $CMD_CFE_FDC