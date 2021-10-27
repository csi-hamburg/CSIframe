#!/bin/bash
# Set output directory
MIX=${BIASCORR}_${MASKINGGAME}

[ $MIX == y_y ] && OUT_DIR=data/${PIPELINE}/${ALGORITHM}_biascorr_masking/$1/ses-${SESSION}/anat/ 
[ $MIX == y_n ] && OUT_DIR=data/${PIPELINE}/${ALGORITHM}_biascorr/$1/ses-${SESSION}/anat/
[ $MIX == n_y ] && OUT_DIR=data/${PIPELINE}/${ALGORITHM}_masking/$1/ses-${SESSION}/anat/
[ $MIX == n_n ] && OUT_DIR=data/${PIPELINE}/${ALGORITHM}/$1/ses-${SESSION}/anat/ 

[ ! -d $OUT_DIR ] && mkdir -p $OUT_DIR

# SET VARIABLES FOR CONTAINER TO BE USED
FSL_VERSION=fsl-6.0.3
FREESURFER_VERSION=freesurfer-7.1.1
MRTRIX_VERSION=mrtrix3-3.0.2
###############################################################################################################################################################
FSL_CONTAINER=$ENV_DIR/$FSL_VERSION
FREESURFER_CONTAINER=$ENV_DIR/$FREESURFER_VERSION
MRTRIX_CONTAINER=$ENV_DIR/$MRTRIX_VERSION
ANTSRNET_CONTAINER=$ENV_DIR/antsrnet
###############################################################################################################################################################
singularity="singularity run --cleanenv --userns -B $PROJ_DIR -B $TMP_DIR/:/tmp"
###############################################################################################################################################################









###############################################################################################################################################################
##### STEP 1: THE ULTIMATE MASKING GAME - CREATE WM MASK FOR FILTERING OF SEGMENTATIONS
###############################################################################################################################################################
if [ $MASKINGGAME == y ]; then 

    # Define inputs
    ASEG_freesurfer=data/freesurfer/$1/mri/aseg.mgz
    TEMPLATE_native=data/freesurfer/$1/mri/rawavg.mgz
    T1_MASK=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-brain_mask.nii.gz

    # Define outputs
    ASEG_native=/tmp/${1}_ses-${SESSION}_space-T1_aseg.mgz
    ASEG_nii=/tmp/${1}_ses-${SESSION}_space-T1_aseg.nii.gz
    WM_right=/tmp/${1}_ses-${SESSION}_space-T1_hemi-R_desc-wm_mask.nii.gz 
    WM_left=/tmp/${1}_ses-${SESSION}_space-T1_hemi-L_desc-wm_mask.nii.gz 
    WMMASK_T1=/tmp/${1}_ses-${SESSION}_space-T1_desc-wm_mask.nii.gz 
    FREESURFER_WMH=/tmp/${1}_ses-${SESSION}_space-T1_desc-freesurferwmh_mask.nii.gz
    VENTRICLE_right=/tmp/${1}_ses-${SESSION}_space-T1_hemi-R_desc-ventricle_mask.nii.gz
    VENTRICLE_left=/tmp/${1}_ses-${SESSION}_space-T1_hemi-L_desc-ventricle_mask.nii.gz
    VENTRICLEMASK_T1=/tmp/${1}_ses-${SESSION}_space-T1_desc-ventricle_mask.nii.gz
    VENTRICLEWMWMHMASK=/tmp/${1}_ses-${SESSION}_space-T1_desc-ventriclewmwmh_mask.nii.gz
    RIBBON_right=/tmp/${1}_ses-${SESSION}_space-T1_hemi-R_desc-ribbon_mask.nii.gz 
    RIBBON_left=/tmp/${1}_ses-${SESSION}_space-T1_hemi-L_desc-ribbon_mask.nii.gz 
    RIBBONMASK=/tmp/${1}_ses-${SESSION}_space-T1_desc-ribbon_mask.nii.gz
    BRAINWITHOUTRIBBON_MASK=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-brainwithoutribbon_mask.nii.gz

    # Define commands
    CMD_prepare_wmmask="mri_label2vol --seg $ASEG_freesurfer --temp $TEMPLATE_native --o $ASEG_native --regheader $ASEG_freesurfer"
    CMD_convert_wmmask="mri_convert $ASEG_native $ASEG_nii"
    CMD_create_wmmask_right="fslmaths $ASEG_nii -thr 41 -uthr 41 -bin $WM_right"
    CMD_create_wmmask_left="fslmaths $ASEG_nii -thr 2 -uthr 2 -bin $WM_left"
    CMD_merge_wmmasks="fslmaths $WM_right -add $WM_left -bin $WMMASK_T1"
    CMD_create_freesurferwmh_mask="fslmaths $ASEG_nii -thr 77 -uthr 77 -bin $FREESURFER_WMH"
    CMD_create_ventriclemask_right="fslmaths $ASEG_nii -thr 43 -uthr 43 -bin $VENTRICLE_right"
    CMD_create_ventriclemask_left="fslmaths $ASEG_nii -thr 4 -uthr 4 -bin $VENTRICLE_left"
    CMD_merge_ventriclemasks="fslmaths $VENTRICLE_right -add $VENTRICLE_left -bin $VENTRICLEMASK_T1"
    CMD_create_ventriclewmmask="fslmaths $VENTRICLEMASK_T1 -add $WMMASK_T1 -add $FREESURFER_WMH -bin $VENTRICLEWMWMHMASK"
    CMD_create_ribbonmask_right="fslmaths $ASEG_nii -thr 42 -uthr 42 -bin $RIBBON_right"
    CMD_create_ribbonmask_left="fslmaths $ASEG_nii -thr 3 -uthr 3 -bin $RIBBON_left"
    CMD_merge_ribbonmasks="fslmaths $RIBBON_right -add $RIBBON_left -bin $RIBBONMASK"
    CMD_threshold_ribbonmask="fslmaths $RIBBONMASK -bin -dilM $RIBBONMASK"
    CMD_threshold_ribbonmaskagain="fslmaths $RIBBONMASK -bin -dilM $RIBBONMASK"
    CMD_new_brainmask="fslmaths $T1_MASK -sub $RIBBONMASK $BRAINWITHOUTRIBBON_MASK"
    CMD_final_mask="fslmaths $BRAINWITHOUTRIBBON_MASK -mul $VENTRICLEWMWMHMASK $BRAINWITHOUTRIBBON_MASK"

    ( cp -ruvfL $ENV_DIR/freesurfer_license.txt $FREESURFER_CONTAINER/opt/$FREESURFER_VERSION/.license )

    # Execute 
    $singularity $FREESURFER_CONTAINER /bin/bash -c "$CMD_prepare_wmmask; $CMD_convert_wmmask"

    $singularity $FSL_CONTAINER /bin/bash -c "$CMD_create_wmmask_right; $CMD_create_wmmask_left; $CMD_merge_wmmasks; $CMD_create_freesurferwmh_mask; $CMD_create_ventriclemask_right; $CMD_create_ventriclemask_left; $CMD_merge_ventriclemasks; $CMD_create_ventriclewmmask; $CMD_create_ribbonmask_right; $CMD_create_ribbonmask_left; $CMD_merge_ribbonmasks; $CMD_threshold_ribbonmask; $CMD_threshold_ribbonmaskagain; $CMD_new_brainmask; $CMD_final_mask"

fi 
###############################################################################################################################################################















###############################################################################################################################################################
##### STEP 2: PREPARE IMAGES FOR SEGMENTATION 
###############################################################################################################################################################

if [ $ALGORITHM == "antsrnet" ]; then

    # Define inputs
    FLAIR=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
    T1=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz

    # Define outputs
    T1_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
    T1_TO_FLAIR_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-T1w_to-FLAIR_mode-image_xfm.txt
    
    # Define commands
    CMD_T1_TO_FLAIR="flirt -in $T1 -ref $FLAIR -omat $T1_TO_FLAIR_WARP -out $T1_IN_FLAIR -v"

    # Execute
    $singularity $FSL_CONTAINER /bin/bash -c " $CMD_T1_TO_FLAIR"

    if [ $BIASCORR == y ]; then

        # Define additional inputs
        T1_MASK=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-brain_mask.nii.gz

        # Define additional outputs
        T1_MASK_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brain_mask.nii.gz
        FLAIR_BIASCORR=$OUT_DIR/${1}_ses-${SESSION}_desc-biascorr_FLAIR.nii.gz
        
        # Define additional commands
        CMD_T1_MASK_TO_FLAIR="flirt -in $T1_MASK -ref $FLAIR -init $T1_TO_FLAIR_WARP -out $T1_MASK_IN_FLAIR -v -applyxfm" 
        CMD_MASK_THRESH="mrthreshold $T1_MASK_IN_FLAIR -abs 0.95 $T1_MASK_IN_FLAIR --force"
        CMD_BIASCORR_FLAIR="N4BiasFieldCorrection -d 3 -i $FLAIR -x $T1_MASK_IN_FLAIR -o $FLAIR_BIASCORR --verbose 1" 

        # Execute
        $singularity $FSL_CONTAINER /bin/bash -c "$CMD_T1_MASK_TO_FLAIR"

        $singularity $MRTRIX_CONTAINER /bin/bash -c "$CMD_MASK_THRESH; $CMD_BIASCORR_FLAIR"

    fi

###############################################################################################################################################################

elif [ $ALGORITHM == "bianca" ]; then

    # Define inputs
    T1=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
    T1_MASK=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-brain_mask.nii.gz
    FLAIR=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
    MNI_TEMPLATE=/opt/$FSL_VERSION/data/standard/MNI152_T1_1mm_brain.nii.gz 

    # Define outputs
    T1_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
    T1_TO_FLAIR_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-T1w_to-FLAIR_mode-image_xfm.txt
    FLAIR_TO_MNI_WARP=$OUT_DIR/${1}_ses-${SESSION}_from_FLAIR_to-MNI_mode-image_xfm.txt
    FLAIR_IN_MNI=$OUT_DIR/${1}_ses-${SESSION}_space-MNI_FLAIR.nii.gz
    T1_MASK_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-brain_mask.nii.gz

    # Define commands
    CMD_T1_TO_FLAIR="flirt -in $T1 -ref $FLAIR -omat $T1_TO_FLAIR_WARP -out $T1_IN_FLAIR -v"
    CMD_flirt="flirt -in $FLAIR -ref $MNI_TEMPLATE -omat $FLAIR_TO_MNI_WARP -out $FLAIR_IN_MNI -v "
    CMD_T1_MASK_TO_FLAIR="flirt -in $T1_MASK -ref $FLAIR -init $T1_TO_FLAIR_WARP -out $T1_MASK_IN_FLAIR -v -applyxfm"
    CMD_MASK_THRESH="mrthreshold $T1_MASK_IN_FLAIR -abs 0.95 $T1_MASK_IN_FLAIR --force"
   
    # Execute 
    $singularity $FSL_CONTAINER /bin/bash -c "$CMD_T1_TO_FLAIR; $CMD_flirt; $CMD_T1_MASK_TO_FLAIR"
    
    $singularity $MRTRIX_CONTAINER /bin/bash -c "$CMD_MASK_THRESH"

    if [ $BIASCORR == y ]; then

        # Define additional outputs
        FLAIR_BIASCORR=$OUT_DIR/${1}_ses-${SESSION}_desc-biascorr_FLAIR.nii.gz

        # Define additional commands
        CMD_BIASCORR_FLAIR="N4BiasFieldCorrection -d 3 -i $FLAIR -x $T1_MASK_IN_FLAIR -o $FLAIR_BIASCORR --verbose 1"

        # Execute
        $singularity $MRTRIX_CONTAINER /bin/bash -c "$CMD_BIASCORR_FLAIR"

    fi 

    # Define inputs 
    [ $BIASCORR == n ] && FLAIR=$FLAIR
    [ $BIASCORR == y ] && FLAIR=$FLAIR_BIASCORR

    # Define outputs
    FLAIR_BRAIN=$OUT_DIR/${1}_ses-${SESSION}_desc-brain_FLAIR.nii.gz

    # Define commands
    CMD_MASKING_FLAIR="mrcalc $T1_MASK_IN_FLAIR $FLAIR -mult $FLAIR_BRAIN --force"

    # Execute
    $singularity $MRTRIX_CONTAINER /bin/bash -c "$CMD_MASKING_FLAIR"

###############################################################################################################################################################

elif [ $ALGORITHM == "lga" ]; then

    # Define inputs
    T1=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
    FLAIR=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz

    # Define outputs
    T1_nii=/work/fatx405/projects/CSI_TEST/$OUT_DIR/${1}_ses-${SESSION}_desc-preproc_T1w.nii
    FLAIR_nii=/work/fatx405/projects/CSI_TEST/$OUT_DIR/${1}_ses-${SESSION}_FLAIR.nii

    # Define commands
    CMD_convert_T1="mri_convert $T1 $T1_nii"
    CMD_convert_FLAIR="mri_convert $FLAIR $FLAIR_nii"

    # Execute
    $singularity $FREESURFER_CONTAINER /bin/bash -c "$CMD_convert_T1; $CMD_convert_FLAIR"

###############################################################################################################################################################

elif [ $ALGORITHM == "lpa" ]; then

    # Define inputs
    T1=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
    FLAIR=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz

    # Define outputs
    T1_nii=/work/fatx405/projects/CSI_TEST/$OUT_DIR/${1}_ses-${SESSION}_desc-preproc_T1w.nii
    FLAIR_nii=/work/fatx405/projects/CSI_TEST/$OUT_DIR/${1}_ses-${SESSION}_FLAIR.nii

    # Define commands
    CMD_convert_T1="mri_convert $T1 $T1_nii"
    CMD_convert_FLAIR="mri_convert $FLAIR $FLAIR_nii"

    # Execute
    $singularity $FREESURFER_CONTAINER /bin/bash -c "$CMD_convert_T1; $CMD_convert_FLAIR"

###############################################################################################################################################################

# reminder: no bias correction for samseg

elif [ $ALGORITHM == "samseg" ]; then

    # Define inputs
    FLAIR=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
    T1=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz

    # Define outputs
    T1_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
    T1_TO_FLAIR_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-T1w_to-FLAIR_mode-image_xfm.txt
    
    # Define commands
    CMD_T1_TO_FLAIR="flirt -in $T1 -ref $FLAIR -omat $T1_TO_FLAIR_WARP -out $T1_IN_FLAIR -v"

    # Execute
    $singularity $FSL_CONTAINER /bin/bash -c " $CMD_T1_TO_FLAIR"

###############################################################################################################################################################

fi























###############################################################################################################################################################
##### STEP 3: THE HEART OF THE SCRIPT - WMH SEGMENTATION 
###############################################################################################################################################################

if [ $ALGORITHM == "antsrnet" ]; then

    # Define inputs
    [ $BIASCORR == n ] && FLAIR=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
    [ $BIASCORR == y ] && FLAIR=$OUT_DIR/${1}_ses-${SESSION}_desc-biascorr_FLAIR.nii.gz
    T1_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
    export FLAIR
    export T1_BRAIN

    # Define outputs
    SEGMENTATION=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_mask.nii.gz
    export WMH_MASK
    SEGMENTATION_FILLED=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-lesionfilling_desc-wmh_mask.nii.gz

    # Define commands
    CMD_LESION_FILLING="LesionFilling 3 $T1_IN_FLAIR $SEGMENTATION $SEGMENTATION_FILLED"

    # Execute 
    $singularity $ANTSRNET_CONTAINER \
    Rscript -e "flair<-antsImageRead('$FLAIR'); t1<-antsImageRead('$T1_IN_FLAIR'); probabilitymask<-sysuMediaWmhSegmentation(flair, t1); antsImageWrite(probabilitymask, '$SEGMENTATION')"

    $singularity $MRTRIX_CONTAINER /bin/bash -c "$CMD_LESION_FILLING"

###############################################################################################################################################################

elif [ $ALGORITHM == "bianca" ]; then

    # the classifier is trained on N=100 HCHS subjects.
    # Input for the training was a brainextracted FLAIR, a T1 in FLAIR space, a mat file with the FLAIR-2-MNI warp and manually segmented WMH masks.
    # Manually segmented WMH masks contain overlap of segmentation of Marvin and Carola.
    # to have full documentation: the following command with the specified flags was executed for the training:
    # bianca --singlefile=masterfile.txt --labelfeaturenum=4 --brainmaskfeaturenum=1 --querysubjectnum=1 --trainingnums=all --featuresubset=1,2 --matfeaturenum=3 \
    # --trainingpts=2000 --nonlespts=10000 --selectpts=noborder -o sub-00012_bianca_output -v --saveclassifierdata=$SCRIPT_DIR/classifierdata

    # we now determined to choose a threshold of 0.75 for the bianca segmentation, which is in between the very strict threshold of 0.95 which we applied in the \
    # old analysis and the very generous threshold of 0.5 which looks a bit oversegmented but overall good.

    # Define inputs
    FLAIR_BRAIN=$OUT_DIR/${1}_ses-${SESSION}_desc-brain_FLAIR.nii.gz
    T1_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz
    FLAIR_TO_MNI_WARP=$OUT_DIR/${1}_ses-${SESSION}_from_FLAIR_to-MNI_mode-image_xfm.txt
    CLASSIFIER=data/wmh/bianca/sourcedata/classifierdata_hchs100

    # Define outputs
    MASTERFILE=$OUT_DIR/${1}_ses-${SESSION}_masterfile.txt
    echo "$FLAIR_BRAIN $T1_IN_FLAIR $FLAIR_TO_MNI_WARP" > $MASTERFILE
    SEGMENTATION=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_mask.nii.gz

    # Define commands
    CMD_run_bianca="bianca --singlefile=$MASTERFILE --brainmaskfeaturenum=1 --querysubjectnum=1 --featuresubset=1,2 --matfeaturenum=3 -o $SEGMENTATION -v --loadclassifierdata=$CLASSIFIER"

    # Execute
    $singularity $FSL_CONTAINER /bin/bash -c "$CMD_run_bianca"

###############################################################################################################################################################

elif [ $ALGORITHM == "lga" ]; then

    module load matlab/2019b

    # ps_LST_lga Lesion segmentation by a lesion growth algorithm (LGA)
    # Part of the LST toolbox, www.statistical-modelling.de/lst.html
    # 
    # ps_LST_lga Lesion segmentation by the LGA requires a T1 and a FLAIR 
    # image. Furthermore, the user has to specify an initial threshold
    # (kappa). See Schmidt et al. (2012) for details.
    # 
    # This routine produces lesion probability maps (ples...), coregistered
    # bias corrected versions of the FLAIR inputs, a .mat-file with
    # information about the segmentation that is needed for a re-run of the 
    # algorithm, and a HTML report along with a folder if this option has 
    # been chosen desired.
    # 
    # ps_LST_lga asks the user for the input images (T1 and FLAIR) and sets
    # kappa to its default value (0.3). MRF parameter is set to 1 and, number 
    # of maximum iterations are 50 and a HTML report is produced.
    # 
    # ps_LST_lga(Vt1, Vf2, kappa, phi, maxiter, html) performs lesion 
    # segmentation for the image volumes given in Vt1 and Vf2. Both must be 
    # characters like a call from from spm_select. Initial thresholds are 
    # colectedInitial in kappa, MRF parameter in phi, number of maximum 
    # iterations in maxiter and a dummy for the HTML report in html. If the
    # last four arguments are missing they are replaced by their default
    # values, see above.
    # 
    # ps_LST_lga(job) Same as above but with job being a harvested job data
    # structure (see matlabbatch help).
    #
    # References
    # P. Schmidt, Gaser C., Arsic M., Buck D., F�rschler A., Berthele A., 
    # Hoshi M., Ilg R., Schmid V.J., Zimmer C., Hemmer B., and M�hlau M. An 
    # automated tool for detec- tion of FLAIR-hyperintense white-matter 
    # lesions in Multiple Sclerosis. NeuroImage, 59:3774?3783, 2012.
    # set an initial threshold for WMH segmentation

    # if not specified differently, following options of LGA algoritm are set: a MRT parameter in phi (default 1), the number of maximum iterations in maxiter (default 50) and HTML report (default yes).
    # ps_LST_lga(Vt1, Vf2, kappa, phi, maxiter, html)

    # Outputs generated:
        # lesion probability maps (ples...) in T1
        # coregistered bias corrected version of the FLAIR inputs
        # a .mat-file with information about the segmentation that is needed for a re-run of the algorithm 
        # a HTML report along with a folder if this option has been chosen desired
    
    for kappa in 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5; do

        # Execute 
        matlab -nosplash -nodesktop -nojvm -batch \
        "addpath(genpath('$ENV_DIR/spm12')); ps_LST_lga('$T1_nii', '$FLAIR_nii', $kappa); quit"

    done

###############################################################################################################################################################

elif [ $ALGORITHM == "lpa" ]; then

    module load matlab/2019b

    # ps_LST_lpa   Lesion segmentation by a lesion predicialgorithm (LGA)
    # Part of the LST toolbox, www.statistical-modelling.de/lst.html
    #
    # ps_LST_lpa Lesion segmentation by the LPA requires a FLAIR image only. 
    # However, the user is free to choose an additional image that serves as 
    # a reference image during a coregistration step before the main lesion 
    # segmentation. This may be helpful if the dimension of the FLAIR image 
    # is low or if the goal of the lesion segmentation is to fill lesions in 
    # T1 images. Beside that no additional parameters need to be set. No
    # other parameters need to be set by the user.
    #
    # This routine produces lesion probability maps (ples...), [coregistered]
    # bias corrected versions of the FLAIR inputs, a .mat-file with
    # information about the segmentation that is needed for a re-run of the 
    # algorithm, and a HTML report along with a folder if this option has 
    # been chosen desired. See the documentation for details.
    #
    # ps_LST_lpa asks the user for the input images (FLAIR and optional
    # reference images). A HTML report is produced by default.
    #
    # ps_LST_lpa(Vf2, Vref, html) performs lesion 
    # segmentation for the FLAIR volumes given in Vf2 and reference volumes 
    # given in Vref. The letter can be left empty. If specified, both must be
    # characters like a call from from spm_select. The last argument is  a 
    # dummy for the HTML reports. If the last argument ismissing it is
    # replaced by its default value, see above.
    #
    # ps_LST_lpa(job) Same as above but with job being a harvested job data
    # structure (see matlabbatch help).

    # Outputs generated:
        # lesion probability maps (ples...) in FLAIR and - if given - in reference space (T1)
        # coregistered bias corrected version of the FLAIR inputs
        # a .mat-file with information about the segmentation that is needed for a re-run of the algorithm 
        # a HTML report along with a folder if this option has been chosen desired

    # Execute 
    matlab -nosplash -nodesktop -nojvm -batch \
    "addpath(genpath('$ENV_DIR/spm12')); ps_LST_lpa('$FLAIR_nii', '$T1_nii'); quit"

###############################################################################################################################################################
# reminder: no bias-correction for samseg

elif [ $ALGORITHM == "samseg" ]; then

    # Define inputs
    FLAIR=data/raw_bids/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_FLAIR.nii.gz
    T1_IN_FLAIR=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-preproc_T1w.nii.gz

    # Define commands
    CMD_SAMSEG="run_samseg --input $FLAIR $T1_IN_FLAIR --output $OUT_DIR"

    # Execute
    $singularity $FREESURFER_CONTAINER /bin/bash -c "$CMD_SAMSEG"

###############################################################################################################################################################

fi
















###############################################################################################################################################################
##### STEP 3: POST-PROCESSING & MASKING GAME
###############################################################################################################################################################

if [ $ALGORITHM == "antsrnet" ]; then

    # Define inputs
    WMH_MASK_FILLED=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-lesionfilling_desc-wmh_mask.nii.gz
    T1=data/fmriprep/$1/ses-${SESSION}/anat/${1}_ses-${SESSION}_desc-preproc_T1w.nii.gz
    FLAIR_TO_T1_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-FLAIR_to-T1_mode-image_xfm.txt
    T1_TO_FLAIR_WARP=$OUT_DIR/${1}_ses-${SESSION}_from-T1w_to-FLAIR_mode-image_xfm.txt

    # Define outputs
    WMH_MASK_T1=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-lesionfilling_desc-wmh_mask.nii.gz

    # Define commands
    CMD_INVERT_WARP="convert_xfm -omat $FLAIR_TO_T1_WARP -inverse $T1_TO_FLAIR_WARP"
    CMD_WMH_MASK_TO_T1="flirt -in $WMH_MASK_FILLED -ref $T1 -init $FLAIR_TO_T1_WARP -out $WMH_MASK_T1 -v -applyxfm"
    
    # Execute
    $singularity $FSL_CONTAINER /bin/bash -c "$CMD_INVERT_WARP; $CMD_WMH_MASK_TO_T1"

    if [ $MASKINGGAME == y ]; then 

        # Define additional inputs
        BRAINWITHOUTRIBBON_MASK=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-brainwithoutribbon_mask.nii.gz

        # Define additional outputs 
        WMH_FILTERED=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-filtered_desc-wmh_mask.nii.gz

        # Define additional commands
        CMD_overlay_wmmask="fslmaths $WMH_MASK_T1 -mul $BRAINWITHOUTRIBBON_MASK $WMH_FILTERED"

        # Execute
        $singularity $FSL_CONTAINER /bin/bash -c "$CMD_overlay_wmmask"

    fi 

###############################################################################################################################################################

elif [ $ALGORITHM == "bianca" ]; then

    if [ $MASKINGGAME == y ]; then 

        # Define additional inputs
        BRAINWITHOUTRIBBON_MASK=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-brainwithoutribbon_mask.nii.gz

        # Define additional outputs
        SEGMENTATION1=$OUT_DIR/${1}_ses-${SESSION}_space-FLAIR_desc-wmh_mask1.nii.gz

        # Define additional commands
        CMD_overlay_wmmask="fslmaths $SEGMENTATION -mul $BRAINWITHOUTRIBBON_MASK $SEGMENTATION1"

        # Execute
        $singularity $FSL_CONTAINER /bin/bahs -c "$CMD_overlay_wmmask"

    fi

###############################################################################################################################################################

elif [ $ALGORITHM == "lga" ]; then

    if [ $MASKINGGAME == y ]; then

        for kappa in 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.45 0.5; do

            # Define inputs
            SEGMENTATION=$OUT_DIR/ples_${ALGORITHM}_${kappa}_rm${1}_ses-${SESSION}_FLAIR.nii
            BRAINWITHOUTRIBBON_MASK=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-brainwithoutribbon_mask.nii.gz

            # Define outputs
            SEGMENTATION_filtered=$OUT_DIR/ples_${ALGORITHM}_${kappa}_rm${1}_ses-${SESSION}_desc-filtered_FLAIR.nii

            # Define commands
            CMD_filter_segmentation="fslmaths $SEGMENTATION -mul $BRAINWITHOUTRIBBON_MASK -bin $SEGMENTATION_filtered"

            # Execute
            $singularity $FSL_CONTAINER /bin/bash -c "$CMD_filter_segmentation"

        done

    fi

###############################################################################################################################################################

elif [ $ALGORITHM == "lpa" ]; then

    if [ $MASKINGGAME == y ]; then

        # Define inputs
        SEGMENTATION=$OUT_DIR/ples_${ALGORITHM}_mr${1}_ses-${SESSION}_FLAIR.nii
        BRAINWITHOUTRIBBON_MASK=$OUT_DIR/${1}_ses-${SESSION}_space-T1_desc-brainwithoutribbon_mask.nii.gz

        # Define outputs
        SEGMENTATION_filtered=$OUT_DIR/ples_${ALGORITHM}_mr${1}_ses-${SESSION}_desc-filtered_FLAIR.nii

        # Define commands
        CMD_filter_segmentation="fslmaths $SEGMENTATION -mul $BRAINWITHOUTRIBBON_MASK -bin $SEGMENTATION_filtered"

        # Execute
        $singularity $FSL_CONTAINER /bin/bash -c "$CMD_filter_segmentation"

    fi

###############################################################################################################################################################

elif [ $ALGORITHM == "samseg" ]; then

   if [ $MASKINGGAME == y ]; then

        echo "how does the output of samseg look like?"

   fi

###############################################################################################################################################################

fi