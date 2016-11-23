
import sys

def Main():
    file = sys.argv[1]    
    min_frames = 1000000
    max_frames = 0
    num_utt = 0
    mean = 0.0

    with open(file) as f:
        lines = f.readlines()
        for line in lines:
            fr = line.split()[-1]
            if int(fr) > max_frames:
                max_frames = int(fr)       
            if int(fr) < min_frames:
                min_frames = int(fr)       
            mean = mean + int(fr)
            num_utt = num_utt + 1

    mean = mean/num_utt
    print("{0} {1} {2}".format(str(min_frames), str(max_frames), str(mean))) 
   
if __name__ ==  "__main__":
    Main()
