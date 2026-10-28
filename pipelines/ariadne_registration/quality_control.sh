#!/bin/bash

# ============================================================================
# Quality Control Script for Registration Process
# ============================================================================

# Template file paths (edit as needed)
MIPLAB_FLAIR_TEMPLATE="templates/CSI_MNI_space/miplab-flair/miplab-flair_asym_with-skull.nii.gz"
MNI152_T1_TEMPLATE="templates/CSI_MNI_space/FSL/MNI152_T1_1mm.nii.gz"

# Base directories
RAW_BIDS="raw_bids"
DERIVATIVES="${RAW_BIDS}/derivatives/lesion_masks_mni"
LESION_MASKS="${RAW_BIDS}/derivatives/lesion_masks"
LOGS_DIR="${DERIVATIVES}/logs"

# Output file
QC_TABLE="${LOGS_DIR}/quality_control_results.csv"

# ============================================================================
# Helper Functions
# ============================================================================

# Initialize CSV header if file doesn't exist
initialize_csv() {
    if [[ ! -f "$QC_TABLE" ]]; then
        echo "subject,session,run,has_FLAIR,has_T1w,has_adc,has_dwi,has_trace,has_lesion_mask,anatomical_used_for_registration,anatomical_alternatives,dwi_used_for_registration,dwi_alternatives,has_dwi_registered_to_anat,has_anat_registered_to_template,has_lesion_in_template_space,registration_success,registration_failed_reason,dwi_to_anat_rating,dwi_to_anat_comment,anat_to_template_rating,anat_to_template_comment" > "$QC_TABLE"
        echo "Created new QC table: $QC_TABLE" >&2
    else
        echo "Resuming from existing QC table: $QC_TABLE" >&2
    fi
}

# Check if a subject-session-run combination has already been rated
is_already_rated() {
    local sub="$1"
    local ses="$2"
    local run="$3"
    
    if [[ -f "$QC_TABLE" ]]; then
        grep -q "^${sub},${ses},${run}," "$QC_TABLE" && return 0
    fi
    return 1
}

# Check if specific FLAIR exists
has_flair() {
    local sub="$1"
    local ses="$2"
    local anat_dir="${RAW_BIDS}/${sub}/${ses}/anat"
    
    if ls "${anat_dir}/${sub}_${ses}"*"FLAIR"*.nii.gz &>/dev/null 2>&1; then
        echo "1"
    else
        echo "0"
    fi
}

# Check if specific T1w exists
has_t1w() {
    local sub="$1"
    local ses="$2"
    local anat_dir="${RAW_BIDS}/${sub}/${ses}/anat"
    
    if ls "${anat_dir}/${sub}_${ses}"*"T1w"*.nii.gz &>/dev/null 2>&1; then
        echo "1"
    else
        echo "0"
    fi
}

# Check if specific DWI type exists
has_dwi_type() {
    local sub="$1"
    local ses="$2"
    local run="$3"
    local dwi_type="$4"  # adc, dwi, or trace
    local dwi_dir="${RAW_BIDS}/${sub}/${ses}/dwi"
    
    if [[ -f "${dwi_dir}/${sub}_${ses}_${run}_${dwi_type}.nii.gz" ]]; then
        echo "1"
    else
        echo "0"
    fi
}

# Check if lesion mask exists
has_lesion_mask() {
    local sub="$1"
    local ses="$2"
    local run="$3"
    
    local mask_file="${LESION_MASKS}/${sub}/${ses}/${sub}_${ses}_${run}_dseg.nii.gz"
    
    if [[ -f "$mask_file" ]]; then
        echo "1"
    else
        echo "0"
    fi
}

# Get all available anatomical alternatives (excluding the one used)
get_anatomical_alternatives() {
    local sub="$1"
    local ses="$2"
    local anat_used="$3"  # Pass the anatomical that was used
    local anat_dir="${RAW_BIDS}/${sub}/${ses}/anat"
    
    if [[ ! -d "$anat_dir" ]]; then
        echo "none"
        return
    fi
    
    local alternatives=()
    
    # Look for all .nii.gz files in anat directory
    for file in "${anat_dir}"/${sub}_${ses}_*.nii.gz; do
        if [[ -f "$file" ]]; then
            local basename=$(basename "$file" .nii.gz)
            local variant=$(echo "$basename" | sed "s/${sub}_${ses}_//")
            
            # Only include if it contains FLAIR or T1w AND it's not the one used
            if [[ "$variant" =~ (FLAIR|T1w) ]]; then
                if [[ "$variant" != "$anat_used" ]]; then
                    alternatives+=("$variant")
                fi
            fi
        fi
    done
    
    if [[ ${#alternatives[@]} -eq 0 ]]; then
        echo "none"
    else
        # Join array with semicolon
        local IFS=';'
        echo "${alternatives[*]}"
    fi
}

# Get all available DWI alternatives (excluding the one used)
get_dwi_alternatives() {
    local sub="$1"
    local ses="$2"
    local run="$3"
    local dwi_used="$4"  # Pass the DWI that was used
    local dwi_dir="${RAW_BIDS}/${sub}/${ses}/dwi"
    
    if [[ ! -d "$dwi_dir" ]]; then
        echo "none"
        return
    fi
    
    local alternatives=()
    
    # Look for all files matching the run
    for file in "${dwi_dir}"/${sub}_${ses}_${run}_*.nii.gz; do
        if [[ -f "$file" ]]; then
            local basename=$(basename "$file" .nii.gz)
            local variant=$(echo "$basename" | sed "s/${sub}_${ses}_${run}_//")
            
            # Only include if it contains adc, dwi, or trace AND it's not the one used
            if [[ "$variant" =~ ^(adc|dwi|trace) && "$variant" != "$dwi_used" ]]; then
                alternatives+=("$variant")
            fi
        fi
    done
    
    if [[ ${#alternatives[@]} -eq 0 ]]; then
        echo "none"
    else
        # Join array with semicolon
        local IFS=';'
        echo "${alternatives[*]}"
    fi
}

# Determine which anatomical was used for registration
get_anatomical_used() {
    local sub="$1"
    local ses="$2"
    local anat_dir="${RAW_BIDS}/${sub}/${ses}/anat"
    
    # Priority: FLAIR* > T1w*
    # Check for FLAIR variants first
    for file in "${anat_dir}"/${sub}_${ses}*FLAIR*.nii.gz; do
        if [[ -f "$file" ]]; then
            local basename=$(basename "$file" .nii.gz)
            local result=$(echo "$basename" | sed "s/${sub}_${ses}_//")
            echo "$result"
            return
        fi
    done
    
    # Then T1w variants
    for file in "${anat_dir}"/${sub}_${ses}*T1w*.nii.gz; do
        if [[ -f "$file" ]]; then
            local basename=$(basename "$file" .nii.gz)
            local result=$(echo "$basename" | sed "s/${sub}_${ses}_//")
            echo "$result"
            return
        fi
    done
    
    echo "none"
}

# Determine which DWI was used for registration
get_dwi_used() {
    local sub="$1"
    local ses="$2"
    local run="$3"
    local dwi_dir="${RAW_BIDS}/${sub}/${ses}/dwi"
    
    # Priority: adc* > dwi* > trace*
    # Check for adc variants first
    for file in "${dwi_dir}"/${sub}_${ses}_${run}_adc*.nii.gz; do
        if [[ -f "$file" ]]; then
            local basename=$(basename "$file" .nii.gz)
            echo "$basename" | sed "s/${sub}_${ses}_${run}_//"
            return
        fi
    done
    
    # Then dwi variants
    for file in "${dwi_dir}"/${sub}_${ses}_${run}_dwi*.nii.gz; do
        if [[ -f "$file" ]]; then
            local basename=$(basename "$file" .nii.gz)
            echo "$basename" | sed "s/${sub}_${ses}_${run}_//"
            return
        fi
    done
    
    # Finally trace variants
    for file in "${dwi_dir}"/${sub}_${ses}_${run}_trace*.nii.gz; do
        if [[ -f "$file" ]]; then
            local basename=$(basename "$file" .nii.gz)
            echo "$basename" | sed "s/${sub}_${ses}_${run}_//"
            return
        fi
    done
    
    echo "none"
}

# Check if DWI registered to anatomical file exists
has_dwi_registered_to_anat() {
    local sub="$1"
    local ses="$2"
    local run="$3"
    
    local dwi_dir="${DERIVATIVES}/${sub}/${ses}/dwi"
    
    # Check if any DWI type registered to any anatomical space exists
    for dwi_type in adc dwi trace; do
        for space in FLAIR T1w; do
            # Use wildcard to catch acquisition parameters
            local dwi_pattern="${dwi_dir}/${sub}_${ses}_*${run}_${dwi_type}_space-${space}.nii.gz"
            if ls $dwi_pattern 2>/dev/null | grep -q .; then
                echo "1"
                return
            fi
        done
    done
    
    echo "0"
}

# Check if anatomical registered to template file exists
has_anat_registered_to_template() {
    local sub="$1"
    local ses="$2"
    
    local anat_dir="${DERIVATIVES}/${sub}/${ses}/anat"
    
    # Check if any anatomical registered to any template space exists
    for anat_type in FLAIR T1w; do
        for space in MIPLabFLAIR MNI152; do
            # Use wildcard to catch acquisition parameters
            local anat_pattern="${anat_dir}/${sub}_${ses}_*${anat_type}_space-${space}.nii.gz"
            if ls $anat_pattern 2>/dev/null | grep -q .; then
                echo "1"
                return
            fi
        done
    done
    
    echo "0"
}

# Check if lesion mask in template space exists
has_lesion_in_template_space() {
    local sub="$1"
    local ses="$2"
    local run="$3"
    
    local lesion_dir="${DERIVATIVES}/${sub}/${ses}/lesion"
    
    # Check for MNI152 space (T1w-based registration)
    local lesion_pattern_mni="${lesion_dir}/${sub}_${ses}_*${run}_dseg_space-MNI152.nii.gz"
    if ls $lesion_pattern_mni 2>/dev/null | grep -q .; then
        echo "1"
        return
    fi
    
    # Check for MIPLabFLAIR space
    local lesion_pattern_flair="${lesion_dir}/${sub}_${ses}_*${run}_dseg_space-MIPLabFLAIR.nii.gz"
    if ls $lesion_pattern_flair 2>/dev/null | grep -q .; then
        echo "1"
        return
    fi
    
    echo "0"
}

# Get the full anatomical filename
get_anatomical_file() {
    local sub="$1"
    local ses="$2"
    local anat_used="$3"
    local anat_dir="${RAW_BIDS}/${sub}/${ses}/anat"
    
    local file=$(ls "${anat_dir}/${sub}_${ses}_${anat_used}.nii.gz" 2>/dev/null | head -1)
    
    if [[ -f "$file" ]]; then
        echo "$file"
    else
        echo ""
    fi
}

# Prompt for quality rating
get_quality_rating() {
    local prompt_text="$1"
    local rating=""
    local comment=""
    
    while true; do
        echo "" >&2
        echo "==========================================" >&2
        echo "$prompt_text" >&2
        echo "==========================================" >&2
        read -p "Quality rating (1=good, 0=bad): " rating </dev/tty
        
        if [[ "$rating" == "1" || "$rating" == "0" ]]; then
            if [[ "$rating" == "0" ]]; then
                read -p "Please provide a comment: " comment </dev/tty
            fi
            break
        else
            echo "Invalid input. Please enter '1' for good or '0' for bad." >&2
        fi
    done
    
    # Convert to good/bad for CSV
    if [[ "$rating" == "1" ]]; then
        echo "good|${comment}"
    else
        echo "bad|${comment}"
    fi
}

# Process QC for a successfully registered subject
process_qc_for_subject() {
    local sub="$1"
    local ses="$2"
    local run="$3"
    local dwi_used="$4"
    local anat_used="$5"
    
    echo "" >&2
    echo "========================================================================" >&2
    echo "Processing QC: ${sub} ${ses} ${run}" >&2
    echo "========================================================================" >&2
    
    # Extract base anatomical type
    local base_anat_type=""
    local template_file=""
    
    if [[ "$anat_used" =~ FLAIR ]]; then
        base_anat_type="FLAIR"
        template_file="$MIPLAB_FLAIR_TEMPLATE"
    elif [[ "$anat_used" =~ T1w ]]; then
        base_anat_type="T1w"
        template_file="$MNI152_T1_TEMPLATE"
    else
        echo "Error: Cannot determine anatomical type from: $anat_used" >&2
        return 1
    fi
    
    local template_space=""
    if [[ "$base_anat_type" == "FLAIR" ]]; then
        template_space="MIPLabFLAIR"
    else
        template_space="MNI152"
    fi
    
    # Construct file paths - search for files that match the pattern
    # DWI registered to anatomical
    local dwi_registered="${DERIVATIVES}/${sub}/${ses}/dwi/${sub}_${ses}_*${run}_${dwi_used}_space-${base_anat_type}.nii.gz"
    dwi_registered=$(ls $dwi_registered 2>/dev/null | head -1)
    
    # Native anatomical
    local anat_native=$(get_anatomical_file "$sub" "$ses" "$anat_used")
    
    # Anatomical registered to template
    local anat_registered="${DERIVATIVES}/${sub}/${ses}/anat/${sub}_${ses}_*${base_anat_type}_space-${template_space}.nii.gz"
    anat_registered=$(ls $anat_registered 2>/dev/null | head -1)
    
    # Verify all files exist
    if [[ ! -f "$dwi_registered" ]]; then
        echo "Error: DWI registered file not found matching: ${DERIVATIVES}/${sub}/${ses}/dwi/${sub}_${ses}_*${run}_${dwi_used}_space-${base_anat_type}.nii.gz" >&2
        return 1
    fi
    
    if [[ ! -f "$anat_native" ]]; then
        echo "Error: Native anatomical file not found: $anat_native" >&2
        return 1
    fi
    
    if [[ ! -f "$anat_registered" ]]; then
        echo "Error: Registered anatomical file not found matching: ${DERIVATIVES}/${sub}/${ses}/anat/${sub}_${ses}_*${base_anat_type}_space-${template_space}.nii.gz" >&2
        return 1
    fi
    
    if [[ ! -f "$template_file" ]]; then
        echo "Error: Template file not found: $template_file" >&2
        return 1
    fi
    
    echo "" >&2
    echo "Files to review:" >&2
    echo "  1. DWI → Anatomical registration:" >&2
    echo "     - DWI (registered): $dwi_registered" >&2
    echo "     - Anatomical (native): $anat_native" >&2
    echo "" >&2
    echo "  2. Anatomical → Template registration:" >&2
    echo "     - Anatomical (registered): $anat_registered" >&2
    echo "     - Template: $template_file" >&2
    echo "" >&2
    
    # Check 1: DWI to Anatomical
    echo "Opening FSLeyes for DWI → Anatomical registration check..." >&2
    fsleyes "$anat_native" "$dwi_registered" &
    FSLEYES_PID=$!
    
    # Wait for FSLeyes to close
    wait $FSLEYES_PID
    
    # Get rating for DWI → Anatomical
    local dwi_to_anat_result=$(get_quality_rating "DWI → Anatomical Registration Quality")
    local dwi_to_anat_rating=$(echo "$dwi_to_anat_result" | cut -d'|' -f1)
    local dwi_to_anat_comment=$(echo "$dwi_to_anat_result" | cut -d'|' -f2)
    
    # Check 2: Anatomical to Template
    echo "" >&2
    echo "Opening FSLeyes for Anatomical → Template registration check..." >&2
    fsleyes "$template_file" "$anat_registered" &
    FSLEYES_PID=$!
    
    # Wait for FSLeyes to close
    wait $FSLEYES_PID
    
    # Get rating for Anatomical → Template
    local anat_to_template_result=$(get_quality_rating "Anatomical → Template Registration Quality")
    local anat_to_template_rating=$(echo "$anat_to_template_result" | cut -d'|' -f1)
    local anat_to_template_comment=$(echo "$anat_to_template_result" | cut -d'|' -f2)
    
    # Escape commas in comments for CSV
    dwi_to_anat_comment=$(echo "$dwi_to_anat_comment" | sed 's/,/;/g')
    anat_to_template_comment=$(echo "$anat_to_template_comment" | sed 's/,/;/g')
    
    echo "" >&2
    echo "✓ Quality control completed for ${sub}_${ses}_${run}" >&2
    echo "========================================================================" >&2
    
    # Return the ratings
    echo "${dwi_to_anat_rating}|${dwi_to_anat_comment}|${anat_to_template_rating}|${anat_to_template_comment}"
}

# Process a single subject-session-run combination
process_subject() {
    local sub="$1"
    local ses="$2"
    local run="$3"
    
    # Check if already rated
    if is_already_rated "$sub" "$ses" "$run"; then
        echo "Skipping ${sub}_${ses}_${run} (already rated)" >&2
        return
    fi
    
    echo "Processing ${sub}_${ses}_${run}..." >&2
    
    # Check for each file type
    local has_flair_file=$(has_flair "$sub" "$ses")
    local has_t1w_file=$(has_t1w "$sub" "$ses")
    local has_adc_file=$(has_dwi_type "$sub" "$ses" "$run" "adc")
    local has_dwi_file=$(has_dwi_type "$sub" "$ses" "$run" "dwi")
    local has_trace_file=$(has_dwi_type "$sub" "$ses" "$run" "trace")
    local has_lesion=$(has_lesion_mask "$sub" "$ses" "$run")
    
    # Get what was used for registration
    local anat_used=$(get_anatomical_used "$sub" "$ses")
    local dwi_used=$(get_dwi_used "$sub" "$ses" "$run")
    
    # Get alternatives (escape commas)
    local anat_alternatives=$(get_anatomical_alternatives "$sub" "$ses" "$anat_used" | sed 's/,/;/g')
    local dwi_alternatives=$(get_dwi_alternatives "$sub" "$ses" "$run" "$dwi_used" | sed 's/,/;/g')
    
    # Check registration status
    local registration_success=0
    local registration_failed_reason=""
    
    local subject_id="${sub}_${ses}_${run}"
    
    # Check if registration succeeded
    if grep -q "$subject_id" "${LOGS_DIR}/processed_successfully.txt" 2>/dev/null; then
        registration_success=1
    fi
    
    # Check if registration failed (escape commas)
    if grep -q "$subject_id" "${LOGS_DIR}/registration_failed.txt" 2>/dev/null; then
        registration_failed_reason=$(grep "$subject_id" "${LOGS_DIR}/registration_failed.txt" | cut -d' ' -f2- | sed 's/,/;/g')
    fi
    
    # Check for output files
    local dwi_reg_exists=$(has_dwi_registered_to_anat "$sub" "$ses" "$run")
    local anat_reg_exists=$(has_anat_registered_to_template "$sub" "$ses")
    local lesion_template_exists=$(has_lesion_in_template_space "$sub" "$ses" "$run")
    
    # Perform QC if registration was successful and files exist
    local dwi_to_anat_rating="NA"
    local dwi_to_anat_comment=""
    local anat_to_template_rating="NA"
    local anat_to_template_comment=""
    
    if [[ $registration_success -eq 1 && $dwi_reg_exists -eq 1 && $anat_reg_exists -eq 1 ]]; then
        local qc_results=$(process_qc_for_subject "$sub" "$ses" "$run" "$dwi_used" "$anat_used")
        if [[ $? -eq 0 && -n "$qc_results" ]]; then
            dwi_to_anat_rating=$(echo "$qc_results" | cut -d'|' -f1)
            dwi_to_anat_comment=$(echo "$qc_results" | cut -d'|' -f2 | sed 's/,/;/g')
            anat_to_template_rating=$(echo "$qc_results" | cut -d'|' -f3)
            anat_to_template_comment=$(echo "$qc_results" | cut -d'|' -f4 | sed 's/,/;/g')
        fi
    fi
    
    # Write to CSV - ensure all fields are properly escaped
    echo "${sub},${ses},${run},${has_flair_file},${has_t1w_file},${has_adc_file},${has_dwi_file},${has_trace_file},${has_lesion},${anat_used},${anat_alternatives},${dwi_used},${dwi_alternatives},${dwi_reg_exists},${anat_reg_exists},${lesion_template_exists},${registration_success},${registration_failed_reason},${dwi_to_anat_rating},${dwi_to_anat_comment},${anat_to_template_rating},${anat_to_template_comment}" >> "$QC_TABLE"
}

# Find all lesion masks to determine which subject-session-run combinations to check
find_all_lesion_mask_combinations() {
    find "${LESION_MASKS}" -name "*_dseg.nii.gz" 2>/dev/null | while read -r mask_file; do
        local basename=$(basename "$mask_file" .nii.gz)
        # Extract sub-XXX-XXX_ses-XX_run-XX from filename
        if [[ "$basename" =~ ^(sub-[0-9]+-[0-9]+)_(ses-[0-9]+)_(run-[0-9]+[a-z]?)_dseg$ ]]; then
            echo "${BASH_REMATCH[1]}|${BASH_REMATCH[2]}|${BASH_REMATCH[3]}"
        fi
    done
}

# Find all subject-session-run combinations in raw_bids
find_all_subject_sessions() {
    for sub_dir in "${RAW_BIDS}"/sub-*; do
        if [[ -d "$sub_dir" ]]; then
            local sub=$(basename "$sub_dir")
            for ses_dir in "${sub_dir}"/ses-*; do
                if [[ -d "$ses_dir" ]]; then
                    local ses=$(basename "$ses_dir")
                    
                    # Look for DWI files to determine runs
                    if [[ -d "${ses_dir}/dwi" ]]; then
                        for dwi_file in "${ses_dir}/dwi"/${sub}_${ses}_run-*.nii.gz; do
                            if [[ -f "$dwi_file" ]]; then
                                local basename=$(basename "$dwi_file" .nii.gz)
                                # Extract run
                                if [[ "$basename" =~ (run-[0-9]+[a-z]?) ]]; then
                                    echo "${sub}|${ses}|${BASH_REMATCH[1]}"
                                fi
                            fi
                        done
                    fi
                fi
            done
        fi
    done | sort -u
}

# ============================================================================
# Main Script
# ============================================================================

main() {
    echo "========================================================================" >&2
    echo "Registration Quality Control Script" >&2
    echo "========================================================================" >&2
    
    # Check if template files exist
    if [[ ! -f "$MIPLAB_FLAIR_TEMPLATE" ]]; then
        echo "Warning: MIPLAB FLAIR template not found: $MIPLAB_FLAIR_TEMPLATE" >&2
        echo "Please update the template path in the script." >&2
    fi
    
    if [[ ! -f "$MNI152_T1_TEMPLATE" ]]; then
        echo "Warning: MNI152 T1 template not found: $MNI152_T1_TEMPLATE" >&2
        echo "Please update the template path in the script." >&2
    fi
    
    # Initialize CSV
    initialize_csv
    
    echo "" >&2
    echo "Finding all subject-session-run combinations..." >&2
    
    # Collect all combinations from both lesion masks and raw data
    declare -A all_combinations
    
    # Add combinations from lesion masks
    while IFS= read -r combo; do
        if [[ -n "$combo" ]]; then
            all_combinations["$combo"]=1
        fi
    done < <(find_all_lesion_mask_combinations)
    
    # Add combinations from raw data
    while IFS= read -r combo; do
        if [[ -n "$combo" ]]; then
            all_combinations["$combo"]=1
        fi
    done < <(find_all_subject_sessions)
    
    local total_count=${#all_combinations[@]}
    local processed_count=0
    
    echo "Found ${total_count} subject-session-run combinations" >&2
    echo "" >&2
    
    # Process each combination
    for combo in "${!all_combinations[@]}"; do
        local sub=$(echo "$combo" | cut -d'|' -f1)
        local ses=$(echo "$combo" | cut -d'|' -f2)
        local run=$(echo "$combo" | cut -d'|' -f3)
        
        process_subject "$sub" "$ses" "$run"
        ((processed_count++))
        
        # Progress indicator
        if (( processed_count % 10 == 0 )); then
            echo "Progress: ${processed_count}/${total_count}" >&2
        fi
    done
    
    echo "" >&2
    echo "========================================================================" >&2
    echo "Quality Control Complete!" >&2
    echo "========================================================================" >&2
    echo "Total combinations: ${total_count}" >&2
    echo "Results saved to: $QC_TABLE" >&2
    echo "========================================================================" >&2
}

# Run main function
main "$@"