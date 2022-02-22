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

FILES_FD=$STATISTICS_DIR/files_fd.txt
FILES_LOG_FC=$STATISTICS_DIR/files_log_fc.txt
FILES_FDC=$STATISTICS_DIR/files_fdc.txt
FILES_FA=$STATISTICS_DIR/files_fa.txt
FILES_L1=$STATISTICS_DIR/files_l1.txt
FILES_MD=$STATISTICS_DIR/files_md.txt
FILES_RD=$STATISTICS_DIR/files_rd.txt
FILES_FAt=$STATISTICS_DIR/files_fat.txt
FILES_L1t=$STATISTICS_DIR/files_l1t.txt
FILES_MDt=$STATISTICS_DIR/files_mdt.txt
FILES_RDt=$STATISTICS_DIR/files_rdt.txt
FILES_COMP=$STATISTICS_DIR/files_comp.txt
FILES_FW=$STATISTICS_DIR/files_fw.txt

# Command
#########################
CMD_TFCE_FD="mrclusterstats $FILES_FD $DESIGN_MATRIX $CONTRAST $STATISTICS_DIR/stats_fd/ -force"
CMD_TFCE_FC="mrclusterstats $FILES_LOG_FC $DESIGN_MATRIX $CONTRAST $STATISTICS_DIR/stats_log_fc/ -force"
CMD_TFCE_FDC="mrclusterstats $FILES_FDC $DESIGN_MATRIX $CONTRAST $STATISTICS_DIR/stats_fdc/ -force"
CMD_TFCE_FA="mrclusterstats $FILES_FA $DESIGN_MATRIX $CONTRAST $STATISTICS_DIR/stats_fa/ -force"
CMD_TFCE_L1="mrclusterstats $FILES_L1 $DESIGN_MATRIX $CONTRAST $STATISTICS_DIR/stats_l1/ -force"
CMD_TFCE_MD="mrclusterstats $FILES_MD $DESIGN_MATRIX $CONTRAST $STATISTICS_DIR/stats_md/ -force"
CMD_TFCE_RD="mrclusterstats $FILES_RD $DESIGN_MATRIX $CONTRAST $STATISTICS_DIR/stats_rd/ -force"
CMD_TFCE_FAt="mrclusterstats $FILES_FAt $DESIGN_MATRIX $CONTRAST $STATISTICS_DIR/stats_fat/ -force"
CMD_TFCE_L1t="mrclusterstats $FILES_L1t $DESIGN_MATRIX $CONTRAST $STATISTICS_DIR/stats_l1t/ -force"
CMD_TFCE_MDt="mrclusterstats $FILES_MDt $DESIGN_MATRIX $CONTRAST $STATISTICS_DIR/stats_mdt/ -force"
CMD_TFCE_RDt="mrclusterstats $FILES_RDt $DESIGN_MATRIX $CONTRAST $STATISTICS_DIR/stats_rdt/ -force"
CMD_TFCE_COMP="mrclusterstats $FILES_COMP $DESIGN_MATRIX $CONTRAST $STATISTICS_DIR/stats_comp/ -force"
CMD_TFCE_FW="mrclusterstats $FILES_FW $DESIGN_MATRIX $CONTRAST $STATISTICS_DIR/stats_fw/ -force"

# Execution
#########################
$singularity_mrtrix3 $CMD_TFCE_FD
$singularity_mrtrix3 $CMD_TFCE_LOG_FC
$singularity_mrtrix3 $CMD_TFCE_FDC
$singularity_mrtrix3 $CMD_TFCE_FA
$singularity_mrtrix3 $CMD_TFCE_L1
$singularity_mrtrix3 $CMD_TFCE_MD
$singularity_mrtrix3 $CMD_TFCE_RD
$singularity_mrtrix3 $CMD_TFCE_FAt
$singularity_mrtrix3 $CMD_TFCE_L1t
$singularity_mrtrix3 $CMD_TFCE_MDt
$singularity_mrtrix3 $CMD_TFCE_RDt
$singularity_mrtrix3 $CMD_TFCE_COMP
$singularity_mrtrix3 $CMD_TFCE_FW