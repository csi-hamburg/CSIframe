#!/usr/bin/env python3
import os

# create a function called create_key
def create_key(template, outtype=('nii.gz',), annotation_classes=None):
    if template is None or not template:
        raise ValueError('Template must be a valid format string')
    return template, outtype, annotation_classes


def infotodict(seqinfo):
    # Section 1: These key definitions should be revised by the user
    ###################################################################
    # For each sequence, define a key and template using the create_key function:
    # key = create_key(output_directory_path_and_name).
    #
    # The "data" key creates sequential numbers which can be for naming sequences.
    # This is especially valuable if you run the same sequence multiple times at the scanner.

    t1w = create_key('sub-{subject}/{session}/anat/sub-{subject}_{session}_T1w')
    flair = create_key('sub-{subject}/{session}/anat/sub-{subject}_{session}_FLAIR')
    dwi = create_key('sub-{subject}/{session}/dwi/sub-{subject}_{session}_acq-AP_dwi')
    func_rest = create_key('sub-{subject}/{session}/func/sub-{subject}_{session}_task-rest_bold')
    dsc = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_dsc')
    tof = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_tof')

    control_asl_03 = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_run-01_asl')
    label_asl_03 = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_run-02_asl')
    control_asl_06 = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_run-03_asl')
    label_asl_06 = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_run-04_asl')
    control_asl_09 = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_run-05_asl')
    label_asl_09 = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_run-06_asl')
    control_asl_12 = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_run-07_asl')
    label_asl_12 = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_run-08_asl')
    control_asl_15 = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_run-09_asl')
    label_asl_15 = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_run-10_asl')
    control_asl_18 = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_run-11_asl')
    label_asl_18 = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_run-12_asl')
    control_asl_21 = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_run-13_asl')
    label_asl_21 = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_run-14_asl')
    control_asl_24 = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_run-15_asl')
    label_asl_24 = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_run-16_asl')
    control_asl_27 = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_run-17_asl')
    label_asl_27 = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_run-18_asl')
    control_asl_30 = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_run-19_asl')
    label_asl_30 = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_run-20_asl')
    m0scan_17 = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_run-01_m0scan')
    m0scan_34 = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_run-02_m0scan')


    # Section 1b: This data dictionary (below) should be revised by the user.
    # It uses the variables defined above as keys.
    ##########################################################################
    # Enter a key in the dictionary for each key you created above in section 1.
    info = {t1w: [], flair: [], dwi: [], func_rest: [], dsc: [], tof: [], label_asl_03: [], control_asl_03: [], label_asl_06: [], control_asl_06: [], label_asl_09: [], \
        control_asl_09: [], label_asl_12: [], control_asl_12: [], label_asl_15: [], control_asl_15: [], label_asl_18: [], control_asl_18: [], \
            label_asl_21: [], control_asl_21: [], label_asl_24: [], control_asl_24: [], label_asl_27: [], control_asl_27: [], label_asl_30: [], \
                control_asl_30: [], m0scan_17: [], m0scan_34: []} 
    last_run = len(seqinfo)

    # Section 2: These criteria should be revised by user.
    ##########################################################
    # Define test criteria to check that each dicom sequence is correct
    # seqinfo (s) refers to information in dicominfo.tsv. Consult that file for
    # available criteria.
    # Here we use two types of criteria:
    # 1) An equivalent field "==" (e.g., good for checking dimensions)
    # 2) A field that includes a string (e.g., 'mprage' in s.protocol_name)
    for idx, s in enumerate(seqinfo):
        if ('t1_mprage_cor_p2_iso_0.9_ND' == s.series_description):
            info[t1w].append(s.series_id)
        if ('t2_tirm_tra_dark-fluid' == s.series_description):
            info[flair].append(s.series_id)
        if ('ep2d_diff_tra_DTI_64no72_p2_monopolar_ORIG' == s.series_description):
            info[dwi].append(s.series_id)
        if ('ep2d_bold_moco_p2_restingstate' == s.series_description):
            info[func_rest].append(s.series_id)
        if ('ep2d_perf_p2_Flow4' == s.series_description):
            info[dsc].append(s.series_id)
        if ('TOF_3D_tra_multi-slab' == s.series_description):
            info[tof].append(s.series_id)
        if ('ss_TE00_TI0300' == s.series_description):
            info[control_asl_03].append(s.series_id)
        if ('ns_TE00_TI0300' == s.series_description):
            info[label_asl_03].append(s.series_id)
        if ('ss_TE00_TI0600' == s.series_description):
            info[control_asl_06].append(s.series_id)
        if ('ns_TE00_TI0600' == s.series_description):
            info[label_asl_06].append(s.series_id)
        if ('ss_TE00_TI0900' == s.series_description):
            info[control_asl_09].append(s.series_id)
        if ('ns_TE00_TI0900' == s.series_description):
            info[label_asl_09].append(s.series_id)
        if ('ss_TE00_TI1200' == s.series_description):
            info[control_asl_12].append(s.series_id)
        if ('ns_TE00_TI1200' == s.series_description):
            info[label_asl_12].append(s.series_id)
        if ('ss_TE00_TI1500' == s.series_description):
            info[control_asl_15].append(s.series_id)
        if ('ns_TE00_TI1500' == s.series_description):
            info[label_asl_15].append(s.series_id)
        if ('ss_TE00_TI1800' == s.series_description):
            info[control_asl_18].append(s.series_id)
        if ('ns_TE00_TI1800' == s.series_description):
            info[label_asl_18].append(s.series_id)
        if ('ss_TE00_TI2100' == s.series_description):
            info[control_asl_21].append(s.series_id)
        if ('ns_TE00_TI2100' == s.series_description):
            info[label_asl_21].append(s.series_id)
        if ('ss_TE00_TI2400' == s.series_description):
            info[control_asl_24].append(s.series_id)
        if ('ns_TE00_TI2400' == s.series_description):
            info[label_asl_24].append(s.series_id)
        if ('ss_TE00_TI2700' == s.series_description):
            info[control_asl_27].append(s.series_id)
        if ('ns_TE00_TI2700' == s.series_description):
            info[label_asl_27].append(s.series_id)
        if ('ss_TE00_TI3000' == s.series_description):
            info[control_asl_30].append(s.series_id)
        if ('ns_TE00_TI3000' == s.series_description):
            info[label_asl_30].append(s.series_id)
        if ('ss_TE00_TI0300' == s.series_description):
            info[control_asl_03].append(s.series_id)
        if ('ss_TE00_TI1700' == s.series_description):
            info[m0scan_17].append(s.series_id)
        if ('ss_TE00_TI3400' == s.series_description):
            info[m0scan_34].append(s.series_id)
    return info
