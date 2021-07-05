#!/usr/bin/env python
# -*- coding: utf-8 -*-
# emacs: -*- mode: python; py-indent-offset: 4; indent-tabs-mode: nil -*-
# vi: set ft=python sts=4 ts=4 sw=4 et:

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import os.path as op
from argparse import ArgumentParser
from argparse import RawTextHelpFormatter
import nibabel as nb
import numpy as np

def main():
    parser = ArgumentParser(description='Normalize ICBM152 atlases',
                            formatter_class=RawTextHelpFormatter)

    parser.add_argument('input_file', help='input file')
    parser.add_argument('output_file', help='output file')

    args = parser.parse_args()

    im = nb.load(args.input_file)
    data = im.get_data()
    
    data -= data.min()
    data /= data.max() / 1e4

    hdr = im.get_header().copy()
    hdr.set_data_dtype(np.float32)
    nb.Nifti1Image(data.astype(np.float32), im.get_affine(), hdr).to_filename(args.output_file)

if __name__ == '__main__':
    main()

