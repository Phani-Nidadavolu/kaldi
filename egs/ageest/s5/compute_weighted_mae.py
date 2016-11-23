import kaldi_io
import sys
import numpy as np
import os

def compute_mse_feat(inp):
    mse = 0.0
    r = np.shape(inp)[0]
    for i in xrange(0,r)):
        mse = mse + np.sum(inp[i,0:-1])
    
    mse = mse/r    
    return 1.0/mse

def Main():
    error_file = sys.argv[1]

    d = dict((u,d) for u,d in kaldi_io.read_mat_scp(error_file))
    avg_mae = 0.0

    for utt in d:
        weight = compute_mse_feat(d[utt]) 
        avg_mae += weight * np.mean( np.absolute(d[utt]) )
    avg_mae = avg_mae/len(d.keys())

    this_dir = os.path.dirname(error_file)    
    f = open("{0}/RESULTS.txt".format(this_dir),'w')
    f.write(str(avg_mae)+'\n')
    f.close
    print(avg_mae)

if __name__ == '__main__':
    Main()




