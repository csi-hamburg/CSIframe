#!/bin/bash
# ============================================================================
# Script to Handle Failed Registrations Based on QC Results
# ============================================================================
# Directories
RAW_BIDS="data/raw_bids"
DERIVATIVES="${RAW_BIDS}/derivatives/lesion_masks_mni"
QC_TABLE="${DERIVATIVES}/logs/quality_control_results.csv"
# Suffix for renaming
RENAME_SUFFIX=".failed"
# Dry run mode - set to 1 to see what would happen without actually doing it
DRY_RUN=0
# ============================================================================
# Helper Functions
# ============================================================================
# Rename a file by adding suffix (only if not already renamed)
rename_file() {
    local file="$1"
    
    # Check if file already has the suffix
    if [[ "$file" == *"${RENAME_SUFFIX}" ]]; then
        return
    fi
    
    if [[ -f "$file" ]]; then
        if [[ $DRY_RUN -eq 1 ]]; then
            echo "  [DRY RUN] Would rename: $file" >&2
        else
            mv "$file" "${file}${RENAME_SUFFIX}"
            echo "  Renamed: $file" >&2
        fi
    fi
}

# Handle bad Anatomical → Template registration (and downstream)
# This is the common part shared by both bad dwi→anat and bad anat→template
handle_bad_anat_to_template() {
    local sub="$1"
    local ses="$2"
    local run="$3"
    local anat_used="$4"  # Full anatomical name like "acq-1_FLAIR" or "FLAIR"
    local base_anat_type="$5"  # Just "FLAIR" or "T1w"
    local template_space="$6"
    
    # === Anatomical directory files ===
    local anat_dir="${DERIVATIVES}/${sub}/${ses}/anat"
    
    # Find all anatomical files and rename them (handles variants)
    # Registered to template
    for file in "${anat_dir}"/${sub}_${ses}_*${base_anat_type}*_space-${template_space}.nii.gz; do
        if [[ -f "$file" ]]; then
            rename_file "$file"
        fi
    done
    
    # Bias-corrected
    for file in "${anat_dir}"/${sub}_${ses}_*${base_anat_type}*_desc-biascorr.nii.gz; do
        if [[ -f "$file" ]]; then
            rename_file "$file"
        fi
    done
    
    # Brain-extracted
    for file in "${anat_dir}"/${sub}_${ses}_*${base_anat_type}*_desc-brain.nii.gz; do
        if [[ -f "$file" ]]; then
            rename_file "$file"
        fi
    done
    
    # Brain mask
    for file in "${anat_dir}"/${sub}_${ses}_*${base_anat_type}*_desc-brain_mask.nii.gz; do
        if [[ -f "$file" ]]; then
            rename_file "$file"
        fi
    done
    
    # === Lesion directory files ===
    local lesion_dir="${DERIVATIVES}/${sub}/${ses}/lesion"
    
    # Lesion in template space
    # Match everything after ses-02 up to dseg
    for file in "${lesion_dir}/${sub}_${ses}_"*"${run}_dseg_space-MNI152.nii.gz"; do
        if [[ -f "$file" ]]; then
            rename_file "$file"
        fi
    done
    
    # Also check for alternative template space
    if [[ "$template_space" == "MIPLabFLAIR" ]]; then
        local lesion_mni="${lesion_dir}/${sub}_${ses}_${run}_dseg_space-MNI152.nii.gz"
        rename_file "$lesion_mni"
    else
        local lesion_flair="${lesion_dir}/${sub}_${ses}_${run}_dseg_space-MIPLabFLAIR.nii.gz"
        rename_file "$lesion_flair"
    fi
    
    # === Transformation files ===
    local xfm_dir="${DERIVATIVES}/${sub}/${ses}/xfm"
    
    # Anatomical to template transforms - use wildcards to catch all variants
    for file in "${xfm_dir}/${sub}_${ses}_from-${base_anat_type}_to-${template_space}"*.h5; do
        if [[ -f "$file" ]]; then
            rename_file "$file"
        fi
    done
    
    for file in "${xfm_dir}/${sub}_${ses}_from-${base_anat_type}_to-${template_space}"*.mat; do
        if [[ -f "$file" ]]; then
            rename_file "$file"
        fi
    done
}

# Handle bad DWI → Anatomical registration
# This affects: DWI registered to anatomical, PLUS all downstream (calls handle_bad_anat_to_template)
handle_bad_dwi_to_anat() {
    local sub="$1"
    local ses="$2"
    local run="$3"
    local anat_used="$4"
    local dwi_used="$5"
    
    echo "Handling bad DWI→Anat for ${sub}_${ses}_${run}" >&2
    
    # Determine base anatomical type
    local base_anat_type=""
    if [[ "$anat_used" =~ FLAIR ]]; then
        base_anat_type="FLAIR"
    elif [[ "$anat_used" =~ T1w ]]; then
        base_anat_type="T1w"
    else
        echo "  Warning: Cannot determine anatomical type from '$anat_used'" >&2
        return
    fi
    
    local template_space=""
    if [[ "$base_anat_type" == "FLAIR" ]]; then
        template_space="MIPLabFLAIR"
    else
        template_space="MNI152"
    fi
    
    # Determine base DWI type
    local base_dwi_type=""
    if [[ "$dwi_used" =~ ^adc ]]; then
        base_dwi_type="adc"
    elif [[ "$dwi_used" =~ ^dwi ]]; then
        base_dwi_type="dwi"
    elif [[ "$dwi_used" =~ ^trace ]]; then
        base_dwi_type="trace"
    fi
    
    # === DWI directory files (specific to dwi→anat failure) ===
    if [[ "$dwi_used" != "none" && -n "$base_dwi_type" ]]; then
        local dwi_dir="${DERIVATIVES}/${sub}/${ses}/dwi"
        
        # DWI registered to anatomical - need flexible pattern to catch acq-X between ses and run
        # Pattern: sub-XXX_ses-XX_*_run-XX_*adc*_space-FLAIR.nii.gz
        # This catches: sub-XXX_ses-XX_run-XX_adc_space-FLAIR.nii.gz
        #           AND: sub-XXX_ses-XX_acq-1_run-XX_adc_space-FLAIR.nii.gz
        #           AND: sub-XXX_ses-XX_run-XX_adca_space-FLAIR.nii.gz
        for file in "${dwi_dir}/${sub}_${ses}_"*"_${run}_"*"${base_dwi_type}"*"_space-${base_anat_type}.nii.gz"; do
            if [[ -f "$file" ]]; then
                rename_file "$file"
            fi
        done
    fi
    
    # === DWI to anatomical transformation files ===
    local xfm_dir="${DERIVATIVES}/${sub}/${ses}/xfm"
    
    # DWI to anatomical transforms
    # Pattern needs to be flexible for acq- parameter
    for file in "${xfm_dir}/${sub}_${ses}_"*"_${run}_from-dwi_to-${base_anat_type}"*.h5; do
        if [[ -f "$file" ]]; then
            rename_file "$file"
        fi
    done
    
    for file in "${xfm_dir}/${sub}_${ses}_"*"_${run}_from-dwi_to-${base_anat_type}"*.mat; do
        if [[ -f "$file" ]]; then
            rename_file "$file"
        fi
    done
    
    # === Handle all downstream files (anatomical→template and beyond) ===
    handle_bad_anat_to_template "$sub" "$ses" "$run" "$anat_used" "$base_anat_type" "$template_space"
}

# Wrapper for handling bad anat→template when dwi→anat was good
handle_bad_anat_to_template_only() {
    local sub="$1"
    local ses="$2"
    local run="$3"
    local anat_used="$4"
    
    echo "Handling bad Anat→Template for ${sub}_${ses}_${run}" >&2
    
    # Determine base anatomical type
    local base_anat_type=""
    local template_space=""
    if [[ "$anat_used" =~ FLAIR ]]; then
        base_anat_type="FLAIR"
        template_space="MIPLabFLAIR"
    elif [[ "$anat_used" =~ T1w ]]; then
        base_anat_type="T1w"
        template_space="MNI152"
    else
        echo "  Warning: Cannot determine anatomical type from '$anat_used'" >&2
        return
    fi
    
    # Call the common function
    handle_bad_anat_to_template "$sub" "$ses" "$run" "$anat_used" "$base_anat_type" "$template_space"
}

# ============================================================================
# Main Script
# ============================================================================
main() {
    echo "========================================================================" >&2
    echo "Failed Registration Handler" >&2
    echo "Renaming to .failed" >&2
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "Mode: DRY RUN (no files will be modified)" >&2
    fi
    echo "========================================================================" >&2
    
    if [[ ! -f "$QC_TABLE" ]]; then
        echo "Error: QC table not found: $QC_TABLE" >&2
        exit 1
    fi
    
    echo "" >&2
    
    local line_num=0
    local bad_dwi_to_anat=0
    local bad_anat_to_template=0
    
    # Read CSV line by line (skip header)
    while IFS=, read -r subject session run has_FLAIR has_T1w has_adc has_dwi has_trace \
        has_lesion_mask anat_used anat_alternatives dwi_used dwi_alternatives \
        has_dwi_registered_to_anat has_anat_registered_to_template has_lesion_in_template_space \
        registration_success registration_failed_reason dwi_to_anat_rating dwi_to_anat_comment \
        anat_to_template_rating anat_to_template_comment; do
        
        ((line_num++))
        
        # Skip header
        if [[ $line_num -eq 1 ]]; then
            continue
        fi
        
        # Skip if no ratings (not QC'd yet)
        if [[ "$dwi_to_anat_rating" == "NA" && "$anat_to_template_rating" == "NA" ]]; then
            continue
        fi
        
        # Check DWI → Anatomical rating
        if [[ "$dwi_to_anat_rating" == "bad" ]]; then
            ((bad_dwi_to_anat++))
            handle_bad_dwi_to_anat "$subject" "$session" "$run" "$anat_used" "$dwi_used"
        elif [[ "$anat_to_template_rating" == "bad" ]]; then
            # Only handle anat→template if dwi→anat was good (or not rated)
            # If dwi→anat was bad, we already handled everything above
            ((bad_anat_to_template++))
            handle_bad_anat_to_template_only "$subject" "$session" "$run" "$anat_used"
        fi
        
    done < "$QC_TABLE"
    
    echo "" >&2
    echo "========================================================================" >&2
    echo "Summary" >&2
    echo "========================================================================" >&2
    echo "Bad DWI→Anatomical registrations handled: $bad_dwi_to_anat" >&2
    echo "Bad Anatomical→Template registrations handled: $bad_anat_to_template" >&2
    echo "========================================================================" >&2
}
# Run main function
main "$@"