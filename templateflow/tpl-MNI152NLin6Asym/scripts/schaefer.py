from argparse import ArgumentParser, RawTextHelpFormatter
from pathlib import Path
import pandas as pd


def main():
    parser = ArgumentParser(description='Curates Schaefer 2018 atlas metadata tables',
                            formatter_class=RawTextHelpFormatter)
    parser.add_argument('input_file', type=Path, action='store', help='input file')
    args = parser.parse_args()
    
    data = pd.read_csv(args.input_file, delimiter='\s+', index_col=0, usecols=[0, 1, 2, 3, 4], header=None)
    out_desc = ''.join(str(args.input_file).split('_')[1:3])
    data.index.name = 'index'
    data['color'] = data.apply(lambda row: '#%02x%02x%02x' % tuple(row[1:]), axis=1)
    data.rename(columns={1: 'name'}, inplace=True)
    data[['name', 'color']].to_csv(f'tpl-MNI152NLin6Asym_atlas-Schaefer2018_desc-{out_desc}_dseg.tsv', sep='\t')
    print(f'Written "tpl-MNI152NLin6Asym_atlas-Schaefer2018_desc-{out_desc}_dseg.tsv"')

if __name__ == '__main__':
    main()

