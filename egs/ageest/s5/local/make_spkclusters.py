
import os, sys

def FindMinAndMaxAge( s2a_list ):
    minage = 100
    maxage = 0
    for each_s2a in s2a_list:
        age = int(each_s2a.split()[1])
        if age < minage:
            minage = age
        if age > maxage:
            maxage = age
    return minage, maxage
 
def CreateSpkClusters( s2a, minage, maxage ):
    cluster_up_lim = 25
    cluster_low_lim = 20
    cluster_dict = {}
    cluster_num = 1
    #while ( cluster_up_lim - int(maxage) < 6 ):
    while ( cluster_up_lim - 65 < 6 ):
        for age in xrange( cluster_low_lim, cluster_up_lim+1 ):
            cluster_dict[age] = cluster_num
        cluster_up_lim += 5
        cluster_low_lim += 5
        cluster_num += 1 
    return [cluster_dict, cluster_num-1]

def Cluster2String( cluster_dict, num_clusters ):
    cluster_to_str = {}
    for key in cluster_dict.keys():
        cluster = cluster_dict[key]
        if cluster not in cluster_to_str:
            x=''
            for i in xrange(1,num_clusters+1):
                if  i == cluster:
                    x = x +'1 '
                else:
                    x = x +'0 '
            x = x[:-1]
            cluster_to_str[cluster] = x

    #print cluster_to_str
    return cluster_to_str

def CreateSpk2AgeDict(s2a):
    s2a_dict = {}
    for s_a in s2a:
        spk = s_a.split()[0]
        age = s_a.split()[1]
        if spk not in s2a_dict:
            s2a_dict[spk] = age 

    return s2a_dict

def CreateLabelFile( u2s2l, s2a_dict, cluster_dict, labfile, cluster_to_str ):

    for each_line in u2s2l:
        parts = each_line.split()
        utt = parts[0]
        spk = parts[1]
        length = int(parts[2])
        age = s2a_dict[spk]
    
        labfile.write('{0} [\n'.format(utt))
        labfile.write( ('    '+cluster_to_str[cluster_dict[int(age)]]+'\n') * (length-1) )
        labfile.write( ('    '+cluster_to_str[cluster_dict[int(age)]] +' ]'+'\n') )
  
def Main():
    exp_dir = sys.argv[1]
    mode = sys.argv[2]
    
    with open( '{0}/data/{1}/allfolds/spk2age'.format( exp_dir, mode ) ) as f:
        s2a = f.read().splitlines()
    
    with open( '{0}/data/{1}/allfolds/utt2spk2len'.format( exp_dir, mode ) ) as f:
        u2s2l = f.read().splitlines()
    labfile = open('{0}/data/{1}/allfolds/lab_spkcluster.txt'.format( exp_dir, mode ), 'w')
    ageclustersfile = open('{0}/data/{1}/allfolds/age2cluster'.format( exp_dir, mode ), 'w')

    # START DOING STUFF
    [ minage, maxage ] = FindMinAndMaxAge(s2a)
    #print minage, maxage
    s2a_dict = CreateSpk2AgeDict(s2a)
    [ cluster_dict, num_clusters ] = CreateSpkClusters(s2a, 30, maxage) 
    #[ cluster_dict, num_clusters ] = CreateSpkClusters(s2a, minage, maxage) 
    
    for key in cluster_dict.keys():
        ageclustersfile.write(str(key)+' '+str(cluster_dict[key])+'\n')
    ageclustersfile.close()
    cluster_to_str = Cluster2String( cluster_dict, num_clusters )
    CreateLabelFile( u2s2l, s2a_dict, cluster_dict, labfile, cluster_to_str )
    labfile.close()
       
if __name__ == '__main__':
    Main()
