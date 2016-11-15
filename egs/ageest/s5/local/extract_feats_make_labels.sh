#!/bin/bash
# Copyright 2015   David Snyder
#           2015   Johns Hopkins University (Author: Daniel Garcia-Romero)
#           2015   Johns Hopkins University (Author: Daniel Povey)
# Apache 2.0.
#
# See README.txt for more info on data required.
# Results (EERs) are inline in comments below.

if [ $# -ne 1 ]; then
    echo USAGE $0 'female' or 'male'
    exit 1;
fi

gen=$1

set -e
mfccdir=`pwd`/arks/mfcc/${gen}
mfccpitchdir=`pwd`/arks/mfccpitch/${gen}
vaddir=`pwd`/arks/vad/${gen}
ivecdir=`pwd`/arks/ivec/${gen}
num_components=2048 # Larger than this doesn't make much of a difference.
ivecdim=400

data=`pwd`/data/nist040506_swbd
exp=`pwd`/exp/${gen}

chkpt=data/${gen}/CHKPTS
[ ! -d $chkpt ] && mkdir -p $chkpt;

# Prepare a collection of NIST SRE data prior to 2008. This is
# used to train the PLDA model, UBM and ivector training
if [ ! -f ${chkpt}/.MakeData ]; then
    # MAKE SRE DATA
    local/make_sre.sh ${data}

    # Prepare SWB for UBM and i-vector extractor training.
    local/make_swbd2_phase2.pl /export/corpora5/LDC/LDC99S79 \
                           ${data}/swbd2_phase2_train
    local/make_swbd2_phase3.pl /export/corpora5/LDC/LDC2002S06 \
                           ${data}/swbd2_phase3_train
    local/make_swbd_cellular1.pl /export/corpora5/LDC/LDC2001S13 \
                             ${data}/swbd_cellular1_train
    local/make_swbd_cellular2.pl /export/corpora5/LDC/LDC2004S07 \
                             ${data}/swbd_cellular2_train
   
    for dir in sre swbd2_phase2_train swbd2_phase3_train swbd_cellular1_train swbd_cellular2_train ; do 
        awk ' $2 == "f" {print $1}'  ${data}/${dir}/spk2gender > ${data}/${dir}/spk_female
        utils/subset_data_dir.sh --spk-list ${data}/${dir}/spk_female ${data}/${dir} ${data}/${dir}_female || exit 1;
        awk ' $2 == "m" {print $1}'  ${data}/${dir}/spk2gender > ${data}/${dir}/spk_male
        utils/subset_data_dir.sh --spk-list ${data}/${dir}/spk_male ${data}/${dir} ${data}/${dir}_male || exit 1;
        rm ${data}/${dir}/spk_*male
    done

    utils/combine_data.sh ${data}/swbd_sre_female \
      ${data}/swbd_cellular1_train_female ${data}/swbd_cellular2_train_female \
      ${data}/swbd2_phase2_train_female ${data}/swbd2_phase3_train_female ${data}/sre_female || exit 1;

    utils/combine_data.sh ${data}/swbd_sre_male \
      ${data}/swbd_cellular1_train_male ${data}/swbd_cellular2_train_male \
      ${data}/swbd2_phase2_train_male ${data}/swbd2_phase3_train_male ${data}/sre_male || exit 1;
    touch ${chkpt}/.MakeData
fi

if [ ! -f ${chkpt}/.MFCCPitch ]; then
    # MAKE SWBD AND SRE FEATS
    utils/copy_data_dir.sh $data/swbd_sre_${gen} $data/swbd_sre_${gen}_pitch || exit 1;
    steps/make_mfcc_pitch.sh --compress false --mfcc-config conf/mfcc.conf --pitch-config conf/pitch.conf --nj 30 --cmd "$train_cmd" \
      ${data}/swbd_sre_${gen}_pitch ${mfccpitchdir}/log $mfccpitchdir || exit 1;
    steps/compute_cmvn_stats.sh ${data}/swbd_sre_${gen}_pitch ${mfccpitchdir}/log $mfccpitchdir || exit 1;
    utils/fix_data_dir.sh ${data}/swbd_sre_${gen}_pitch || exit 1;

    steps/select_feats.sh  --nj 30 \
      --cmd "$train_cmd" 0-19 $data/swbd_sre_${gen}_pitch $data/swbd_sre_${gen} \
      ${mfccdir}/log $mfccdir || exit 1;
    steps/compute_cmvn_stats.sh $data/swbd_sre_$gen ${mfccdir}/log_cmvn $mfccdir || exit 1;

    utils/fix_data_dir.sh ${data}/swbd_sre_${gen} || exit 1;
    # MAKE SRE08 AND SRE10 FEATS
    utils/copy_data_dir.sh data/${gen}/allfolds data/${gen}/allfolds_pitch || exit 1;
    steps/make_mfcc_pitch.sh  --compress false --nj 30 --mfcc-config conf/mfcc.conf \
      --pitch-config conf/pitch.conf --cmd "$train_cmd" \
      data/${gen}/allfolds_pitch ${mfccpitchdir}/log $mfccpitchdir || exit 1;
    steps/compute_cmvn_stats.sh data/$gen/allfolds_pitch ${mfccpitchdir}/log_cmvn $mfccpitchdir || exit 1;
    utils/fix_data_dir.sh data/${gen}/allfolds_pitch || exit 1;

    utils/copy_data_dir.sh data/${gen}/allfolds_pitch data/${gen}/allfolds || exit 1;
    steps/select_feats.sh  --nj 30 \
      --cmd "$train_cmd" 0-19 data/${gen}/allfolds_pitch data/${gen}/allfolds \
      ${mfccdir}/log $mfccdir || exit 1;
    steps/compute_cmvn_stats.sh data/$gen/allfolds ${mfccdir}/log_cmvn $mfccdir || exit 1;

    utils/fix_data_dir.sh data/$gen/allfolds || exit 1;

    # MAKE SRE FEATS
    utils/copy_data_dir.sh $data/sre_${gen} $data/sre_${gen}_pitch || exit 1;
    steps/make_mfcc_pitch.sh --compress false --mfcc-config conf/mfcc.conf --pitch-config conf/pitch.conf --nj 30 --cmd "$train_cmd" \
      ${data}/sre_${gen}_pitch ${mfccpitchdir}/log $mfccpitchdir || exit 1;
    steps/compute_cmvn_stats.sh ${data}/sre_${gen}_pitch ${mfccpitchdir}/log $mfccpitchdir || exit 1;
    utils/fix_data_dir.sh ${data}/sre_${gen}_pitch || exit 1;

    steps/select_feats.sh  --nj 30 \
      --cmd "$train_cmd" 0-19 $data/sre_${gen}_pitch $data/sre_${gen} \
      ${mfccdir}/log $mfccdir || exit 1;
    steps/compute_cmvn_stats.sh $data/sre_$gen ${mfccdir}/log_cmvn $mfccdir || exit 1;

    utils/fix_data_dir.sh ${data}/sre_${gen} || exit 1;
    touch ${chkpt}/.MFCCPitch
fi

if [ ! -f ${chkpt}/.VAD ]; then
    sid/compute_vad_decision.sh --nj 40 --cmd "$train_cmd" \
      ${data}/swbd_sre_${gen} ${vaddir}/log $vaddir || exit 1;

    sid/compute_vad_decision.sh --nj 40 --cmd "$train_cmd" \
      ${data}/sre_${gen} ${vaddir}/log $vaddir || exit 1;

    sid/compute_vad_decision.sh --nj 40 --cmd "$train_cmd" \
      data/${gen}/allfolds ${vaddir} $vaddir || exit 1;

    for name in sre_${gen} swbd_sre_${gen}; do
      utils/fix_data_dir.sh ${data}/${name}
    done

    utils/fix_data_dir.sh data/${gen}/allfolds

    cp data/${gen}/allfolds/vad.scp data/${gen}/allfolds_pitch/
    touch ${chkpt}/.VAD
fi

false && {
if [ ! -f ${chkpt}/.SPKR_CLUSTERS ]; then

    if [ ! -f data/${gen}/allfolds/feats_len.txt ] ; then
        feat-to-len scp:data/${gen}/allfolds/feats.scp ark,t:data/${gen}/allfolds/feats_len.txt || exit 1;
    fi
    awk '{ print $2 }' data/${gen}/allfolds/utt2spk |paste -d " " data/${gen}/allfolds/feats_len.txt - | awk '{ print $1" "$3" "$2" " }' > data/${gen}/allfolds/utt2spk2len || exit 1;
    python local/make_spkclusters.py $pwd $gen

    [ ! -d arks/labels ] && mkdir -p arks/labels;
    cat data/${gen}/allfolds/lab_spkcluster.txt | copy-feats ark:- ark,scp:$PWD/arks/labels/lab_${gen}_spkcluster.ark,$PWD/data/${gen}/allfolds/lab_spkcluster.scp || exit 1;
    utils/my_fix_data_dir.sh data/${gen}/allfolds || exit 1;
    cp data/${gen}/allfolds/lab*  data/${gen}/allfolds_pitch/
    touch ${chkpt}/.SPKR_CLUSTERS
fi
}

if [ ! -f ${chkpt}/.AGE_CLUSTERS ]; then
    if [ ! -f data/${gen}/allfolds/feats_len.txt ] ; then
        feat-to-len scp:data/${gen}/allfolds/feats.scp ark,t:data/${gen}/allfolds/feats_len.txt || exit 1;
    fi
    awk '{ print $2 }' data/${gen}/allfolds/utt2spk |paste -d " " data/${gen}/allfolds/feats_len.txt - | awk '{ print $1" "$3" "$2" " }' > data/${gen}/allfolds/utt2spk2len || exit 1;
    python local/make_ageclusters.py $pwd $gen

    [ ! -d arks/labels ] && mkdir -p arks/labels;
    cat data/${gen}/allfolds/lab_age.txt | copy-feats ark:- ark,scp:$PWD/arks/labels/lab_${gen}_age.ark,$PWD/data/${gen}/allfolds/lab_age.scp || exit 1;
    utils/my_fix_data_dir.sh data/${gen}/allfolds || exit 1;
    cp data/${gen}/allfolds/age2* data/${gen}/allfolds_pitch
    touch ${chkpt}/.AGE_CLUSTERS
fi

