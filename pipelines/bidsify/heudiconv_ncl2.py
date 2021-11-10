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

    t1w_1 = create_key('sub-{subject}/{session}/anat/sub-{subject}_{session}_T1w')
    t1w_2 = create_key('sub-{subject}/{session}/anat/sub-{subject}_{session}_T1w')
    t1w_3 = create_key('sub-{subject}/{session}/anat/sub-{subject}_{session}_T1w')
    t1w_4 = create_key('sub-{subject}/{session}/anat/sub-{subject}_{session}_T1w')
    t1w_5 = create_key('sub-{subject}/{session}/anat/sub-{subject}_{session}_T1w')
    t1w_6 = create_key('sub-{subject}/{session}/anat/sub-{subject}_{session}_T1w')

    # t1w_1 = create_key('sub-{subject}/{session}/anat/sub-{subject}_{session}_desc-nssagfast_T1w')
    # t1w_2 = create_key('sub-{subject}/{session}/anat/sub-{subject}_{session}_desc-3dmprage_T1w')
    # t1w_3 = create_key('sub-{subject}/{session}/anat/sub-{subject}_{session}_desc-cssag3d_T1w')
    # t1w_4 = create_key('sub-{subject}/{session}/anat/sub-{subject}_{session}_desc-cssags3d_T1w')
    # t1w_5 = create_key('sub-{subject}/{session}/anat/sub-{subject}_{session}_desc-sag3d_T1w')
    # t1w_6 = create_key('sub-{subject}/{session}/anat/sub-{subject}_{session}_desc-sags3d_T1w')

    # Section 1b: This data dictionary (below) should be revised by the user.
    # It uses the variables defines above as keys.
    ##########################################################################
    # Enter a key in the dictionary for each key you created above in section 1.
    info = {t1w_1: [], t1w_2: [], t1w_3: [], t1w_4: [], t1w_5: [], t1w_6: []} 
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
        #if ('t1_mprage_ns_sag_fast' == s.series_description) or ('3D_T1w_MPRAGE' == s.series_description) or ('CS sag T1W_3D_TFE nativ' == s.series_description) or ('CS sag sT1W_3D_TFE nativ' == s.series_description) ('sag sT1W_3D_TFE nativ' == s.series_description):
        if ('t1_mprage_ns_sag_fast' == s.series_description):
            info[t1w_1].append(s.series_id)
        if ('3D_T1w_MPRAGE' == s.series_description):
            info[t1w_2].append(s.series_id)
        if ('CS sag T1W_3D_TFE nativ' == s.series_description):
            info[t1w_3].append(s.series_id)
        if ('CS sag sT1W_3D_TFE nativ' == s.series_description):
            info[t1w_4].append(s.series_id)
        if ('sag T1W_3D_TFE nativ' == s.series_description):
            info[t1w_5].append(s.series_id)
        if ('sag sT1W_3D_TFE nativ' == s.series_description):
            info[t1w_6].append(s.series_id)
    return info