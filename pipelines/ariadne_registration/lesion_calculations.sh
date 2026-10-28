#!/bin/bash

# ============================================================================
# Lesion Overlay Analysis Script
# ============================================================================

# Configuration variables
VOLUME_DIFF_THRESHOLD=20  # Percentage difference threshold for multiple runs
NUM_SLICES=7              # Number of axial slices to display

# Directories
LESION_MNI_DIR="data/raw_bids/derivatives/lesion_masks_mni"
LESION_NATIVE_DIR="data/raw_bids/derivatives/lesion_masks"
OUTPUT_DIR="output/overlay_map"
LOG_DIR="data/raw_bids/derivatives/lesion_masks/logs"
TEMPLATE="data/templates/CSI_MNI_space/FSL/MNI152_T1_1mm_brain.nii.gz"

# Output files
VOLUME_CSV="${LOG_DIR}/lesion_volumes.csv"
OVERLAY_SUM="${OUTPUT_DIR}/lesion_frequency_map.nii.gz"
OVERLAY_PNG="${OUTPUT_DIR}/lesion_overlay_all_subjects.png"
OVERLAY_SELECTION_LOG="${OUTPUT_DIR}/overlay_mask_selection.log"

# ============================================================================
# Setup
# ============================================================================

# Create output directories
mkdir -p "${OUTPUT_DIR}"
mkdir -p "${LOG_DIR}"

# Initialize CSV file
echo "subject,session,run,volume_mm3" > "${VOLUME_CSV}"
echo "Overlay Mask Selection Log" > "${OVERLAY_SELECTION_LOG}"
echo "==========================" >> "${OVERLAY_SELECTION_LOG}"
echo "" >> "${OVERLAY_SELECTION_LOG}"

# ============================================================================
# Functions
# ============================================================================

calculate_volume() {
    local mask_file=$1
    
    # Get voxel dimensions (in mm)
    voxel_dims=$(fslinfo "${mask_file}" | grep pixdim[1-3] | awk '{print $2}')
    dim1=$(echo "${voxel_dims}" | sed -n '1p')
    dim2=$(echo "${voxel_dims}" | sed -n '2p')
    dim3=$(echo "${voxel_dims}" | sed -n '3p')
    
    # Calculate voxel volume in mm3
    voxel_volume=$(echo "${dim1} * ${dim2} * ${dim3}" | bc -l)
    
    # Count non-zero voxels
    nvoxels=$(fslstats "${mask_file}" -V | awk '{print $1}')
    
    # Calculate total volume in mm3
    volume=$(echo "${nvoxels} * ${voxel_volume}" | bc -l)
    
    echo "${volume}"
}

extract_subject_session_run() {
    local filename=$1
    
    # Extract subject (sub-XXX-XXX)
    subject=$(echo "${filename}" | grep -oP 'sub-\d+-\d+')
    
    # Extract session (ses-XX)
    session=$(echo "${filename}" | grep -oP 'ses-\d+')
    
    # Extract run (run-XX)
    run=$(echo "${filename}" | grep -oP 'run-[^_]+')
    
    echo "${subject}|${session}|${run}"
}

get_session_priority() {
    local session=$1
    # Extract number from ses-XX
    local num=$(echo "${session}" | grep -oP '\d+')
    
    # Priority order: ses-02 (0), ses-01 (1), ses-03 (2), ses-04 (3), ...
    if [ "${num}" == "02" ]; then
        echo "0"
    elif [ "${num}" == "01" ]; then
        echo "1"
    else
        # For ses-03 and higher, priority is num
        echo "${num}"
    fi
}

# ============================================================================
# Step 1: Calculate lesion volumes in native space
# ============================================================================

echo "============================================================================"
echo "Step 1: Calculating lesion volumes in native space"
echo "============================================================================"

# Create associative array to store volume info for later use
declare -A session_volume_status  # stores "OK" or "ERROR" for each subject-session
declare -A session_volumes         # stores volumes for each subject-session-run

# Find all subjects and sessions
for subject_dir in "${LESION_NATIVE_DIR}"/sub-*/; do
    for session_dir in "${subject_dir}"ses-*/; do
        
        # Find all lesion masks for this subject/session
        lesion_masks=($(find "${session_dir}" -name "*_dseg.nii.gz" | sort))
        
        if [ ${#lesion_masks[@]} -eq 0 ]; then
            echo "Warning: No lesion masks found in ${session_dir}"
            continue
        fi
        
        # Extract subject and session info from first mask
        info=$(extract_subject_session_run "$(basename "${lesion_masks[0]}")")
        subject=$(echo "${info}" | cut -d'|' -f1)
        session=$(echo "${info}" | cut -d'|' -f2)
        
        echo ""
        echo "Processing ${subject} ${session}..."
        
        # Calculate volumes for all runs
        declare -a volumes
        declare -a run_names
        
        for mask in "${lesion_masks[@]}"; do
            info=$(extract_subject_session_run "$(basename "${mask}")")
            run=$(echo "${info}" | cut -d'|' -f3)
            
            volume=$(calculate_volume "${mask}")
            volumes+=("${volume}")
            run_names+=("${run}")
            
            # Store volume for later lookup
            session_volumes["${subject}|${session}|${run}"]="${volume}"
            
            echo "  ${run}: ${volume} mm³"
            echo "${subject},${session},${run},${volume}" >> "${VOLUME_CSV}"
        done
        
        # Compare volumes if multiple runs exist
        if [ ${#volumes[@]} -gt 1 ]; then
            echo "  Comparing ${#volumes[@]} runs..."
            
            # Find min and max volumes
            min_vol=$(printf '%s\n' "${volumes[@]}" | sort -n | head -n1)
            max_vol=$(printf '%s\n' "${volumes[@]}" | sort -n | tail -n1)
            
            # Calculate percentage difference
            diff=$(echo "scale=2; (${max_vol} - ${min_vol}) / ${min_vol} * 100" | bc -l)
            diff_abs=$(echo "${diff}" | sed 's/-//')
            
            echo "  Volume difference: ${diff_abs}%"
            
            # Check if difference exceeds threshold
            exceeds=$(echo "${diff_abs} > ${VOLUME_DIFF_THRESHOLD}" | bc -l)
            
            if [ "${exceeds}" -eq 1 ]; then
                echo "  ERROR: Volume difference (${diff_abs}%) exceeds threshold (${VOLUME_DIFF_THRESHOLD}%)"
                echo "  ERROR: ${subject} ${session} - volume difference ${diff_abs}% > ${VOLUME_DIFF_THRESHOLD}%" >> "${LOG_DIR}/volume_errors.log"
                session_volume_status["${subject}|${session}"]="ERROR"
            else
                echo "  ✓ Volume difference within acceptable range"
                session_volume_status["${subject}|${session}"]="OK"
            fi
        else
            # Single run - always OK
            session_volume_status["${subject}|${session}"]="OK"
        fi
        
        # Clear arrays for next iteration
        unset volumes
        unset run_names
        
    done
done

echo ""
echo "Lesion volumes saved to: ${VOLUME_CSV}"

# ============================================================================
# Step 2: Select one lesion mask per subject for overlay
# ============================================================================

echo ""
echo "============================================================================"
echo "Step 2: Selecting one lesion mask per subject (priority: ses-02, 01, 03...)"
echo "============================================================================"

# Create associative array to store best mask per subject
declare -A subject_best_mask
declare -A subject_best_priority

# Find all subjects
for subject_dir in "${LESION_MNI_DIR}"/sub-*/; do
    subject=$(basename "${subject_dir}")
    
    echo ""
    echo "Processing ${subject}..."
    
    # Find all sessions for this subject, sorted by priority
    declare -a session_candidates
    
    for session_dir in "${subject_dir}"ses-*/; do
        session=$(basename "${session_dir}")
        lesion_dir="${session_dir}lesion"
        
        if [ ! -d "${lesion_dir}" ]; then
            continue
        fi
        
        # Get priority for this session
        priority=$(get_session_priority "${session}")
        
        # Store with priority prefix for sorting
        session_candidates+=("${priority}|${session}|${lesion_dir}")
    done
    
    # Sort sessions by priority
    IFS=$'\n' sorted_sessions=($(sort -t'|' -k1 -n <<<"${session_candidates[*]}"))
    unset IFS
    
    # Try sessions in priority order
    mask_found=false
    for session_entry in "${sorted_sessions[@]}"; do
        priority=$(echo "${session_entry}" | cut -d'|' -f1)
        session=$(echo "${session_entry}" | cut -d'|' -f2)
        lesion_dir=$(echo "${session_entry}" | cut -d'|' -f3)
        
        echo "  Checking ${session} (priority: ${priority})..."
        
        # Check volume status for this session
        volume_status="${session_volume_status[${subject}|${session}]}"
        
        if [ "${volume_status}" == "ERROR" ]; then
            echo "    ✗ Skipped: Multiple runs with volume difference > ${VOLUME_DIFF_THRESHOLD}%"
            echo "${subject} ${session}: SKIPPED - volume difference exceeded threshold" >> "${OVERLAY_SELECTION_LOG}"
            continue
        fi
        
        # Find all MNI masks for this session
        mni_masks=($(find "${lesion_dir}" -name "*_dseg_space-MNI152.nii.gz" | sort))
        
        if [ ${#mni_masks[@]} -eq 0 ]; then
            echo "    ✗ No MNI space mask found"
            continue
        fi
        
        # Check if multiple runs exist in MNI space
        if [ ${#mni_masks[@]} -gt 1 ]; then
            echo "    Found ${#mni_masks[@]} runs in MNI space"
            
            # Calculate volumes for MNI masks to verify consistency
            declare -a mni_volumes
            for mni_mask in "${mni_masks[@]}"; do
                vol=$(calculate_volume "${mni_mask}")
                mni_volumes+=("${vol}")
            done
            
            # Check volume difference
            min_vol=$(printf '%s\n' "${mni_volumes[@]}" | sort -n | head -n1)
            max_vol=$(printf '%s\n' "${mni_volumes[@]}" | sort -n | tail -n1)
            diff=$(echo "scale=2; (${max_vol} - ${min_vol}) / ${min_vol} * 100" | bc -l)
            diff_abs=$(echo "${diff}" | sed 's/-//')
            exceeds=$(echo "${diff_abs} > ${VOLUME_DIFF_THRESHOLD}" | bc -l)
            
            if [ "${exceeds}" -eq 1 ]; then
                echo "    ✗ MNI space volume difference (${diff_abs}%) exceeds threshold"
                echo "${subject} ${session}: SKIPPED - MNI volume difference ${diff_abs}% > ${VOLUME_DIFF_THRESHOLD}%" >> "${OVERLAY_SELECTION_LOG}"
                unset mni_volumes
                continue
            fi
            
            echo "    ✓ MNI space volume difference (${diff_abs}%) within threshold"
            unset mni_volumes
        fi
        
        # Use first mask (they're within threshold or only one exists)
        selected_mask="${mni_masks[0]}"
        subject_best_mask[${subject}]="${selected_mask}"
        subject_best_priority[${subject}]="${priority}"
        
        info=$(extract_subject_session_run "$(basename "${selected_mask}")")
        selected_run=$(echo "${info}" | cut -d'|' -f3)
        
        echo "    ✓ Selected ${session} ${selected_run}"
        echo "${subject} ${session} ${selected_run}: SELECTED" >> "${OVERLAY_SELECTION_LOG}"
        
        mask_found=true
        break
    done
    
    if [ "${mask_found}" = false ]; then
        echo "  ✗ No suitable mask found for ${subject}"
        echo "${subject}: NO SUITABLE MASK FOUND" >> "${OVERLAY_SELECTION_LOG}"
    fi
    
    # Clear array for next subject
    unset session_candidates
done

# Convert associative array to indexed array for processing
declare -a mni_masks_to_use
for subject in "${!subject_best_mask[@]}"; do
    mni_masks_to_use+=("${subject_best_mask[${subject}]}")
done

echo ""
echo "Total subjects to include in overlay: ${#mni_masks_to_use[@]}"
echo "" >> "${OVERLAY_SELECTION_LOG}"
echo "Total subjects included in overlay: ${#mni_masks_to_use[@]}" >> "${OVERLAY_SELECTION_LOG}"

if [ ${#mni_masks_to_use[@]} -eq 0 ]; then
    echo "ERROR: No MNI space lesion masks found!"
    exit 1
fi

# ============================================================================
# Step 3: Create frequency overlay map from selected MNI space lesions
# ============================================================================

echo ""
echo "============================================================================"
echo "Step 3: Creating lesion frequency map in MNI space"
echo "============================================================================"

# Sum all masks to create frequency map
echo "Creating frequency map..."
first_mask="${mni_masks_to_use[0]}"
fslmaths "${first_mask}" "${OVERLAY_SUM}"

for i in $(seq 1 $((${#mni_masks_to_use[@]} - 1))); do
    mask="${mni_masks_to_use[$i]}"
    fslmaths "${OVERLAY_SUM}" -add "${mask}" "${OVERLAY_SUM}"
done

echo "Frequency map saved to: ${OVERLAY_SUM}"

# Get max frequency for color bar
max_freq=$(fslstats "${OVERLAY_SUM}" -R | awk '{print $2}')
echo "Maximum lesion overlap: ${max_freq} subjects"

# ============================================================================
# Step 4: Create overlay visualization
# ============================================================================

echo ""
echo "============================================================================"
echo "Step 4: Creating overlay visualization"
echo "============================================================================"

# Get max frequency for color bar (already calculated but recalculate for clarity)
max_freq=$(fslstats "${OVERLAY_SUM}" -R | awk '{print $2}')
max_freq_int=$(printf "%.0f" "${max_freq}")

echo "Maximum lesion overlap: ${max_freq_int} subjects"

# Create overlay image using fsleyes
echo "Rendering with fsleyes..."

fsleyes render \
    --outfile "${OVERLAY_PNG}" \
    --size 1785 536 \
    --scene lightbox \
    --worldLoc 0.0 0.0 0.0 \
    --zaxis 2 --zrange 0.25 0.75 --sliceSpacing 0.08 --sampleSlices start \
    --labelSpace none --sliceOverlap 40 --hideCursor --cursorWidth 1.0 \
    --bgColour 1.0 1.0 1.0 --fgColour 0.0 0.0 0.0 --cursorColour 0.0 1.0 0.0 \
    --showColourBar --colourBarLocation right --colourBarLabelSide bottom-right \
    --colourBarSize 60.0 --labelSize 12 --performance 3 \
    "${TEMPLATE}" --name "MNI152_T1_1mm" \
    --overlayType volume --alpha 100.0 --brightness 49.75 --contrast 49.9 \
    --cmap greyscale --negativeCmap greyscale \
    --displayRange 0.0 10000.0 --clippingRange 0.0 10000.0 \
    --cmapResolution 256 --interpolation none --numSteps 150 --blendFactor 0.1 \
    --smoothing 0 --resolution 100 --numInnerSteps 10 --clipMode intersection --volume 0 \
    "${OVERLAY_SUM}" --name "lesion_frequency_map" \
    --overlayType volume --alpha 100.0 --brightness 50.0 --contrast 50.0 \
    --cmap hot --unlinkLowRanges \
    --displayRange 1.0 ${max_freq} --clippingRange 1.0 ${max_freq} --gamma 0.0 \
    --cmapResolution 256 --interpolation none --numSteps 150 --blendFactor 0.1 \
    --smoothing 0 --resolution 100 --numInnerSteps 10 --clipMode intersection --volume 0

echo ""
echo "Overlay image saved to: ${OVERLAY_PNG}"

# ============================================================================
# Summary
# ============================================================================

echo ""
echo "============================================================================"
echo "COMPLETE!"
echo "============================================================================"
echo "Lesion volumes: ${VOLUME_CSV}"
echo "Frequency map:  ${OVERLAY_SUM}"
echo "Overlay image:  ${OVERLAY_PNG}"
echo "Selection log:  ${OVERLAY_SELECTION_LOG}"
echo "Number of subjects included: ${#mni_masks_to_use[@]}"
echo "Maximum overlap: ${max_freq_int} subjects"
echo "============================================================================"