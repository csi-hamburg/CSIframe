#!/usr/bin/env bash
set -x

###################################################################################################################
# Extraction of radiomics features based on https://pyradiomics.readthedocs.io/en/latest/index.html               #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - wmh (WMH masks and FLAIR in MNI)                                                                        #
#   [optional]                                                                                                    #
#       - freewater (FA, MD, FW)                                                                                  #
#       - fmriprep & xcpengine (ReHo)                                                                             #
#       - aslprep (CBF, CBV)                                                                                      #
#   [container]                                                                                                   #
#       - pyradiomics_latest.sif                                                                                  #
###################################################################################################################

# Define subject array

input_subject_array=($@)

# Define environment
#########################
module load parallel

PYRADIOMICS_DIR=$DATA_DIR/pyradiomics
container_pyradiomics=pyradiomics_latest

[ ! -d $PYRADIOMICS_DIR ] && mkdir -p $PYRADIOMICS_DIR

singularity_pyradiomics="singularity run --cleanenv --userns \
    -B . \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    $ENV_DIR/$container_pyradiomics" 

#########################
# T1w
#########################

# Input
#########################
INPUT=$DATA_DIR/fmriprep/$1/ses-$SESSION/anat/${1}_ses-${session}_space-MNI152NLin6Asym_desc-preproc_T1w.nii.gz
INPUT_WMH_MASK=

# Output
#########################
INTERMED_OUT=$PYRADIOMICS_DIR/$1/ses-$SESSION/anat/T1w_intermed.csv
OUT_WMH_CSV=$PYRADIOMICS_DIR/$1/ses-$SESSION/anat/T1w.csv
INTERMED_OUT=$PYRADIOMICS_DIR/$1/ses-$SESSION/anat/T1w_intermed.csv
OUT_WMH_CSV=$PYRADIOMICS_DIR/$1/ses-$SESSION/anat/T1w.csv


# Command
#########################
CMD_PYRADIOMICS="pyradiomics $INPUT $INPUT_WMH_MASK --out $OUT_WMH_CSV -f csv --mode segment --format-path basename --jobs $SLURM_CPUS_PER_TASK" #--out-dir .

# Execution
#########################
[ -f $INPUT ] && $singularity_pyradiomics $CMD_PYRADIOMICS
awk 'BEGIN{FS=OFS=","} FNR == 1 {print "sub_id" OFS $0}' $INTERMED_OUT > $OUT_WMH_CSV
awk -v name=$1 'BEGIN{FS=OFS=","} FNR == 2 {print name OFS $0}' $INTERMED_OUT >> $OUT_WMH_CSV
rm -rf $INTERMED_OUT


#########################
# FLAIR
#########################

# Input
#########################
INPUT=
INPUT_WMH_MASK=

# Output
#########################
INTERMED_OUT=$PYRADIOMICS_DIR/$1/ses-$SESSION/anat/FLAIR_intermed.csv
OUT_WMH_CSV=$PYRADIOMICS_DIR/$1/ses-$SESSION/anat/FLAIR.csv


# Command
#########################
CMD_PYRADIOMICS="pyradiomics $INPUT $INPUT_WMH_MASK --out $OUT_WMH_CSV -f csv --mode segment --format-path basename --jobs $SLURM_CPUS_PER_TASK" #--out-dir .

# Execution
#########################
[ -f $INPUT ] && $singularity_pyradiomics $CMD_PYRADIOMICS
awk 'BEGIN{FS=OFS=","} FNR == 1 {print "sub_id" OFS $0}' $INTERMED_OUT > $OUT_WMH_CSV
awk -v name=$1 'BEGIN{FS=OFS=","} FNR == 2 {print name OFS $0}' $INTERMED_OUT >> $OUT_WMH_CSV
rm -rf $INTERMED_OUT



#########################
# FAt
#########################

# Input
#########################
INPUT=$DATA_DIR/freewater/$1/ses-${SESSION}/dwi/${1}_ses-${SESSION}_space-MNI_desc-FWcorrected_FA.nii.gz
INPUT_WMH_MASK=

# Output
#########################
INTERMED_OUT=$PYRADIOMICS_DIR/$1/ses-$SESSION/anat/FAt_intermed.csv
OUT_WMH_CSV=$PYRADIOMICS_DIR/$1/ses-$SESSION/anat/FAt.csv


# Command
#########################
CMD_PYRADIOMICS="pyradiomics $INPUT $INPUT_WMH_MASK --out $OUT_WMH_CSV -f csv --mode segment --format-path basename --jobs $SLURM_CPUS_PER_TASK"

# Execution
#########################
[ -f $INPUT ] && $singularity_pyradiomics $CMD_PYRADIOMICS
awk 'BEGIN{FS=OFS=","} FNR == 1 {print "sub_id" OFS $0}' $INTERMED_OUT > $OUT_WMH_CSV
awk -v name=$1 'BEGIN{FS=OFS=","} FNR == 2 {print name OFS $0}' $INTERMED_OUT >> $OUT_WMH_CSV
rm -rf $INTERMED_OUT



#########################
# MDt
#########################

# Input
#########################
INPUT=$DATA_DIR/freewater/$1/ses-${SESSION}/dwi/${1}_ses-${SESSION}_space-MNI_desc-FWcorrected_MD.nii.gz
INPUT_WMH_MASK=

# Output
#########################
INTERMED_OUT=$PYRADIOMICS_DIR/$1/ses-$SESSION/anat/MDt_intermed.csv
OUT_WMH_CSV=$PYRADIOMICS_DIR/$1/ses-$SESSION/anat/MDt.csv


# Command
#########################
CMD_PYRADIOMICS="pyradiomics $INPUT $INPUT_WMH_MASK --out $OUT_WMH_CSV -f csv --mode segment --format-path basename --jobs $SLURM_CPUS_PER_TASK"

# Execution
#########################
[ -f $INPUT ] && $singularity_pyradiomics $CMD_PYRADIOMICS
awk 'BEGIN{FS=OFS=","} FNR == 1 {print "sub_id" OFS $0}' $INTERMED_OUT > $OUT_WMH_CSV
awk -v name=$1 'BEGIN{FS=OFS=","} FNR == 2 {print name OFS $0}' $INTERMED_OUT >> $OUT_WMH_CSV
rm -rf $INTERMED_OUT



#########################
# FW
#########################

# Input
#########################
INPUT=$DATA_DIR/freewater/$1/ses-${SESSION}/dwi/${1}_ses-${SESSION}_space-MNI_FW.nii.gz
INPUT_WMH_MASK=

# Output
#########################
INTERMED_OUT=$PYRADIOMICS_DIR/$1/ses-$SESSION/anat/FW_intermed.csv
OUT_WMH_CSV=$PYRADIOMICS_DIR/$1/ses-$SESSION/anat/FW.csv


# Command
#########################
CMD_PYRADIOMICS="pyradiomics $INPUT $INPUT_WMH_MASK --out $OUT_WMH_CSV -f csv --mode segment --format-path basename --jobs $SLURM_CPUS_PER_TASK"

# Execution
#########################
[ -f $INPUT ] && $singularity_pyradiomics $CMD_PYRADIOMICS
awk 'BEGIN{FS=OFS=","} FNR == 1 {print "sub_id" OFS $0}' $INTERMED_OUT > $OUT_WMH_CSV
awk -v name=$1 'BEGIN{FS=OFS=","} FNR == 2 {print name OFS $0}' $INTERMED_OUT >> $OUT_WMH_CSV
rm -rf $INTERMED_OUT


#########################
# FD
#########################

# Input
#########################
INPUT=
INPUT_WMH_MASK=

# Output
#########################
INTERMED_OUT=$PYRADIOMICS_DIR/$1/ses-$SESSION/anat/FD_intermed.csv
OUT_WMH_CSV=$PYRADIOMICS_DIR/$1/ses-$SESSION/anat/FD.csv


# Command
#########################
CMD_PYRADIOMICS="pyradiomics $INPUT $INPUT_WMH_MASK --out $OUT_WMH_CSV -f csv --mode segment --format-path basename --jobs $SLURM_CPUS_PER_TASK"

# Execution
#########################
[ -f $INPUT ] && $singularity_pyradiomics $CMD_PYRADIOMICS
awk 'BEGIN{FS=OFS=","} FNR == 1 {print "sub_id" OFS $0}' $INTERMED_OUT > $OUT_WMH_CSV
awk -v name=$1 'BEGIN{FS=OFS=","} FNR == 2 {print name OFS $0}' $INTERMED_OUT >> $OUT_WMH_CSV
rm -rf $INTERMED_OUT


#########################
# LOGFC
#########################

# Input
#########################
INPUT=
INPUT_WMH_MASK=

# Output
#########################
INTERMED_OUT=$PYRADIOMICS_DIR/$1/ses-$SESSION/anat/LOGFC_intermed.csv
OUT_WMH_CSV=$PYRADIOMICS_DIR/$1/ses-$SESSION/anat/LOGFC.csv


# Command
#########################
CMD_PYRADIOMICS="pyradiomics $INPUT $INPUT_WMH_MASK --out $OUT_WMH_CSV -f csv --mode segment --format-path basename --jobs $SLURM_CPUS_PER_TASK"

# Execution
#########################
[ -f $INPUT ] && $singularity_pyradiomics $CMD_PYRADIOMICS
awk 'BEGIN{FS=OFS=","} FNR == 1 {print "sub_id" OFS $0}' $INTERMED_OUT > $OUT_WMH_CSV
awk -v name=$1 'BEGIN{FS=OFS=","} FNR == 2 {print name OFS $0}' $INTERMED_OUT >> $OUT_WMH_CSV
rm -rf $INTERMED_OUT


#########################
# FDC
#########################

# Input
#########################
INPUT=
INPUT_WMH_MASK=

# Output
#########################
INTERMED_OUT=$PYRADIOMICS_DIR/$1/ses-$SESSION/anat/FDC_intermed.csv
OUT_WMH_CSV=$PYRADIOMICS_DIR/$1/ses-$SESSION/anat/FDC.csv


# Command
#########################
CMD_PYRADIOMICS="pyradiomics $INPUT $INPUT_WMH_MASK --out $OUT_WMH_CSV -f csv --mode segment --format-path basename --jobs $SLURM_CPUS_PER_TASK"

# Execution
#########################
[ -f $INPUT ] && $singularity_pyradiomics $CMD_PYRADIOMICS
awk 'BEGIN{FS=OFS=","} FNR == 1 {print "sub_id" OFS $0}' $INTERMED_OUT > $OUT_WMH_CSV
awk -v name=$1 'BEGIN{FS=OFS=","} FNR == 2 {print name OFS $0}' $INTERMED_OUT >> $OUT_WMH_CSV
rm -rf $INTERMED_OUT


#########################
# CBV
#########################

# Input
#########################
INPUT=
INPUT_WMH_MASK=

# Output
#########################
INTERMED_OUT=$PYRADIOMICS_DIR/$1/ses-$SESSION/anat/CBV_intermed.csv
OUT_WMH_CSV=$PYRADIOMICS_DIR/$1/ses-$SESSION/anat/CBV.csv


# Command
#########################
CMD_PYRADIOMICS="pyradiomics $INPUT $INPUT_WMH_MASK --out $OUT_WMH_CSV -f csv --mode segment --format-path basename --jobs $SLURM_CPUS_PER_TASK"

# Execution
#########################
[ -f $INPUT ] && $singularity_pyradiomics $CMD_PYRADIOMICS
awk 'BEGIN{FS=OFS=","} FNR == 1 {print "sub_id" OFS $0}' $INTERMED_OUT > $OUT_WMH_CSV
awk -v name=$1 'BEGIN{FS=OFS=","} FNR == 2 {print name OFS $0}' $INTERMED_OUT >> $OUT_WMH_CSV
rm -rf $INTERMED_OUT



#########################
# CBF
#########################

# Input
#########################
INPUT=
INPUT_WMH_MASK=

# Output
#########################
INTERMED_OUT=$PYRADIOMICS_DIR/$1/ses-$SESSION/anat/CBF_intermed.csv
OUT_WMH_CSV=$PYRADIOMICS_DIR/$1/ses-$SESSION/anat/CBF.csv


# Command
#########################
CMD_PYRADIOMICS="pyradiomics $INPUT $INPUT_WMH_MASK --out $OUT_WMH_CSV -f csv --mode segment --format-path basename --jobs $SLURM_CPUS_PER_TASK"

# Execution
#########################
[ -f $INPUT ] && $singularity_pyradiomics $CMD_PYRADIOMICS
awk 'BEGIN{FS=OFS=","} FNR == 1 {print "sub_id" OFS $0}' $INTERMED_OUT > $OUT_WMH_CSV
awk -v name=$1 'BEGIN{FS=OFS=","} FNR == 2 {print name OFS $0}' $INTERMED_OUT >> $OUT_WMH_CSV
rm -rf $INTERMED_OUT