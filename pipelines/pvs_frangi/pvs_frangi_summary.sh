#!/usr/bin/env bash

###################################################################################################################
# Simple data summary of the pvs count and volume. Please run this after pvs_postproc.sh
#                                                                                                                 
# Pipeline specific dependencies:                                                                                 
#   [pipelines which need to be run first]                                                                        
#       - fmriprep
#       - wmh     
#       - pvs_postproc                                                                                              
#   [container]                                                                                                   
#       - fsl 
#       - mrtrix 
#                                                                           
###################################################################################################################
# Get verbose outputs
set -x
ulimit -c 0

# Set output directories
DERIVATIVE_dir=$DATA_DIR/$PIPELINE/derivatives
[ ! -d $DERIVATIVE_dir ] && mkdir -p $DERIVATIVE_dir

echo "subject pvs_count pvs_volume" > $DERIVATIVE_dir/pvs_frangi_summary.csv

for sub in $sublist; do  

    # Set subject-specific output directories
    OUT_DIR=$DATA_DIR/$PIPELINE/$sub/ses-${SESSION}/anat/
    [ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR
    export TMP_DIR=$SCRATCH_DIR/$sub/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
    TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
    TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT


    ###################################################################################################################
    # Pipeline execution
    ###################################################################################################################

    if [ -f $DERIVATIVE_dir/${sub}_ses-1_pvscount.csv ]; then 

        echo $sub | tr '\n' ' ' >> $DERIVATIVE_dir/pvs_frangi_summary.csv
        cat $DERIVATIVE_dir/${sub}_ses-1_pvscount.csv | awk '{print $1}' | tr '\n' ' ' >> $DERIVATIVE_dir/pvs_frangi_summary.csv
        cat $DERIVATIVE_dir/${sub}_ses-1_pvsvolume.csv | awk '{print $2}' >> $DERIVATIVE_dir/pvs_frangi_summary.csv 

    fi
    
done
