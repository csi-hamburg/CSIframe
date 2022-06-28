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
    t2w = create_key('sub-{subject}/{session}/anat/sub-{subject}_{session}_T2w')
    flair = create_key('sub-{subject}/{session}/anat/sub-{subject}_{session}_FLAIR')
    dwi = create_key('sub-{subject}/{session}/dwi/sub-{subject}_{session}_acq-AP_dwi')
    func_rest = create_key('sub-{subject}/{session}/func/sub-{subject}_{session}_task-rest_bold')

    # Section 1b: This data dictionary (below) should be revised by the user.
    # It uses the variables defines above as keys.
    ##########################################################################
    # Enter a key in the dictionary for each key you created above in section 1.
    info = {t1w: [], t2w: [], flair: [], dwi: [], func_rest: []} 
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
        if ('t1_mprage_cor_ND' == s.series_description):
            info[t1w].append(s.series_id)
        if ('t2_space_cor_p4_iso_ND' == s.series_description) or ('t2_tse_tra_ND' == s.series_description):
            info[t2w].append(s.series_id)
        if ('t2_spc_da-fl_sag_ND' == s.series_description):
            info[flair].append(s.series_id)
        if ('ep2d_diff_tra_DTI_DFC' == s.series_description) or ('ep2d_diff_tra_DTI_DFC_MIX' == s.series_description):
            info[dwi].append(s.series_id)
        if ('ep2d_bold_restingstate_tra' == s.series_description):
            info[func_rest].append(s.series_id)
    return info
