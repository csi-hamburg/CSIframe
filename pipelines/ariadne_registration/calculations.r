# Load required libraries
library(tidyverse)

# Read the data
qc_data <- read_csv("data/raw_bids/derivatives/lesion_masks_mni/logs/quality_control_results.csv")

# ============================================================================
# BASIC COUNTS
# ============================================================================

# Total subjects
# Total rows and unique subjects
cat("Total rows:", nrow(qc_data), "\n")
cat("Unique subjects:", n_distinct(qc_data$subject), "\n")
cat("Unique sessions:", n_distinct(qc_data$session), "\n")
cat("Unique runs:", n_distinct(qc_data$run), "\n\n")

# ============================================================================
# LESION MASKS
# ============================================================================

# Subjects where registration was attempted (has lesion mask AND anatomical AND dwi image)
# Take only one row per subject (the first successful registration, or first row if none successful)
registration_attempted <- qc_data %>%
  filter(has_lesion_mask == 1 &
         anatomical_used_for_registration != "none" & 
         dwi_used_for_registration != "none") %>%
  arrange(subject, desc(registration_success)) %>%
  group_by(subject) %>%
  slice(1) %>%
  ungroup()

# Total unique subjects where registration was attempted
total_attempted <- nrow(registration_attempted)

cat("Total unique subjects where registration was attempted:", total_attempted, "\n\n")

# Unique subjects with FLAIR used (contains "FLAIR")
unique_flair_reg <- registration_attempted %>%
  filter(grepl("FLAIR", anatomical_used_for_registration, ignore.case = TRUE)) %>%
  nrow()

# Unique subjects with T1w used (contains "T1w")
unique_t1w_reg <- registration_attempted %>%
  filter(grepl("T1w", anatomical_used_for_registration, ignore.case = TRUE)) %>%
  nrow()

# Unique subjects with dwi or trace used (contains "dwi" or "trace")
unique_dwi_trace_reg <- registration_attempted %>%
  filter(grepl("dwi|trace", dwi_used_for_registration, ignore.case = TRUE)) %>%
  nrow()

# Unique subjects with ADC used (contains "adc")
unique_adc_reg <- registration_attempted %>%
  filter(grepl("adc", dwi_used_for_registration, ignore.case = TRUE)) %>%
  nrow()

cat("Among subjects where registration was attempted (with lesion mask, one row per subject):\n")
cat("Unique subjects with FLAIR used:", unique_flair_reg, "\n")
cat("Unique subjects with T1w used:", unique_t1w_reg, "\n")
cat("Unique subjects with DWI/Trace used:", unique_dwi_trace_reg, "\n")
cat("Unique subjects with ADC used:", unique_adc_reg, "\n")






# Read the lesion volume data
lesion_volumes <- read_csv("data/raw_bids/derivatives/lesion_masks/logs/lesion_volumes.csv")

# Remove zero volumes
lesion_volumes <- lesion_volumes %>%
  filter(volume_mm3 > 0)

# For each subject, check if volumes differ by more than 20%
subject_volumes <- lesion_volumes %>%
  group_by(subject) %>%
  summarise(
    n_volumes = n(),
    min_vol = min(volume_mm3),
    max_vol = max(volume_mm3),
    mean_vol = mean(volume_mm3),
    # Calculate percent difference: (max - min) / min * 100
    pct_diff = ifelse(n_volumes > 1, (max_vol - min_vol) / min_vol * 100, 0),
    # Keep only if single volume OR difference <= 20%
    use_volume = n_volumes == 1 | pct_diff <= 20
  ) %>%
  ungroup()

# Filter to only subjects we can use
valid_subjects <- subject_volumes %>%
  filter(use_volume == TRUE)

# Calculate overall mean lesion volume
mean_lesion_volume <- mean(valid_subjects$mean_vol)
median_lesion_volume <- median(valid_subjects$mean_vol)

cat("Total subjects with lesion volumes:", nrow(subject_volumes), "\n")
cat("Subjects excluded (>20% difference between runs):", sum(!subject_volumes$use_volume), "\n")
cat("Subjects included in analysis:", nrow(valid_subjects), "\n\n")
cat("Mean lesion volume:", round(mean_lesion_volume, 2), "mm³\n")
cat("Median lesion volume:", round(median_lesion_volume, 2), "mm³\n")

# Show excluded subjects
excluded <- subject_volumes %>%
  filter(use_volume == FALSE) %>%
  select(subject, n_volumes, min_vol, max_vol, pct_diff)

if(nrow(excluded) > 0) {
  cat("\nExcluded subjects:\n")
  print(excluded)
}


# Calculate mean, median, and confidence intervals
n <- nrow(valid_subjects)
mean_vol <- mean(valid_subjects$mean_vol)
sd_vol <- sd(valid_subjects$mean_vol)
se_mean <- sd_vol / sqrt(n)

# 95% Confidence Interval for the mean
ci_mean_lower <- mean_vol - qt(0.975, df = n-1) * se_mean
ci_mean_upper <- mean_vol + qt(0.975, df = n-1) * se_mean

# 95% Confidence Interval for the median (bootstrap method)
set.seed(123)
n_bootstrap <- 10000
bootstrap_medians <- replicate(n_bootstrap, {
  sample_data <- sample(valid_subjects$mean_vol, size = n, replace = TRUE)
  median(sample_data)
})

ci_median_lower <- quantile(bootstrap_medians, 0.025)
ci_median_upper <- quantile(bootstrap_medians, 0.975)

# Print results
cat("=== LESION VOLUME SUMMARY ===\n\n")
cat("Sample size (n):", n, "\n\n")

cat("Mean:", round(mean_vol, 2), "mm³ (", round(mean_vol/1000, 2), "ml)\n")
cat("95% CI for mean:", round(ci_mean_lower, 2), "-", round(ci_mean_upper, 2), "mm³\n")
cat("              (", round(ci_mean_lower/1000, 2), "-", round(ci_mean_upper/1000, 2), "ml)\n\n")

cat("Median:", round(median_lesion_volume, 2), "mm³ (", round(median_lesion_volume/1000, 2), "ml)\n")
cat("95% CI for median:", round(ci_median_lower, 2), "-", round(ci_median_upper, 2), "mm³\n")
cat("                 (", round(ci_median_lower/1000, 2), "-", round(ci_median_upper/1000, 2), "ml)\n\n")

cat("Standard deviation:", round(sd_vol, 2), "mm³\n")
cat("Interquartile range (IQR):", 
    round(quantile(valid_subjects$mean_vol, 0.25), 2), "-", 
    round(quantile(valid_subjects$mean_vol, 0.75), 2), "mm³\n")







# Read participants file to get all subjects and extract center info
participants <- read_tsv("data/raw_bids/participants.tsv")

# Extract center from subject ID (the XXX part of sub-XXX-YYY)
all_subjects <- participants %>%
  mutate(center = str_extract(original_id, "(?<=sub-)\\d{3}"))

# Read missing anatomical list
missing_anat <- read_lines("data/raw_bids/derivatives/lesion_masks_mni/logs/missing_anatomical_sorted.txt") %>%
  tibble(line = .) %>%
  separate(line, into = c("old_id", "session"), sep = " ") %>%
  mutate(
    original_id = str_replace(old_id, "0679_", "sub-"),
    center = str_extract(original_id, "\\d{3}(?=-)")
  )

# Calculate per-center statistics
center_missing_stats <- all_subjects %>%
  group_by(center) %>%
  summarise(total_subjects = n()) %>%
  left_join(
    missing_anat %>% 
      distinct(original_id, .keep_all = TRUE) %>%
      count(center, name = "missing_anat"),
    by = "center"
  ) %>%
  mutate(
    missing_anat = replace_na(missing_anat, 0),
    pct_missing_anat = round(missing_anat / total_subjects * 100, 1)
  ) %>%
  arrange(center)

cat("\n=== MISSING ANATOMICAL IMAGES BY CENTER ===\n")
print(center_missing_stats)

# Save to file
write_csv(center_missing_stats, "center_missing_anatomical_stats.csv")
