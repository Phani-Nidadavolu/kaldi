#!/bin/bash

# Anna's list path = fromAnna/female_lists
# modified list path = fromAnna/female_lists_modified

# Anna's age list = fromAnna/age_list.txt
# modified age list = fromAnna/age_list_modified.txt
# In Anna's list thmgs-b appears in two lists 1 and 15, I deleted them in list 15, I also deleted it in fromAnna/srcdata/female10.txt and saved the new file in fromAnna/srcdata_modified/female10.txt
# In Anns's list tkbox-a apperas in two lists 2 and 15, I deleted them in list 2, I also delted it in fromAnna/srcdata/female10.txt and saved the new file in fromAnna/srcdata_modified/female10.txt
# In Anna's lists we don't have sph file for utterance tacho-b in path /export/corpora5/SRE/SRE2010/eval. Hence, I deleted it from list7. I also delted it in fromAnna/srcdata/female10.txt and saved the new file in fromAnna/srcdata_modified/female10.txt


gen=female

srcdir=/home/snidada1/ageest_lists/fromAnna
desdir=`pwd`/data/${gen}

sphdir1=/export/corpora5/SRE/SRE2010/eval
sphdir2=/export/corpora5/LDC/LDC2011S08
sphdir3=/export/corpora5/LDC/LDC2011S05

[ ! -d ${desdir}/allfolds ] && mkdir -p ${desdir}/allfolds;

cat ${srcdir}/srcdata_modified/${gen}* | awk '{print $2"-"$1" "$2}' | sort -u > ${desdir}/allfolds/utt2spk
cat ${srcdir}/srcdata_modified/${gen}* | awk '{print $2"-"$1" "$3}' | sort -u > ${desdir}/allfolds/utt2age
cat ${srcdir}/srcdata_modified/${gen}* | awk '{print $2" "$3}' | sort -u > ${desdir}/allfolds/spk2age

utils/utt2spk_to_spk2utt.pl ${desdir}/allfolds/utt2spk > ${desdir}/allfolds/spk2utt
utils/utt2age_to_age2utt.pl ${desdir}/allfolds/utt2age | sort -u > ${desdir}/allfolds/age2utt
utils/spk2age_to_age2spk.pl ${desdir}/allfolds/spk2age | sort -u > ${desdir}/allfolds/age2spk

cat ${desdir}/allfolds/utt2spk | cut -d " " -f1 | cut -d "-" -f2- | while read line; do
    x=`awk -F"=" -v utt=${line}.fea ' $1 == utt { print $2} ' ${srcdir}/age_list_modified.txt | cut -d "/" -f1`
    echo $line $x
done > ${srcdir}/srcdata_modified/utt2dataset_${gen}

cat ${desdir}/allfolds/utt2spk | cut -d " " -f1 | while read line; do
    utt=`echo $line | cut -d "-" -f2`
    chn=`echo $line | awk -F"-" '{print $NF}'`
    if  [ $chn == 'a' ]; then
        chn_int=1
    elif [ $chn == 'b' ]; then
        chn_int=2
    fi

    dataset=`awk -v u="${utt}-${chn}" ' $1 == u {print $2}' ${srcdir}/srcdata_modified/utt2dataset_${gen}`
    if [ $dataset == "nist-sre-train2008" ] ; then
        echo ${line} ${chn_int} `find ${sphdir3}/ -name ${utt}.sph`
    elif [ $dataset == "nist-sre-test2008" ] ; then
        echo ${line} ${chn_int} `find ${sphdir2}/ -name ${utt}.sph`
    elif [ $dataset == "nist-sre-all2010" ] ; then
        echo ${line} ${chn_int} `find ${sphdir1}/ -name ${utt}.sph`
    fi
done > ${srcdir}/${gen}_utt2sph 

#100396-m-sre2008-fkffz-A sph2pipe -f wav -p -c 1 /export/corpora5/LDC/LDC2011S08/data/test/data/short3/fkffz.sph |

awk '{ print $1" sph2pipe -f wav -p -c "$2" "$3" |" }' ${srcdir}/${gen}_utt2sph > ${desdir}/allfolds/wav.scp
utils/fix_data_dir.sh ${desdir}/allfolds || exit 1;
utils/validate_data_dir.sh --no-text --no-feats ${desdir}/allfolds || exit 1;

