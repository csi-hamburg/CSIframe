# Convert FLAIR miss file
awk -F'/' '{
    # Extract subject ID from field 3
    sub(/ .*/, "", $3);  # Remove everything after space
    gsub(/_/, "-", $3);  # Replace _ with -
    sub(/-/, "_", $3);   # But keep first _ (0679_117-036)
    
    # Keep only 0679_XXX-XXX (remove everything after third segment)
    match($3, /0679_[0-9]+-[0-9]+/);
    $3 = substr($3, RSTART, RLENGTH);
    
    # Extract visit and lowercase it
    visit = tolower($4);
    
    print $3, visit
}' ~/Downloads/elan_seg_flair_miss.txt | sort -u > output/missing/flair_miss_formatted.txt

# Convert T1 miss file  
awk -F'/' '{
    sub(/ .*/, "", $3);
    gsub(/_/, "-", $3);
    sub(/-/, "_", $3);
    match($3, /0679_[0-9]+-[0-9]+/);
    $3 = substr($3, RSTART, RLENGTH);
    visit = tolower($4);
    print $3, visit
}' ~/Downloads/elan_seg_t1_miss.txt | sort -u > output/missing/t1_miss_formatted.txt

# Show first few lines to verify
echo "FLAIR formatted:"
head -20 output/missing/flair_miss_formatted.txt
echo -e "\nT1 formatted:"
head -20 output/missing/t1_miss_formatted.txt


# Find subjects missing both FLAIR and T1
comm -12 output/missing/flair_miss_formatted.txt output/missing/t1_miss_formatted.txt > output/missing/both_missing.txt

# Find subjects in both_missing but NOT in missing_anatomical_sorted.txt
echo "subjects in both_missing but NOT in missing_anatomical_sorted.txt: "
comm -23 output/missing/both_missing.txt <(sort data/raw_bids/derivatives/lesion_masks_mni/logs/missing_anatomical_sorted.txt) | wc -l
