#!/usr/bin/env bash

###################################################################################################################
# Resample recon-all output to average spaces (fsaverage, fsLR)                                                   #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - freesurfer_reconall or fmriprep (depends on recon-all)                                                  #
#   [container]                                                                                                   #
#       - connectome_workbench-1.5.0                                                                              #
###################################################################################################################

# Get verbose outputs
set -x

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

###################################################################################################################

# Pipeline-specific environment
##################################

# Singularity container version and command
container_freesurfer=freesurfer-7.1.1
singularity_freesurfer="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_freesurfer" 

container_connectome_workbench=connectome_workbench-1.5.0
singularity_connectome_workbench="singularity run --cleanenv --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_connectome_workbench" 

# To make I/O more efficient read/write outputs from/to scratch 
[ -d $TMP_IN ] && cp -rf $DATA_DIR/cat12/$1 $ENV_DIR/standard/fsaverage7 $ENV_DIR/standard/fsaverage5 $ENV_DIR/standard/fsaverage6 $TMP_IN 
[ ! -d $TMP_OUT/ ] && mkdir -p $TMP_OUT


export SINGULARITYENV_SUBJECTS_DIR=$TMP_IN
export SINGULARITYENV_FS_LICENSE=$ENV_DIR/freesurfer_license.txt
parallel="parallel --ungroup --delay 0.2 -j1 --joblog /tmp/parallel_runtask.log"

CMD_THICK2FSAVG="
   $singularity_connectome_workbench \
   mri_surf2surf \
   --srcsubject $1 
   --trgsubject fsaverage7 \
   --surfreg rh.sphere.reg.T1.gii \
   --hemi {} \
   --sval $1/surf/{}.thickness.T1 \
   --tval $1/surf/{}.fsaverage.thickness.T1.gii \
   --cortex
"

CMD_THICK2FSAVG5="
   $singularity_connectome_workbench \
   mri_surf2surf \
   --srcsubject $1 
   --trgsubject fsaverage5 \
   --hemi {} \
   --sval $1/surf/{}.thickness.T1 \
   --tval $1/surf/{}.fsaverage5.thickness.T1.gii \
   --cortex
"

CMD_THICK2FSAVG6="
   $singularity_connectome_workbench \
   mri_surf2surf \
   --srcsubject $1 
   --trgsubject fsaverage6 \
   --hemi {} \
   --sval $1/surf/{}.thickness.T1 \
   --tval $1/surf/{}.fsaverage6.thickness.T1.gii \
   --cortex
"

CMD_FSAVG2FSLR="
    $singularity_connectome_workbench \
    wb_command \
    -metric-resample \
    $TMP_IN/$1/surf/{1}.fsaverage.thickness.T1.gii \
    $ENV_DIR/standard/fsaverage/tpl-fsaverage_hemi-{2}_den-164k_desc-std_sphere.surf.gii \
    $ENV_DIR/standard/fsLR/tpl-fsLR_space-fsaverage_hemi-{2}_den-{3}_sphere.surf.gii \
    ADAP_BARY_AREA \
    $TMP_IN/$1/surf/{1}.fsLR{3}.thickness.T1.func.gii \
    -area-metrics \
    $ENV_DIR/standard/fsaverage/tpl-fsaverage_hemi-{2}_den-164k_desc-vaavg_midthickness.shape.gii \
    $ENV_DIR/standard/fsLR/tpl-fsLR_hemi-{2}_den-{3}_desc-vaavg_midthickness.shape.gii
"
   
pushd $TMP_IN
$parallel $CMD_THICK2FSAVG ::: lh rh
$parallel $CMD_THICK2FSAVG5 ::: lh rh
$parallel $CMD_THICK2FSAVG6 ::: lh rh
$parallel $CMD_FSAVG2FSLR ::: lh rh :::+ L R ::: 32k 59k 164k
popd

#cp -ruvf $TMP_IN/$1 $DATA_DIR/cat12


#CMD_SPHERE2FSAVG="
#   $singularity_freesurfer \
#   mri_surf2surf \
#   --srcsubject $1 
#   --trgsubject fsaverage \
#   --hemi $hemi \
#   --sval $1/surf/${hemi}.sphere 
#   --tval $1/surf/${hemi}.fsaverage.thickness.gii
#"