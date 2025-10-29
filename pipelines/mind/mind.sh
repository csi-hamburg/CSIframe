#!/usr/bin/env bash

###################################################################################################################
# Morphometric INverse Divergence (MIND) Networks                                                                 #
# Cortical similarity network computation with via MIND (https://github.com/isebenius/MIND)                       #
#                                                                                                                 #
# Pipeline specific dependencies:                                                                                 #
#   [pipelines which need to be run first]                                                                        #
#       - freesurfer_reconall                                                                                     #
#   [container]                                                                                                   #
#       - mind_env.sif                                                                                            #
#                                                                                                                 #
# Author: David Emskötter (demsi-csi)                                                                             #
###################################################################################################################

# Get verbose outputs
set -x

# Define subject specific temporary directory on $SCRATCH_DIR
export TMP_DIR=$SCRATCH_DIR/$1/tmp/;   [ ! -d $TMP_DIR ] && mkdir -p $TMP_DIR
TMP_IN=$TMP_DIR/input;                 [ ! -d $TMP_IN ] && mkdir -p $TMP_IN
TMP_OUT=$TMP_DIR/output;               [ ! -d $TMP_OUT ] && mkdir -p $TMP_OUT

####################################################################################################################

# Pipeline-specific environment
##################################

# Apptainer mind-container
container_mind=mind_env5.sif
apptainer_mind="apptainer exec --cleanenv --no-home --userns \
    -B $PROJ_DIR \
    -B $(readlink -f $ENV_DIR) \
    -B $TMP_DIR/:/tmp \
    -B $TMP_IN:/tmp_in \
    -B $TMP_OUT:/tmp_out \
    $ENV_DIR/$container_mind" 

####################################################################################################################

# Define pipeline directory 
export MIND_PIPELINE_DIR="$PIPELINE_DIR/"

# Define freesurfer directory
export SURFER_DATA_DIR="$DATA_DIR/freesurfer"

# Define mind input directory
export MIND_INPUT_DIR="$TMP_IN/$1"
[ ! -d "$MIND_INPUT_DIR" ] && mkdir -p "$MIND_INPUT_DIR/surf" "$MIND_INPUT_DIR/label" && echo "Created: $MIND_INPUT_DIR" 

# Define mind output directory
export MIND_OUTPUT_DIR="$TMP_OUT/$1/ses-$SESSION/${PARCELLATION}"
[ ! -d "$MIND_OUTPUT_DIR" ] && mkdir -p "$MIND_OUTPUT_DIR" && echo "Created: $MIND_OUTPUT_DIR"

# Define mind data directory
export MIND_DATA_DIR="$DATA_DIR/mind/$1/ses-$SESSION/${PARCELLATION}"
[ ! -d "$MIND_DATA_DIR" ] && mkdir -p "$MIND_DATA_DIR" && echo "Created: $MIND_DATA_DIR"

####################################################################################################################

# Get surf data and annotation files according to freesurfer
cp -rf "$SURFER_DATA_DIR/$1/surf/." "$MIND_INPUT_DIR/surf/"
cp -rf "$SURFER_DATA_DIR/$1/label/." "$MIND_INPUT_DIR/label/"

####################################################################################################################

# Parcellation
if [[ "$PARCELLATION" == Schaefer2018_* ]]; then

    # Get fsaverage (schaefer annotation files)
    if [[ ! -d "$TMP_IN/fsaverage" ]]; then
        cp -rf "$SURFER_DATA_DIR/fsaverage" "$TMP_IN/"
        cp -rn "$MIND_PIPELINE_DIR/fsaverage/surf/." "$TMP_IN/fsaverage/surf/"
        cp -rn "$MIND_PIPELINE_DIR/fsaverage/label/." "$TMP_IN/fsaverage/label/"
        echo "Copied fsaverage (schaefer annotation files) to $TMP_IN/fsaverage"
    fi

    # Apptainer freesurfer-container
    export FREESURFER_LICENSE="$ENV_DIR/freesurfer_license.txt"
    container_freesurfer=freesurfer-7.4.1.sif
    apptainer_freesurfer="apptainer run --cleanenv --userns \
        -B $PROJ_DIR \
        -B $(readlink -f $ENV_DIR) \
        -B $TMP_DIR/:/tmp \
        -B $TMP_IN:/tmp_in \
        -B $TMP_OUT:/tmp_out \
        -B $FREESURFER_LICENSE:/opt/freesurfer/license.txt \
        $ENV_DIR/$container_freesurfer" 

    export APPTAINERENV_SUBJECTS_DIR=/tmp_in
    export APPTAINERENV_FS_LICENSE=/opt/freesurfer/license.txt
    export SUBJECTS_DIR=/usr/local/freesurfer/subjects

    # mri_surf2surf
    srcsubject="fsaverage"
    trgsubject="$1"

    echo "Projecting ${PARCELLATION} from $srcsubject to $trgsubject ..."

    sval_lh="/tmp_in/${srcsubject}/label/lh.${PARCELLATION}.annot"
    tval_lh="/tmp_in/${trgsubject}/label/lh.${PARCELLATION}.annot"
    sval_rh="/tmp_in/${srcsubject}/label/rh.${PARCELLATION}.annot"
    tval_rh="/tmp_in/${trgsubject}/label/rh.${PARCELLATION}.annot"

    $apptainer_freesurfer mri_surf2surf \
        --hemi lh \
        --srcsubject "${srcsubject}" \
        --trgsubject "${trgsubject}" \
        --sval-annot "${sval_lh}" \
        --tval "${tval_lh}" \
        && echo "lh done for $trgsubject"

    $apptainer_freesurfer mri_surf2surf \
        --hemi rh \
        --srcsubject "${srcsubject}" \
        --trgsubject "${trgsubject}" \
        --sval-annot "${sval_rh}" \
        --tval "${tval_rh}" \
        && echo "rh done for $trgsubject"

    # copy projected annot files to data directory
    cp -ruvf "$MIND_INPUT_DIR/label/lh.${PARCELLATION}.annot" "$MIND_DATA_DIR"/
    cp -ruvf "$MIND_INPUT_DIR/label/rh.${PARCELLATION}.annot" "$MIND_DATA_DIR"/

    # copy structural feature files to data directory
    for hemi in lh rh; do
        for feature in thickness curv volume sulc area; do
            cp -ruvf "$MIND_INPUT_DIR/surf/${hemi}.${feature}" "$MIND_DATA_DIR"/
        done
    done

elif [[ "$PARCELLATION" == aparc ]]; then

    cp -ruvf "$MIND_INPUT_DIR/label/lh.aparc.annot" "$MIND_DATA_DIR"/
    cp -ruvf "$MIND_INPUT_DIR/label/rh.aparc.annot" "$MIND_DATA_DIR"/

    for hemi in lh rh; do
        for feature in thickness curv volume sulc area; do
            cp -ruvf "$MIND_INPUT_DIR/surf/${hemi}.${feature}" "$MIND_DATA_DIR"/
        done
    done

else 
    
    echo "Skipping due to PARCELLATION=$PARCELLATION"

fi

####################################################################################################################
# Troubleshooting: list input files
#echo "=== TMP_IN for $1 ==="
#ls -l $TMP_IN/$1/surf    # should list lh.orig, rh.orig, etc.
#ls -l $TMP_IN/$1/label   # should list both the DK/aparc AND Schaefer annot files
#ls -l $TMP_IN/fsaverage/surf  # should list sphere.reg, orig, etc.
#ls -l $TMP_IN/fsaverage/label # should list your Schaefer annot files again

####################################################################################################################
# PIPELINE EXECUTION

###################################################### 
####### Compute mind-networks: compute_mind.py #######
######################################################

$apptainer_mind python3 "$MIND_PIPELINE_DIR"compute_mind.py \
    --sub               "$1" \
    --session           "$SESSION" \
    --mind_pipeline_dir "$MIND_PIPELINE_DIR" \
    --surf_dir          /tmp_in/$1 \
    --features          CT MC Vol SD SA \
    --parcellation      "$PARCELLATION" \
    --mind_dir          /tmp_out/$1/ses-$SESSION/$PARCELLATION/ \

cp -ruvf "$MIND_OUTPUT_DIR/"* "$MIND_DATA_DIR"/

####################################################################################################################

###################################################### 
####### Compute graph-metrics: graphmetrics.py #######
######################################################

# Calculation and normalization of global graph metrics
if [[ "$GRAPH_METRICS" == y ]]; then

    # Get parcellation-specific mind-network-csv as input
    MIND_DATA_DIR="$DATA_DIR/mind/$1/ses-$SESSION/${PARCELLATION}"

    NETWORK_TO_NORMALIZE=$MIND_DATA_DIR/${1}_ses-${SESSION}_desc-${PARCELLATION}_mind_network.csv

    $apptainer_mind python3 "$MIND_PIPELINE_DIR"graphmetrics.py \
        --sub               "$1" \
        --session           "$SESSION" \
        --parcellation      "$PARCELLATION" \
        --mind_csv          "$NETWORK_TO_NORMALIZE" \
        --mind_data_dir     "$MIND_DATA_DIR" \

fi