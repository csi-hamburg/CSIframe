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
#       - fba (only for fixel branch)                                         #
#   [container]                                                               #
#       - tbss_pnl-0.1.5                                                      #  
#       - fsl-6.0.3                                                           #  
#       - mrtrix3-3.0.2 (only for fixel branch)                               #
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

    # Remove previous run
    #####################

    if [ -f $TBSS_DIR/log/config.ini ]; then
        rm -rf $TBSS_DIR/*/
    fi

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
            --ncpu 1" 

elif [ $TBSS_PIPELINE == "fmrib" ]; then 

    ##############
    # FMRIB TBSS #
    ##############

    echo "Running FMRIB TBSS pipeline ..."

    # Define output directory
    #########################

    TBSS_DIR=$DATA_DIR/tbss_fmrib_scratch
    IMAGELIST=$TBSS_DIR/sourcedata/imagelist.csv
    CASELIST=$TBSS_DIR/sourcedata/caselist.csv

    cp $PIPELINE_DIR/FMRIB58_FA_1mm.nii.gz $SCRATCH_DIR/FMRIB58_FA_1mm.nii.gz
    cp $PIPELINE_DIR/FMRIB58_FA-skeleton_1mm.nii.gz $SCRATCH_DIR/FMRIB58_FA-skeleton_1mm.nii.gz 
    FMRIB_FA=$SCRATCH_DIR/FMRIB58_FA_1mm.nii.gz
    FMRIB_SKEL=$SCRATCH_DIR/FMRIB58_FA-skeleton_1mm.nii.gz

    # Remove previous run
    #####################

    if [ -f $TBSS_DIR/log/config.ini ]; then
        rm -rf $TBSS_DIR/*/
    fi

    # Define command
    ################

    CMD_TBSS="
        tbss_all \
            --caselist $CASELIST \
            --input $IMAGELIST \
            --modality FA,FAt,AD,ADt,RD,RDt,MD,MDt,FW \
            --template $FMRIB_FA \
            --skeleton $FMRIB_SKEL
            --labelMap /opt/fsl-6.0.4/data/atlases/JHU/JHU-ICBM-labels-1mm.nii.gz \
            --lut $PIPELINE_DIR/JHU-ICBM-LUT.txt \
            --outDir $TBSS_DIR \
            --avg \
            --force \
            --verbose \
            --ncpu 32" 

elif [ $TBSS_PIPELINE == "fixel"]; then

    ##############
    # Fixel TBSS #
    ##############

    echo "Running fixel TBSS pipeline ..."
    
    # Set up environment
    ####################
    
    module load parallel
    parallel="parallel --ungroup --delay 0.2 -j 16 --joblog $CODE_DIR/log/parallel_runtask.log"

    singularity_mrtrix3="singularity run --cleanenv --userns \
    -B . \
    -B $PROJ_DIR \
    -B $SCRATCH_DIR:/tmp \
    $ENV_DIR/mrtrix3-3.0.2" 

    # Define input/output for TBSS
    ##############################

    TBSS_DIR=$DATA_DIR/tbss_template
    IMAGELIST=$TBSS_DIR/sourcedata/imagelist.csv
    CASELIST=$TBSS_DIR/sourcedata/caselist.csv
    FA_TEMPLATE=$DATA_DIR/fba/derivatives/template/###

    # Remove previous TBSS run
    ##########################

    if [ -f $TBSS_DIR/log/config.ini ]; then
        rm -rf $TBSS_DIR/*/
    fi

    # Registration of DTI metrics to FOD template space
    ###################################################

    # Input

    FA_IMAGE=$DATA_DIR/freewater/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-T1w_desc-DTINoNeg_FA.nii.gz
    FAt_IMAGE=$DATA_DIR/freewater/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-T1w_desc-FWcorrected_FA.nii.gz
    AD_IMAGE=$DATA_DIR/freewater/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-T1w_desc-DTINoNeg_L1.nii.gz
    ADt_IMAGE=$DATA_DIR/freewater/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-T1w_desc-FWcorrected_L1.nii.gz
    RD_IMAGE=$DATA_DIR/freewater/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-T1w_desc-DTINoNeg_RD.nii.gz
    RDt_IMAGE=$DATA_DIR/freewater/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-T1w_desc-FWcorrected_RD.nii.gz
    MD_IMAGE=$DATA_DIR/freewater/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-T1w_desc-DTINoNeg_MD.nii.gz
    MDt_IMAGE=$DATA_DIR/freewater/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-T1w_desc-FWcorrected_MD.nii.gz
    FW_IMAGE=$DATA_DIR/freewater/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-T1w_FW.nii.gz
    
    SUB2TEMP_WARP=$DATA_DIR/fba/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_acq-AP_from-subject_to-fodtemplate_warp.mif
    FOD_TEMPLATE=$DATA_DIR/fba/derivatives/template/wmfod_template.mif
    FD_IMAGE_REG_MIF=$DATA_DIR/fba/derivatives/fd/{}.mif
    LOG_FC_IMAGE_REG_MIF=$DATA_DIR/fba/derivatives/log_fc/{}.mif
    FDC_IMAGE_REG_MIF=$DATA_DIR/fba/derivatives/fdc/{}.mif

    # Output
    
    [ -d $TBSS_DIR/dti2fod ] || mkdir -p $TBSS_DIR/dti2fod

    FA_IMAGE_REG=$TBSS_DIR/dti2fod/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-DTINoNeg_FA.nii.gz
    FAt_IMAGE_REG=$TBSS_DIR/dti2fod/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-FWcorrected_FA.nii.gz
    AD_IMAGE_REG=$TBSS_DIR/dti2fod/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-DTINoNeg_L1.nii.gz
    ADt_IMAGE_REG=$TBSS_DIR/dti2fod/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-FWcorrected_L1.nii.gz
    RD_IMAGE_REG=$TBSS_DIR/dti2fod/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-DTINoNeg_RD.nii.gz
    RDt_IMAGE_REG=$TBSS_DIR/dti2fod/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-FWcorrected_RD.nii.gz
    MD_IMAGE_REG=$TBSS_DIR/dti2fod/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-DTINoNeg_MD.nii.gz
    MDt_IMAGE_REG=$TBSS_DIR/dti2fod/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtemplate_desc-FWcorrected_MD.nii.gz
    FW_IMAGE_REG=$TBSS_DIR/dti2fod/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtempalte_FW.nii.gz
    FD_IMAGE_REG=$TBSS_DIR/dti2fod/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtempalte_FD.nii.gz
    LOG_FC_IMAGE_REG=$TBSS_DIR/dti2fod/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtempalte_logFC.nii.gz
    FDC_IMAGE_REG=$TBSS_DIR/dti2fod/{}/ses-$SESSION/dwi/{}_ses-${SESSION}_space-fodtempalte_FDC.nii.gz

    # Commands

    CMD_MRCONVERT_FD="mrconvert -nthreads 2 $FD_IMAGE_REG_MIF $FD_IMAGE_REG"
    CMD_MRCONVERT_LOG_FC="mrconvert -nthreads 2 $LOG_FC_IMAGE_REG_MIF $LOG_FC_IMAGE_REG"
    CMD_MRCONVERT_FDC="mrconvert -nthreads 2 $FDC_IMAGE_REG_MIF $FDC_IMAGE_REG"

    CMD_MRTRANSFORM_FA="mrtransform $FA_IMAGE -template $FOD_TEMPLATE -warp $SUB2TEMP_WARP -interp nearest -nthreads 2 -force $FA_IMAGE_REG"
    CMD_MRTRANSFORM_FAt="mrtransform $FAt_IMAGE -template $FOD_TEMPLATE -warp $SUB2TEMP_WARP -interp nearest -nthreads 2 -force $FAt_IMAGE_REG"
    CMD_MRTRANSFORM_AD="mrtransform $AD_IMAGE -template $FOD_TEMPLATE -warp $SUB2TEMP_WARP -interp nearest -nthreads 2 -force $AD_IMAGE_REG"
    CMD_MRTRANSFORM_ADt="mrtransform $ADt_IMAGE -template $FOD_TEMPLATE -warp $SUB2TEMP_WARP -interp nearest -nthreads 2 -force $ADt_IMAGE_REG"
    CMD_MRTRANSFORM_RD="mrtransform $RD_IMAGE -template $FOD_TEMPLATE -warp $SUB2TEMP_WARP -interp nearest -nthreads 2 -force $RD_IMAGE_REG"
    CMD_MRTRANSFORM_RDt="mrtransform $RDt_IMAGE -template $FOD_TEMPLATE -warp $SUB2TEMP_WARP -interp nearest -nthreads 2 -force $RDt_IMAGE_REG"
    CMD_MRTRANSFORM_MD="mrtransform $MD_IMAGE -template $FOD_TEMPLATE -warp $SUB2TEMP_WARP -interp nearest -nthreads 2 -force $MD_IMAGE_REG"
    CMD_MRTRANSFORM_MDt="mrtransform $MDt_IMAGE -template $FOD_TEMPLATE -warp $SUB2TEMP_WARP -interp nearest -nthreads 2 -force $MDt_IMAGE_REG"
    CMD_MRTRANSFORM_FW="mrtransform $FW_IMAGE -template $FOD_TEMPLATE -warp $SUB2TEMP_WARP -interp nearest -nthreads 2 -force $FW_IMAGE_REG"

   
    # Execution

    $parallel "$singularity_mrtrix3 $CMD_MRCONVERT_FD" ::: ${input_subject_array[@]}
    $parallel "$singularity_mrtrix3 $CMD_MRCONVERT_LOG_FC" ::: ${input_subject_array[@]}
    $parallel "$singularity_mrtrix3 $CMD_MRCONVERT_FDC" ::: ${input_subject_array[@]}

    $parallel "$singularity_mrtrix3 $CMD_MRTRANSFORM_FA" ::: ${input_subject_array[@]}
    $parallel "$singularity_mrtrix3 $CMD_MRTRANSFORM_FAt" ::: ${input_subject_array[@]}
    $parallel "$singularity_mrtrix3 $CMD_MRTRANSFORM_AD" ::: ${input_subject_array[@]}
    $parallel "$singularity_mrtrix3 $CMD_MRTRANSFORM_ADt" ::: ${input_subject_array[@]}
    $parallel "$singularity_mrtrix3 $CMD_MRTRANSFORM_RD" ::: ${input_subject_array[@]}
    $parallel "$singularity_mrtrix3 $CMD_MRTRANSFORM_RDt" ::: ${input_subject_array[@]}
    $parallel "$singularity_mrtrix3 $CMD_MRTRANSFORM_MD" ::: ${input_subject_array[@]}
    $parallel "$singularity_mrtrix3 $CMD_MRTRANSFORM_MDt" ::: ${input_subject_array[@]}
    $parallel "$singularity_mrtrix3 $CMD_MRTRANSFORM_FW" ::: ${input_subject_array[@]}
   
    # Define TBSS command
    #####################

    CMD_TBSS="
        tbss_all \
            --caselist $CASELIST \
            --input $IMAGELIST \
            --modality FA,FAt,AD,ADt,RD,RDt,MD,MDt,FW,FD,FC,FDC \
            --template $FA_TEMPLATE \
            --outDir $TBSS_DIR \
            --force \
            --ncpu 4"

fi


####################################################################################################
# Check input and create imagelist.csv and caselist.csv for tbss in sourcedata of output directory #
####################################################################################################
    
[ -d $TBSS_DIR/sourcedata ] || mkdir -p $TBSS_DIR/sourcedata
echo "TBSS_DIR = $TBSS_DIR"

# Remove old imagelist.csv and caselist.csv; other previous output will be overwritten by --force flag of tbss_all

# if [ -f $IMAGELIST ]; then
#     rm $IMAGELIST
# fi

# if [ -f $CASELIST ]; then
#     rm $CASELIST
# fi

# Define input files
####################

for sub in ${input_subject_array[@]}; do

    
    if [ $TBSS_PIPELINE == "fixel" ]; then
        
        FA_IMAGE_REG=$TBSS_DIR/dti2fod/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-fodtemplate_desc-DTINoNeg_FA.nii.gz
        FAt_IMAGE_REG=$TBSS_DIR/dti2fod/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-fodtemplate_desc-FWcorrected_FA.nii.gz
        AD_IMAGE_REG=$TBSS_DIR/dti2fod/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-fodtemplate_desc-DTINoNeg_L1.nii.gz
        ADt_IMAGE_REG=$TBSS_DIR/dti2fod/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-fodtemplate_desc-FWcorrected_L1.nii.gz
        RD_IMAGE_REG=$TBSS_DIR/dti2fod/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-fodtemplate_desc-DTINoNeg_RD.nii.gz
        RDt_IMAGE_REG=$TBSS_DIR/dti2fod/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-fodtemplate_desc-FWcorrected_RD.nii.gz
        MD_IMAGE_REG=$TBSS_DIR/dti2fod/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-fodtemplate_desc-DTINoNeg_MD.nii.gz
        MDt_IMAGE_REG=$TBSS_DIR/dti2fod/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-fodtemplate_desc-FWcorrected_MD.nii.gz
        FW_IMAGE_REG=$TBSS_DIR/dti2fod/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-fodtempalte_FW.nii.gz
        FD_IMAGE_REG=$TBSS_DIR/dti2fod/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-fodtempalte_FD.nii.gz
        LOG_FC_IMAGE_REG=$TBSS_DIR/dti2fod/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-fodtempalte_logFC.nii.gz
        FDC_IMAGE_REG=$TBSS_DIR/dti2fod/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-fodtempalte_FDC.nii.gz

        # Check if all input files are present
        
        files_complete=y
        for img in $FA_IMAGE_REG $FAt_IMAGE_REG $AD_IMAGE_REG $ADt_IMAGE_REG $RD_IMAGE $RDt_IMAGE $MD_IMAGE $MDt_IMAGE $FW_IMAGE $FD_IMAGE_REG $LOG_FC_IMAGE_REG $FDC_IMAGE_REG; do
            [ -f $img ] || files_complete=n
        done

        # Write $IMAGELIST and $CASELIST
        
        if [ $files_complete == y ];then
            echo $FA_IMAGE_REG,$FAt_IMAGE_REG,$AD_IMAGE_REG,$ADt_IMAGE_REG,$RD_IMAGE_REG,$RDt_IMAGE_REG,$MD_IMAGE_REG,$MDt_IMAGE_REG,$FW_IMAGE_REG,$FD_IMAGE_REG,$LOG_FC_IMAGE_REG,$FDC_IMAGE_REG >> $IMAGELIST;
            echo $sub >> $CASELIST
        fi

    else
        cp $DATA_DIR/freewater/$sub/ses-$SESSION/dwi/${sub}_ses-${SESSION}_space-T1w_desc-DTINoNeg_FA.nii.gz $SCRATCH_DIR/
        FA_IMAGE=$SCRATCH_DIR/${sub}_ses-${SESSION}_space-T1w_desc-DTINoNeg_FA.nii.gz
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
        for img in $FA_IMAGE $FAt_IMAGE $AD_IMAGE $ADt_IMAGE $RD_IMAGE $RDt_IMAGE $MD_IMAGE $MDt_IMAGE $FW_IMAGE; do
            [ -f $img ] || files_complete=n
        done

        # Write $IMAGELIST and $CASELIST
        
        if [ $files_complete == y ];then
            echo $FA_IMAGE,$FAt_IMAGE,$AD_IMAGE,$ADt_IMAGE,$RD_IMAGE,$RDt_IMAGE,$MD_IMAGE,$MDt_IMAGE,$FW_IMAGE >> $IMAGELIST;
            echo $sub >> $CASELIST
        fi
    fi

done

############
# Run TBSS #
############

singularity run --cleanenv --userns \
    -B . \
    -B $PROJ_DIR \
    -B $TMP_DIR:/tmp \
    -B $SCRATCH_DIR \
    $ENV_DIR/tbss_pnl-0.1.5 $CMD_TBSS