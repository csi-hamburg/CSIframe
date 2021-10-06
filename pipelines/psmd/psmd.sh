#!/bin/bash
set -x

# NOTICE: Parallelization does not work with psmd container, as the original psmd.sh script does not tolerate
#         the /psmdtemp directory of a parallel run. Still use container for the sake of reproducibility, or 
#         isolate PSMD calculation and integrate in TBSS pipeline?   

######################################################################
# Submission script for PSMD (https://github.com/miac-research/psmd) #
#                                                                    #
# Pipeline specific dependencies:                                    #
#   [pipelines which need to be run first]                           #
#       - qsiprep                                                    #
#       - freewater                                                  #
#   [container]                                                      #
#       - psmd-1.8.2                                                 #
######################################################################

###################################################################################
# IMPORTANT: This tool is NOT a medical device and for research use only!         #
# Do NOT use this tool for diagnosis, prognosis, monitoring or any other          #
# purpose in clinical use.                                                        #
#                                                                                 #
# This script is provided under the revised BSD (3-clause) license                #
#                                                                                 #
# Copyright (c) 2016-2020, Institute for Stroke and Dementia Research, Munich,    #
# Germany, http://www.isd-muc.de                                                  #
# Copyright (c) 2020, MIAC AG Basel, Switzerland, https://miac.swiss              #
# All rights reserved.                                                            #
#                                                                                 #
# Redistribution and use in source and binary forms, with or without              #
# modification, are permitted provided that the following conditions are met:     #
#     * Redistributions of source code must retain the above copyright            #
#       notice, this list of conditions and the following disclaimer.             #
#     * Redistributions in binary form must reproduce the above copyright         #
#       notice, this list of conditions and the following disclaimer in the       #
#       documentation and/or other materials provided with the distribution.      #
#     * Neither the name of the “Institute for Stroke and Dementia Research”      #
#       nor the names of its contributors may be used to endorse or promote       #
#       products derived from this software without specific prior written        #
#       permission.                                                               #
#                                                                                 #
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND #
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED   #
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE          #
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER BE LIABLE FOR ANY            #
# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES      #
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;    #
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND     #
# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT      #
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS   #
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.                    #
###################################################################################

######################################################################################
# The use of the software needs to be acknowledged through proper citations:         #
#                                                                                    #
# For the PSMD pipeline:                                                             #
# Baykara E, Gesierich B, Adam R, Tuladhar AM, Biesbroek JM, Koek HL, Ropele S,      #
# Jouvent E, Alzheimer’s Disease Neuroimaging Initiative (ADNI), Chabriat H,         #
# Ertl-Wagner B, Ewers M, Schmidt R, de Leeuw FE, Biessels GJ, Dichgans M, Duering M #
# A novel imaging marker for small vessel disease based on skeletonization of        #
# white matter tracts and diffusion histograms                                       #
# Annals of Neurology 2016, 80(4):581-92, DOI: 10.1002/ana.24758                     #
#                                                                                    #
# For FSL-TBSS:                                                                      #
# Follow the guidelines at http://fsl.fmrib.ox.ac.uk/fsl/fslwiki/TBSS                #
######################################################################################

PSMD_DIR=$DATA_DIR/psmd

if [ $ANALYSIS_LEVEL == "subject" ]; then

##########################
# Subject level analysis #
##########################

#cd $DATA_DIR/freewater

#for sub in $(ls -d sub-*); do

    # echo "###################"
    # echo "Processing $sub ..."
    # echo "###################"

    cd $SCRATCH_DIR

    # Define input data

    FA_IMAGE=$DATA_DIR/freewater/$1/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-T1w_desc-DTINoNeg_FA.nii.gz
    MD_IMAGE=$DATA_DIR/freewater/$1/ses-$SESSION/dwi/${1}_ses-${SESSION}_space-T1w_desc-DTINoNeg_MD.nii.gz
    SKELETON_MASK=$PIPELINE_DIR/skeleton_mask_2019.nii.gz

    # Create output directory

    if [ -d $PSMD_DIR/$1/ses-${SESSION} ]; then
        
        rm -rf $PSMD_DIR/$1/ses-${SESSION}
        mkdir -p $PSMD_DIR/$1/ses-${SESSION}/dwi

    else
        
        mkdir -p $PSMD_DIR/$1/ses-${SESSION}/dwi

    fi

    # Run PSMD calculation

    CMD_PSMD_GLOBAL="psmd.sh -f $FA_IMAGE -m $MD_IMAGE -s $SKELETON_MASK -c"
    PSMD_OUTPUT_GLOBAL=`singularity run --cleanenv --userns \
        -B . \
        -B $PROJ_DIR \
        -B $SCRATCH_DIR:/tmp \
        $ENV_DIR/psmd-1.8.2 $CMD_PSMD_GLOBAL`
    PSMD_RESULT_GLOBAL=`echo $PSMD_OUTPUT_GLOBAL | grep "PSMD is" | grep -Eo "[0-9]+\.[0-9][0-9]+"`

    CMD_PSMD_HEMI="psmd.sh -f $FA_IMAGE -m $MD_IMAGE -s $SKELETON_MASK -g -c"
    PSMD_OUTPUT_HEMI=`singularity run --cleanenv --userns \
        -B . \
        -B $PROJ_DIR \
        -B $SCRATCH_DIR:/tmp \
        $ENV_DIR/psmd-1.8.2 $CMD_PSMD_HEMI`
    PSMD_RESULT_HEMI=`echo $PSMD_OUTPUT_HEMI | grep "PSMD is" | grep -Eo "[0-9]+\.[0-9]+\,[0-9]+\.[0-9]+"`

    # Create csv file with results

    echo "Subject,PSMD_global,PSMD_left,PSMD_right" > $PSMD_DIR/$1/ses-${SESSION}/dwi/${1}_ses-${SESSION}_psmd.csv
    echo $1,$PSMD_RESULT_GLOBAL,$PSMD_RESULT_HEMI >> $PSMD_DIR/$1/ses-${SESSION}/dwi/${1}_ses-${SESSION}_psmd.csv

#done

cd $CODE_DIR

########################
# Group level analysis #
########################

elif [ $ANALYSIS_LEVEL == "group" ]; then

    #cho "Please confirm PSMD has been run on participant level (y/n)."
    #read PSMD_RUN

    #if [ $PSMD_RUN == "y" ]; then

        cd $PSMD_DIR
        echo "Subject,PSMD_global,PSMD_left,PSMD_right" > $PSMD_DIR/group_ses-${SESSION}_psmd.csv
    
        for sub in $(ls -d sub-*); do

            tail -n 1 $PSMD_DIR/$sub/ses-${SESSION}/dwi/${sub}_ses-${SESSION}_psmd.csv >> $PSMD_DIR/group_ses-${SESSION}_psmd.csv
        
        done

        cd $CODE_DIR 

    #elif [ $PSMD_RUN == "n" ]; then

    #    echo "Please run PSMD on participant level first. Exiting ..."
    #    exit
    
    #fi

fi
