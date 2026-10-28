#!/bin/bash

###################################################################################################################
# ELAN Lesion Mask Registration Pipeline
# Registers stroke lesion masks to FSL MNI152 space via anatomical images and templates
###################################################################################################################

# Set number of threads for ANTs
export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=${SLURM_CPUS_PER_TASK:-4}

# Define paths from environment variables set by submission script
BIDS_ROOT=${BIDS_ROOT:-"$BEEGFS/ELAN/data/raw_bids"}
OUTPUT_ROOT="${BIDS_ROOT}/derivatives/lesion_masks_mni"
LOGS_DIR="${OUTPUT_ROOT}/logs"
TEMPLATES_DIR="$DATA_DIR/templates/CSI_MNI_space"

# Create output directories
mkdir -p "$LOGS_DIR"

# Define container paths
ANTS_CONTAINER="${ENV_DIR}/ants-2.5.4.sif"
FSL_CONTAINER="${ENV_DIR}/fsl-6.0.7.13.sif"

# Check if containers exist
if [ ! -f "$ANTS_CONTAINER" ]; then
    echo "ERROR: ANTs container not found: $ANTS_CONTAINER"
    exit 1
fi

if [ ! -f "$FSL_CONTAINER" ]; then
    echo "ERROR: FSL container not found: $FSL_CONTAINER"
    exit 1
fi

# Tracking lists
LIST_PROCESSED="${LOGS_DIR}/processed_successfully.txt"
LIST_NO_ANAT="${LOGS_DIR}/missing_anatomical.txt"
LIST_NO_DWI="${LOGS_DIR}/missing_dwi.txt"
LIST_FAILED="${LOGS_DIR}/registration_failed.txt"
LIST_USING_T1W="${LOGS_DIR}/registered_via_t1w.txt"
LIST_USING_FLAIR="${LOGS_DIR}/registered_via_flair.txt"

# Create tracking files (append mode for parallel jobs)
touch "$LIST_PROCESSED"
touch "$LIST_NO_ANAT"
touch "$LIST_NO_DWI"
touch "$LIST_FAILED"
touch "$LIST_USING_T1W"
touch "$LIST_USING_FLAIR"

# Main log file for this batch
BATCH_LOG="${LOGS_DIR}/registration_batch_${SLURM_JOB_ID}.log"

################################################################################
# Helper Functions
################################################################################

log_message() {
    local message="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[${timestamp}] ${message}" | tee -a "$BATCH_LOG"
}

log_error() {
    local message="$1"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "[${timestamp}] ERROR: ${message}" | tee -a "$BATCH_LOG" >&2
}

# Extract BIDS entities from filename
extract_entity() {
    local filename="$1"
    local entity="$2"
    echo "$filename" | grep -oP "(?<=_)${entity}-[^_]+" | head -1
}

# Wrapper for ANTs commands
run_ants() {
    apptainer exec \
        -B ${BIDS_ROOT}:${BIDS_ROOT} \
        -B ${OUTPUT_ROOT}:${OUTPUT_ROOT} \
        -B ${TEMPLATES_DIR}:${TEMPLATES_DIR} \
        "$ANTS_CONTAINER" "$@"
}

# Wrapper for FSL commands (if needed)
run_fsl() {
    apptainer exec \
        -B ${BIDS_ROOT}:${BIDS_ROOT} \
        -B ${OUTPUT_ROOT}:${OUTPUT_ROOT} \
        -B ${TEMPLATES_DIR}:${TEMPLATES_DIR} \
        "$FSL_CONTAINER" "$@"
}

# Helper function for skull stripping
run_skull_strip() {
    local input_image="$1"
    local output_brain="$2"
    local log_file="$3"
    
    log_message "    Running BET skull stripping..."
    log_message "      Input:  $(basename $input_image)"
    log_message "      Output: $(basename $output_brain)"
    
    run_fsl bet "$input_image" "$output_brain" -m -v >> "$log_file" 2>&1
    
    if [[ $? -ne 0 ]]; then
        log_error "Skull stripping failed"
        return 1
    fi
    
    log_message "    Skull stripping complete"
    return 0
}

# Helper function for ANTs registration to template
# Uses aggressive multi-stage registration (Rigid + Affine + SyN)
run_ants_to_template() {
    local moving_image="$1"      # Brain-extracted image
    local template_image="$2"    # Template (should be brain-extracted)
    local output_prefix="$3"     # Transform prefix
    local output_warped="$4"     # Warped output image
    local log_file="$5"
    
    log_message "    Running ANTs registration..."
    log_message "      Moving:   $(basename $moving_image)"
    log_message "      Template: $(basename $template_image)"
    log_message "      Stages:   Rigid → Affine → SyN (deformable)"
    
    run_ants antsRegistration \
        --output [ ${output_prefix}, ${output_warped} ] \
        --collapse-output-transforms 0 \
        --dimensionality 3 \
        --initial-moving-transform [ ${template_image}, ${moving_image}, 1 ] \
        --initialize-transforms-per-stage 0 \
        --interpolation Linear \
        --transform Rigid[ 0.1 ] \
        --metric MI[ ${template_image}, ${moving_image}, 1, 32, Regular, 0.25 ] \
        --convergence [ 10000x11110x1110x100, 1e-08, 10 ] \
        --smoothing-sigmas 3.0x2.0x1.0x0.0vox \
        --shrink-factors 8x4x2x1 \
        --use-histogram-matching 1 \
        --transform Affine[ 0.1 ] \
        --metric MI[ ${template_image}, ${moving_image}, 1, 32, Regular, 0.25 ] \
        --convergence [ 10000x11110x1110x100, 1e-08, 10 ] \
        --smoothing-sigmas 3.0x2.0x1.0x0.0vox \
        --shrink-factors 8x4x2x1 \
        --use-histogram-matching 1 \
        --transform SyN[ 0.2, 3.0, 0.0 ] \
        --metric CC[ ${template_image}, ${moving_image}, 1, 4 ] \
        --convergence [ 100x50x30x20, 1e-08, 10 ] \
        --smoothing-sigmas 3.0x2.0x1.0x0.0vox \
        --shrink-factors 8x4x2x1 \
        --use-histogram-matching 1 \
        --winsorize-image-intensities [ 0.005, 0.995 ] \
        --write-composite-transform 1 \
        --verbose 1 >> "$log_file" 2>&1
    
    if [[ $? -ne 0 ]]; then
        log_error "ANTs registration failed"
        return 1
    fi
    
    log_message "    Registration complete"
    return 0
}

################################################################################
# Main Processing Loop
################################################################################

log_message "=== Starting ELAN lesion mask registration batch ==="
log_message "Job ID: ${SLURM_JOB_ID}"
log_message "CPUs per task: ${SLURM_CPUS_PER_TASK}"
log_message "BIDS root: $BIDS_ROOT"
log_message "Output root: $OUTPUT_ROOT"
log_message "Templates dir: $TEMPLATES_DIR"
log_message "ANTs container: $ANTS_CONTAINER"
log_message "FSL container: $FSL_CONTAINER"
log_message ""

# Receive lesion masks as arguments
lesion_masks=($@)
TOTAL=${#lesion_masks[@]}

log_message "Processing $TOTAL lesion masks in this batch"
log_message ""

# Counter for progress
n=0
start_time=$(date +%s)

for lesion_mask_path in "${lesion_masks[@]}"; do
    n=$((n + 1))
    
    # Check if file exists
    if [[ ! -f "$lesion_mask_path" ]]; then
        log_error "Lesion mask file not found: $lesion_mask_path"
        continue
    fi
    
    # Extract filename and components
    lesion_mask_file=$(basename "$lesion_mask_path")
    lesion_mask_dir=$(dirname "$lesion_mask_path")
    
    # Extract BIDS entities
    subject_id=$(echo "$lesion_mask_file" | grep -oP "sub-[^_]+")
    session_id=$(echo "$lesion_mask_file" | grep -oP "ses-[^_]+")
    run_entity=$(extract_entity "$lesion_mask_file" "run")
    run_id=$(echo "$run_entity" | cut -d'-' -f2)
    
    log_message "=================================================="
    log_message "Processing ($n/$TOTAL): $subject_id $session_id $run_entity"
    log_message "Lesion mask: $lesion_mask_file"
    
    # Define subject directories
    subject_dir="${BIDS_ROOT}/${subject_id}"
    session_dir="${subject_dir}/${session_id}"
    work_dir="${OUTPUT_ROOT}/${subject_id}/${session_id}"
    xfm_dir="${work_dir}/xfm"
    anat_dir="${work_dir}/anat"
    dwi_dir="${work_dir}/dwi"
    lesion_dir="${work_dir}/lesion"
    
    mkdir -p "$xfm_dir" "$anat_dir" "$dwi_dir" "$lesion_dir"
    
    # ========================================================================
    # Step 1: Find corresponding DWI image
    # ========================================================================
    
    log_message "Step 1: Finding DWI image for ${run_entity}..."
    
    dwi_source_dir="${session_dir}/dwi"
    dwi_image=""
    dwi_type=""
    
    # Priority: adc > dwi > trace
    for dtype in adc dwi trace; do
        potential_dwi="${dwi_source_dir}/${subject_id}_${session_id}_${run_entity}_${dtype}.nii.gz"
        if [[ -f "$potential_dwi" ]]; then
            dwi_image="$potential_dwi"
            dwi_type="$dtype"
            log_message "  Found DWI: $(basename $dwi_image) (type: $dwi_type)"
            break
        fi
    done
    
    if [[ -z "$dwi_image" ]]; then
        log_error "No DWI image found for ${subject_id} ${session_id} ${run_entity}"
        echo "${subject_id}_${session_id}_${run_entity}" >> "$LIST_NO_DWI"
        continue
    fi
    
    # ========================================================================
    # Step 2: Find anatomical image (FLAIR preferred, else T1w)
    # ========================================================================
    
    log_message "Step 2: Finding anatomical image..."
    
    anat_source_dir="${session_dir}/anat"
    anat_image=""
    anat_type=""
    acq_tag=""
    
    # Try to find FLAIR first
    flair_images=($(ls ${anat_source_dir}/${subject_id}_${session_id}*_FLAIR.nii.gz 2>/dev/null || true))
    
    if [[ ${#flair_images[@]} -gt 0 ]]; then
        anat_image="${flair_images[0]}"
        anat_type="FLAIR"
        acq_entity=$(extract_entity "$(basename $anat_image)" "acq")
        acq_tag="${acq_entity:+_${acq_entity}}"
        log_message "  Found FLAIR: $(basename $anat_image)"
        echo "${subject_id}_${session_id}_${run_entity}" >> "$LIST_USING_FLAIR"
    else
        # Try T1w
        t1w_images=($(ls ${anat_source_dir}/${subject_id}_${session_id}*_T1w.nii.gz 2>/dev/null || true))
        
        if [[ ${#t1w_images[@]} -gt 0 ]]; then
            anat_image="${t1w_images[0]}"
            anat_type="T1w"
            acq_entity=$(extract_entity "$(basename $anat_image)" "acq")
            acq_tag="${acq_entity:+_${acq_entity}}"
            log_message "  Found T1w: $(basename $anat_image)"
            echo "${subject_id}_${session_id}_${run_entity}" >> "$LIST_USING_T1W"
        fi
    fi
    
    if [[ -z "$anat_image" ]]; then
        log_error "No anatomical image (FLAIR or T1w) found for ${subject_id} ${session_id}"
        echo "${subject_id}_${session_id}_${run_entity}" >> "$LIST_NO_ANAT"
        continue
    fi
    
    # ========================================================================
    # Step 3: Bias correction of anatomical
    # ========================================================================
    
    log_message "Step 3: Bias correction..."
    
    anat_biascorr="${anat_dir}/${subject_id}_${session_id}${acq_tag}_${anat_type}_desc-biascorr.nii.gz"
    
    if [[ ! -f "$anat_biascorr" ]]; then
        log_message "  Running N4BiasFieldCorrection..."
        run_ants N4BiasFieldCorrection \
            -d 3 \
            -i "$anat_image" \
            -o "$anat_biascorr" \
            --verbose 1 >> "$BATCH_LOG" 2>&1
        
        if [[ $? -ne 0 ]]; then
            log_error "Bias correction failed"
            echo "${subject_id}_${session_id}_${run_entity} Bias correction failed" >> "$LIST_FAILED"
            continue
        fi
    else
        log_message "  Bias corrected image already exists, skipping"
    fi
    
    # ========================================================================
    # Step 4: Register DWI to anatomical (linear)
    # ========================================================================
    
    log_message "Step 4: Registering DWI to anatomical ($anat_type)..."
    
    # Include run entity since DWI may differ between runs
    dwi_to_anat_prefix="${xfm_dir}/${subject_id}_${session_id}${acq_tag}_${run_entity}_from-${dwi_type}_to-${anat_type}_"
    dwi_in_anat="${dwi_dir}/${subject_id}_${session_id}${acq_tag}_${run_entity}_${dwi_type}_space-${anat_type}.nii.gz"
    
    # Check for composite transform file
    if [[ ! -f "${dwi_to_anat_prefix}Composite.h5" ]]; then
        log_message "  Running ANTs registration (Rigid + Affine)..."
        log_message "  Moving: $(basename $dwi_image)"
        log_message "  Fixed:  $(basename $anat_biascorr)"
        
        run_ants antsRegistration \
            --output [ ${dwi_to_anat_prefix}, ${dwi_in_anat} ] \
            --collapse-output-transforms 0 \
            --dimensionality 3 \
            --initial-moving-transform [ ${anat_biascorr}, ${dwi_image}, 1 ] \
            --initialize-transforms-per-stage 0 \
            --interpolation Linear \
            --transform Rigid[ 0.1 ] \
            --metric MI[ ${anat_biascorr}, ${dwi_image}, 1, 32, Regular, 0.25 ] \
            --convergence [ 1000x500x250x100, 1e-08, 10 ] \
            --smoothing-sigmas 3.0x2.0x1.0x0.0vox \
            --shrink-factors 8x4x2x1 \
            --use-histogram-matching 1 \
            --transform Affine[ 0.1 ] \
            --metric MI[ ${anat_biascorr}, ${dwi_image}, 1, 32, Regular, 0.25 ] \
            --convergence [ 1000x500x250x100, 1e-08, 10 ] \
            --smoothing-sigmas 3.0x2.0x1.0x0.0vox \
            --shrink-factors 8x4x2x1 \
            --use-histogram-matching 1 \
            --write-composite-transform 1 \
            --verbose 1 >> "$BATCH_LOG" 2>&1
        
        if [[ $? -ne 0 ]]; then
            log_error "DWI to anatomical registration failed"
            echo "${subject_id}_${session_id}_${run_entity} DWI to anatomical registration failed" >> "$LIST_FAILED"
            continue
        fi

        log_message "  Registration complete"

    else
        log_message "  DWI to anatomical transform already exists, skipping"
    fi

    # ========================================================================
    # Step 5: Register anatomical to template
    # ========================================================================
    
    log_message "Step 5: Registering anatomical to template..."
    
    # Determine template target and output paths based on anatomical type
    if [[ "$anat_type" == "FLAIR" ]]; then
        # Register FLAIR to MIPLab FLAIR template
        log_message "  Target: MIPLab FLAIR template (brain-extracted)"
        
        # Define paths (NO run entity - anatomical is same for all runs)
        anat_to_template_prefix="${xfm_dir}/${subject_id}_${session_id}${acq_tag}_from-FLAIR_to-MIPLabFLAIR_"
        anat_in_template="${anat_dir}/${subject_id}_${session_id}${acq_tag}_FLAIR_space-MIPLabFLAIR.nii.gz"
        anat_brain="${anat_dir}/${subject_id}_${session_id}${acq_tag}_FLAIR_desc-brain.nii.gz"
        anat_brain_mask="${anat_dir}/${subject_id}_${session_id}${acq_tag}_FLAIR_desc-brain_mask.nii.gz"
        
        # Use brain-extracted MIPLab template
        template_target="${TEMPLATES_DIR}/miplab-flair/miplab-flair_asym_brain.nii.gz"
        
        # Skull stripping
        if [[ ! -f "$anat_brain" ]]; then
            log_message "  Performing skull stripping on FLAIR..."
            run_skull_strip "$anat_biascorr" "$anat_brain" "$BATCH_LOG"
            
            if [[ $? -ne 0 ]]; then
                echo "${subject_id}_${session_id}_${run_entity} Skull stripping on FLAIR failed" >> "$LIST_FAILED"
                continue
            fi
        else
            log_message "  Skull-stripped brain already exists: $(basename $anat_brain)"
        fi
        
        # Check for composite transform (created with --write-composite-transform 1)
        if [[ ! -f "${anat_to_template_prefix}Composite.h5" ]]; then
            log_message "  Registering FLAIR to MIPLab template..."
            run_ants_to_template "$anat_brain" "$template_target" \
                "${anat_to_template_prefix}" "$anat_in_template" "$BATCH_LOG"
            
            if [[ $? -ne 0 ]]; then
                echo "${subject_id}_${session_id}_${run_entity} Registering FLAIR to MIPLab template failed" >> "$LIST_FAILED"
                continue
            fi
        else
            log_message "  FLAIR to MIPLab template transform already exists, skipping"
        fi
        
    else  # T1w
        # Register T1w to FSL MNI152 template
        log_message "  Target: FSL MNI152 T1 template (brain-extracted)"
        
        # Define paths (NO run entity - anatomical is same for all runs)
        anat_to_template_prefix="${xfm_dir}/${subject_id}_${session_id}${acq_tag}_from-T1w_to-MNI152_"
        anat_in_template="${anat_dir}/${subject_id}_${session_id}${acq_tag}_T1w_space-MNI152.nii.gz"
        anat_brain="${anat_dir}/${subject_id}_${session_id}${acq_tag}_T1w_desc-brain.nii.gz"
        anat_brain_mask="${anat_dir}/${subject_id}_${session_id}${acq_tag}_T1w_desc-brain_mask.nii.gz"
        
        # Use brain-extracted FSL MNI template
        template_target="${TEMPLATES_DIR}/FSL/MNI152_T1_1mm_brain.nii.gz"
        
        # Skull stripping
        if [[ ! -f "$anat_brain" ]]; then
            log_message "  Performing skull stripping on T1w..."
            run_skull_strip "$anat_biascorr" "$anat_brain" "$BATCH_LOG"
            
            if [[ $? -ne 0 ]]; then
                echo "${subject_id}_${session_id}_${run_entity} Performing skull stripping on T1w" >> "$LIST_FAILED"
                continue
            fi
        else
            log_message "  Skull-stripped brain already exists: $(basename $anat_brain)"
        fi
        
        # Check for composite transform (created with --write-composite-transform 1)
        if [[ ! -f "${anat_to_template_prefix}Composite.h5" ]]; then
            log_message "  Registering T1w to MNI152 template..."
            run_ants_to_template "$anat_brain" "$template_target" \
                "${anat_to_template_prefix}" "$anat_in_template" "$BATCH_LOG"
            
            if [[ $? -ne 0 ]]; then
                echo "${subject_id}_${session_id}_${run_entity} Registering T1w to MNI152 template" >> "$LIST_FAILED"
                continue
            fi
        else
            log_message "  T1w to MNI152 template transform already exists, skipping"
        fi
    fi
    
    log_message "  Step 5 complete: Anatomical registered to template"

    # ========================================================================
    # Step 6: Transform lesion mask to MNI space
    # ========================================================================
    
    log_message "Step 6: Transforming lesion mask to FSL MNI152 space..."

    # Define MNI reference template
    FSL_MNI_T1="${TEMPLATES_DIR}/FSL/MNI152_T1_1mm_brain.nii.gz"

    # Verify reference exists
    if [[ ! -f "$FSL_MNI_T1" ]]; then
        log_error "FSL MNI reference not found: $FSL_MNI_T1"
        echo "${subject_id}_${session_id}_${run_entity} FSL MNI reference not found" >> "$LIST_FAILED"
        continue
    fi
    
    # Define output path
    lesion_in_mni="${lesion_dir}/${subject_id}_${session_id}${acq_tag}_${run_entity}_dseg_space-MNI152.nii.gz"
    
    if [[ ! -f "$lesion_in_mni" ]]; then
        log_message "  Input lesion: $(basename $lesion_mask_path)"
        log_message "  Output: $(basename $lesion_in_mni)"
        
        # Build transform chain depending on anatomical type
        if [[ "$anat_type" == "FLAIR" ]]; then
            # Chain: DWI -> FLAIR -> MIPLab FLAIR -> FSL MNI152
            log_message "  Transform chain: DWI → FLAIR → MIPLab FLAIR → FSL MNI152"
            
            # Define MIPLab to MNI warp (note: named mni_to_miplab but inverted by ANTs)
            MIPLAB_TO_MNI_WARP="${TEMPLATES_DIR}/miplab-flair/mni_to_miplab_asym_warp.nii.gz"
            
            # Verify warp exists
            if [[ ! -f "$MIPLAB_TO_MNI_WARP" ]]; then
                log_error "MIPLab to MNI warp not found: $MIPLAB_TO_MNI_WARP"
                echo "${subject_id}_${session_id}_${run_entity} MIPLab to MNI warp not found" >> "$LIST_FAILED"
                continue
            fi
            
            # Note: transforms are applied in REVERSE order (last to first)
            # ANTs automatically inverts the warp direction as needed
            run_ants antsApplyTransforms \
                -d 3 \
                -i "$lesion_mask_path" \
                -r "$FSL_MNI_T1" \
                -t "$MIPLAB_TO_MNI_WARP" \
                -t "${anat_to_template_prefix}Composite.h5" \
                -t "${dwi_to_anat_prefix}Composite.h5" \
                -n GenericLabel \
                -o "$lesion_in_mni" \
                --verbose 1 >> "$BATCH_LOG" 2>&1
                
        else
            # Chain: DWI -> T1w -> FSL MNI152
            log_message "  Transform chain: DWI → T1w → FSL MNI152"
            
            # Note: transforms are applied in REVERSE order (last to first)
            run_ants antsApplyTransforms \
                -d 3 \
                -i "$lesion_mask_path" \
                -r "$FSL_MNI_T1" \
                -t "${anat_to_template_prefix}Composite.h5" \
                -t "${dwi_to_anat_prefix}Composite.h5" \
                -n GenericLabel \
                -o "$lesion_in_mni" \
                --verbose 1 >> "$BATCH_LOG" 2>&1
        fi
        
        if [[ $? -ne 0 ]]; then
            log_error "Transform application failed"
            echo "${subject_id}_${session_id}_${run_entity} Transform application failed" >> "$LIST_FAILED"
            continue
        fi
        
        log_message "  Lesion mask successfully transformed to MNI space"
    else
        log_message "  Lesion in MNI space already exists: $(basename $lesion_in_mni)"
    fi
    
    # ========================================================================
    # Success - add to processed list
    # ========================================================================
    
    echo "${subject_id}_${session_id}_${run_entity}" >> "$LIST_PROCESSED"
    log_message "Successfully processed ${subject_id} ${session_id} ${run_entity}"
    
    # ========================================================================
    # Progress reporting
    # ========================================================================
    
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))
    
    if [[ $n -gt 0 ]]; then
        avg_time=$((elapsed / n))
        remaining=$((TOTAL - n))
        eta=$((remaining * avg_time))
        
        elapsed_formatted=$(printf "%02d:%02d:%02d" $((elapsed/3600)) $(((elapsed%3600)/60)) $((elapsed%60)))
        eta_formatted=$(printf "%02d:%02d:%02d" $((eta/3600)) $(((eta%3600)/60)) $((eta%60)))
        
        log_message "Progress: ${n}/${TOTAL} | Elapsed: ${elapsed_formatted} | ETA: ${eta_formatted}"
    fi
    
    log_message ""
    
done

################################################################################
# Batch Summary
################################################################################

log_message "=================================================="
log_message "=== Batch completed ==="
log_message "=================================================="

total_time=$(date +%s)
total_elapsed=$((total_time - start_time))
total_formatted=$(printf "%02d:%02d:%02d" $((total_elapsed/3600)) $(((total_elapsed%3600)/60)) $((total_elapsed%60)))

log_message "Total time for this batch: ${total_formatted}"
log_message "Processed $n of $TOTAL lesion masks"
log_message "Log file: $BATCH_LOG"
log_message "=== Done ==="

exit 0