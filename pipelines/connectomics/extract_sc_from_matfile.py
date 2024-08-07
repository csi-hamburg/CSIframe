# Helper script that extracts schaefer parcellated structural connectomes from mat files output of qsiprep
# execute from code/ directory: `python pipelines/connectomics/extract_sc_from_matfile.py`
# with a python environment containing the following packages:

from pathlib import Path
import sys
import pandas as pd
from scipy.io import loadmat

project_dir = Path("../")
qsirecon_dir = Path(project_dir/"data/qsirecon")
output_dir = Path(project_dir/"data/connectomics/derivatives/extracted_connectomes")

for idx, conn_path in enumerate(qsirecon_dir.glob("*/*/*/*T1w_dhollanderconnectome.mat")):
    sub_id = str(conn_path).split("/")[3]

    print(conn_path)
    print(idx, sub_id)

    try :conn_mat = loadmat(conn_path)
    except ValueError: pass

    for resolution in ["100x7", "100x17", "200x7", "200x17", "400x7", "400x17"]:
        if Path(output_dir/f"{resolution}/{sub_id}_desc-{resolution}_structuralconnectome.csv").exists(): continue
        Path(output_dir/f"{resolution}").mkdir(parents=True, exist_ok=True)
        atlas_df = pd.DataFrame(conn_mat[f"schaefer{resolution}_sift_radius2_count_connectivity"])
        atlas_df.to_csv(output_dir/f"{resolution}/{sub_id}_desc-{resolution}_structuralconnectome.csv", index=False, header=None, sep=" ")

    if Path(output_dir/f"aal116/{sub_id}_desc-aal116_structuralconnectome.csv").exists(): continue
    Path(output_dir/f"aal116").mkdir(parents=True, exist_ok=True)
    atlas_df = pd.DataFrame(conn_mat[f"aal116_sift_radius2_count_connectivity"])
    atlas_df.to_csv(output_dir/f"aal116/{sub_id}_desc-aal116_structuralconnectome.csv", index=False, header=None, sep=" ")
