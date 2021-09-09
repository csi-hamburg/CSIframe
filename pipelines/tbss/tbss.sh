#!/bin/bash
set -x

###############################################################################
# Submission script for TBSS (https://fsl.fmrib.ox.ac.uk/fsl/fslwiki/TBSS)    #
# based on PNL implementation developed by Tashrif Billah, Sylvain Bouix, and #
# Ofer Pasternak, Brigham and Women's Hospital (Harvard Medical School)       #
#                                                                             #
# Pipeline specific dependencies:                                             #
#   [pipelines which need to be run first]                                    #
#       - qsiprep                                                             #
#       - freewater                                                           #
#   [container]                                                               #
#       - tbss_pnl-0.1.5                                                      #
###############################################################################

###############################################################
# Citation for PNL implementation of TBSS                     #
# Billah, Tashrif; Bouix, Sylvain; Pasternak, Ofer;           # 
# Generalized Tract Based Spatial Statistics (TBSS) pipeline, #
# https://github.com/pnlbwh/tbss, 2019,                       #
# DOI: https://doi.org/10.5281/zenodo.2662497                 #
###############################################################

# Define subject array

input_subject_array=($@)

###############################
# Definition of TBSS pipeline #
###############################

if [ $TBSS_PIPELINE == "enigma" ]; then

    ###############
    # ENIGMA TBSS #
    ###############

    echo "Running ENIGMA TBSS pipeline ..."

    # Define output directory
    #########################

    TBSS_DIR=$DATA_DIR/tbss_enigma
    IMAGELIST=$TBSS_DIR/sourcedata/imagelist.csv
    CASELIST=$TBSS_DIR/sourcedata/caselist.csv

    # Define command
    ################

    CMD_TBSS="
        tbss_all \
            --caselist $CASELIST \
            --input $IMAGELIST \
            --modality FA,FAt,AD,ADt,RD,RDt,MD,MDt,FW \
            --enigma \
            --outDir $TBSS_DIR \
            --avg \
            --force \
            --verbose \
            --ncpu 16" 

elif [ $TBSS_PIPELINE == "fmrib" ]; then 

    ##############
    # FMRIB TBSS #
    ##############

    echo "Running FMRIB TBSS pipeline ..."

    # Define output directory
    #########################

    TBSS_DIR=$DATA_DIR/tbss_fmrib
    IMAGELIST=$TBSS_DIR/sourcedata/imagelist.csv
    CASELIST=$TBSS_DIR/sourcedata/caselist.csv

    # Define command
    ################

    CMD_TBSS="
        tbss_all \
            --caselist $CASELIST \
            --input $IMAGELIST \
            --modality FA,FAt,AD,ADt,RD,RDt,MD,MDt,FW \
            --fmrib \
            --labelMap /opt/fsl-6.0.4/data/atlases/JHU/JHU-ICBM-labels-1mm.nii.gz \
            --lut $PIPELINE_DIR/JHU-ICBM-LUT.txt
            --outDir $TBSS_DIR \
            --avg \
            --force \
            --verbose \
            --ncpu 16" 

fi

# TO DO: elif [ $TBSS_PIPELINE == "usertemplate"]

####################################################################################################
# Check input and create imagelist.csv and caselist.csv for tbss in sourcedata of output directory #
####################################################################################################
    
[ -d $TBSS_DIR/sourcedata ] || mkdir -p $TBSS_DIR/sourcedata
echo "TBSS_DIR = $TBSS_DIR"

# Remove old imagelist.csv and caselist.csv; other previous output will be overwritten by --force flag of tbss_all

if [ -f $IMAGELIST ]; then
    rm $IMAGELIST
fi

if [ -f $CASELIST ]; then
    rm $CASELIST
fi

for sub in ${input_subject_array[@]}; do

    # Define input files
        
    FA_IMAGE=$DATA_DIR/freewater/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-T1w_desc-DTINoNeg_FA.nii.gz
    FAt_IMAGE=$DATA_DIR/freewater/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-T1w_desc-FWcorrected_FA.nii.gz
    AD_IMAGE=$DATA_DIR/freewater/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-T1w_desc-DTINoNeg_L1.nii.gz
    ADt_IMAGE=$DATA_DIR/freewater/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-T1w_desc-FWcorrected_L1.nii.gz
    RD_IMAGE=$DATA_DIR/freewater/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-T1w_desc-DTINoNeg_RD.nii.gz
    RDt_IMAGE=$DATA_DIR/freewater/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-T1w_desc-FWcorrected_RD.nii.gz
    MD_IMAGE=$DATA_DIR/freewater/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-T1w_desc-DTINoNeg_MD.nii.gz
    MDt_IMAGE=$DATA_DIR/freewater/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-T1w_desc-FWcorrected_MD.nii.gz
    FW_IMAGE=$DATA_DIR/freewater/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-T1w_FW.nii.gz

    # Check if all input files are present
    
    files_complete=y
    for img in $FA_IMAGE $FAt_IMAGE $FA_IMAGE $FAt_IMAGE $AD_IMAGE $ADt_IMAGE $RD_IMAGE $RDt_IMAGE $MD_IMAGE $MDt_IMAGE $FW_IMAGE; do
        [ -f $img ] || files_complete=n
    done

    # Write $IMAGELIST and $CASELIST
    
    if [ $files_complete == y ];then
        echo $FA_IMAGE,$FAt_IMAGE,$AD_IMAGE,$ADt_IMAGE,$RD_IMAGE,$RDt_IMAGE,$MD_IMAGE,$MDt_IMAGE,$FW_IMAGE >> $IMAGELIST;
        echo $sub >> $CASELIST
    fi

done

############
# Run TBSS #
############

singularity run --cleanenv --userns \
    -B . \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    $ENV_DIR/tbss_pnl-0.1.5 $CMD_TBSS