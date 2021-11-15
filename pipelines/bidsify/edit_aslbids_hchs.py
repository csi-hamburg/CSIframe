#!/usr/bin/env python
# -*- coding: utf-8 -*-
# emacs: -*- mode: python; py-indent-offset: 4; indent-tabs-mode: nil -*-
# vi: set ft=python sts=4 ts=4 sw=4 et:
import warnings
warnings.filterwarnings("ignore")
from argparse import (ArgumentParser, RawTextHelpFormatter)
import json,os,pathlib
import numpy as np
import nibabel as nib
import pandas as pd 
import glob as glob 

def get_parser():

    parser = ArgumentParser(
        formatter_class=RawTextHelpFormatter,
        description='Edit asl bids'
                    )
    parser.add_argument(
        '-s', '--subject_id', action='store', required=True,
        help='[required]'
             '\n subject id with sub-, e.g sub-01 .')
    parser.add_argument(
        '-t', '--session_id', action='store', required=False,
        help='[optional]'
             '\n session id with ses-, e.g ses-01.'),
    parser.add_argument(
        '-b', '--bids_dir', action='store', required=True,
        help='[required]'
             '\n bids directory.')
    parser.add_argument(
        '-j', '--jsontemplate', action='store', required=True,
        help='[required]'
             '\n json template with metadata')
    return parser

opts = get_parser().parse_args()

subject_id=opts.subject_id
bids_dir=opts.bids_dir
jsontemp=opts.jsontemplate

if opts.session_id:
    session_id=opts.session_id
else:
    session_id=''

print (session_id)

def readjson(jsonfile):
    with open(jsonfile) as f:
        data = json.load(f)
    return data

def writejson(jdict,outfile): 
    with open(outfile, 'w+') as outfile:
        json.dump(jdict, outfile, indent = 4, sort_keys=True)
    return outfile

def merge_two_dicts(x, y):
    z = x.copy()   # start with x's keys and values
    z.update(y)    # modifies z with y's keys and values & returns None
    return z

# read the json file with asl and Mzeroscan metadata extra 
jsontemp=readjson(jsontemp)

#change to subjectid directory 
os.chdir(bids_dir+'/'+subject_id)

# get the asl and mzeroscan 
asl=glob.glob(session_id+'/perf/'+subject_id+'*_asl.nii.gz')
asl_j=glob.glob(session_id+'/perf/'+subject_id+'*_asl.json')
m0=glob.glob(session_id+'/perf/'+subject_id+'*_m0scan.nii.gz')
m0_j=glob.glob(session_id+'/perf/'+subject_id+'*_m0scan.json')

# edit json file and write tsv for asl
for i in range(0,len(asl)):
    print(asl[i])
    asl_nj=merge_two_dicts(readjson(asl_j[i]),jsontemp['asl'])
    writejson(asl_nj,asl_j[i])    
    asllist=jsontemp['asllabel']
    df=pd.DataFrame(asllist)
    df.to_csv(os.path.splitext(asl_j[i])[0]+'context.tsv',index=False,sep='\t',header=False)

# create "IntendedFor" dictionary for *m0scan.json
intfor = {"IntendedFor": f"{session_id}/perf/{subject_id}_{session_id}_asl.nii.gz"}

# edit json file and write tsv for m0
for i in range(0,len(m0)):
    m0_nj=merge_two_dicts(readjson(m0_j[i]),jsontemp['m0scan'])
    writejson(m0_nj,m0_j[i])
    m0_nj2=merge_two_dicts(readjson(m0_j[i]),intfor)
    writejson(m0_nj2,m0_j[i])
