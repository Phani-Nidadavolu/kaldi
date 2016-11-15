
import os, sys

def CreateUtt2AgeDict(u2a):
    u2a_dict = {}
    for u_a in u2a:
        utt = u_a.split()[0]
        age = u_a.split()[1]
        if utt not in u2a_dict:
            u2a_dict[utt] = age 

    return u2a_dict

def CreateUtt2LenDict(u2l):
    u2l_dict = {}
    for u_l in u2l:
        utt = u_l.split()[0]
        leng = u_l.split()[1]
        if utt not in u2l_dict:
            u2l_dict[utt] = leng 

    return u2l_dict

def Main():
    exp_dir = sys.argv[1]   
    mode = sys.argv[2]
 
    with open( '{0}/data/{1}/allfolds/utt2age'.format( exp_dir, mode ) ) as f:
        u2a = f.read().splitlines()
    
    with open( '{0}/data/{1}/allfolds/feats_len.txt'.format( exp_dir, mode ) ) as f:
        u2l = f.read().splitlines()

    labfile = open('{0}/data/{1}/allfolds/lab_age.txt'.format( exp_dir, mode ), 'w')

    u2a = CreateUtt2AgeDict(u2a)
    u2l = CreateUtt2LenDict(u2l)
    for utt in u2l.keys():
        length = u2l[utt]
        age = u2a[utt]

        labfile.write('{0} [\n'.format(utt))
        labfile.write( ('    '+str(float(age)/1.0)+'\n') * (int(length)-1) )
        labfile.write( ('    '+str(float(age)/1.0)+' ]'+'\n') )

    labfile.close()
       
if __name__ == '__main__':
    Main()
