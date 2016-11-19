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

if [ ! -f ${chkpt}/.MFCCPitch ]; then
    # MAKE SRE08 AND SRE10 FEATS
    utils/copy_data_dir.sh data/${gen}/allfolds data/${gen}/allfolds_pitch_temp || exit 1;
    steps/make_mfcc_pitch.sh  --compress false --nj 30 --mfcc-config conf/mfcc.conf \
      --pitch-config conf/pitch.conf --cmd "$train_cmd" \
      data/${gen}/allfolds_pitch_temp ${mfccpitchdir}/log $mfccpitchdir || exit 1;
    steps/compute_cmvn_stats.sh data/$gen/allfolds_pitch_temp ${mfccpitchdir}/log_cmvn $mfccpitchdir || exit 1;
    utils/subset_data_dir.sh --utt-list data/$gen/allfolds_pitch_temp/feats.scp data/$gen/allfolds_pitch_temp data/$gen/allfolds_pitch
    utils/fix_data_dir.sh data/${gen}/allfolds_pitch || exit 1;

    utils/copy_data_dir.sh data/${gen}/allfolds_pitch data/${gen}/allfolds || exit 1;
    steps/select_feats.sh  --nj 30 \
      --cmd "$train_cmd" 0-19 data/${gen}/allfolds_pitch data/${gen}/allfolds \
      ${mfccdir}/log $mfccdir || exit 1;
    steps/compute_cmvn_stats.sh data/$gen/allfolds ${mfccdir}/log_cmvn $mfccdir || exit 1;
    utils/fix_data_dir.sh data/$gen/allfolds || exit 1;

    touch ${chkpt}/.MFCCPitch
fi

if [ ! -f ${chkpt}/.VAD ]; then

    sid/compute_vad_decision.sh --nj 40 --cmd "$train_cmd" \
      data/${gen}/allfolds_pitch ${vaddir} $vaddir || exit 1;

    utils/fix_data_dir.sh data/${gen}/allfolds_pitch

    sid/compute_vad_decision.sh --nj 40 --cmd "$train_cmd" \
      data/${gen}/allfolds ${vaddir} $vaddir || exit 1;

    utils/fix_data_dir.sh data/${gen}/allfolds

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
    utils/fix_data_dir.sh data/${gen}/allfolds || exit 1;
    cp data/${gen}/allfolds/lab*  data/${gen}/allfolds_pitch/
    touch ${chkpt}/.SPKR_CLUSTERS
fi
}

if [ ! -f ${chkpt}/.AGE_CLUSTERS ]; then
    if [ ! -f data/${gen}/allfolds/feats_len.txt ] ; then
        feat-to-len scp:data/${gen}/allfolds/feats.scp ark,t:data/${gen}/allfolds/feats_len.txt || exit 1;
    fi
    awk '{ print $2 }' data/${gen}/allfolds/utt2spk |paste -d " " data/${gen}/allfolds/feats_len.txt - | awk '{ print $1" "$3" "$2" " }' > data/${gen}/allfolds/utt2spk2len || exit 1;
    python local/make_ageclusters.py $PWD $gen

    [ ! -d arks/labels ] && mkdir -p arks/labels;
    cat data/${gen}/allfolds/lab_age.txt | copy-feats ark:- ark,scp:$PWD/arks/labels/lab_${gen}_age.ark,$PWD/data/${gen}/allfolds/lab_age.scp || exit 1;
    utils/fix_data_dir.sh data/${gen}/allfolds || exit 1;
    cp data/${gen}/allfolds/age2* data/${gen}/allfolds_pitch
    cp data/${gen}/allfolds/lab* data/${gen}/allfolds_pitch
    utils/fix_data_dir.sh data/${gen}/allfolds_pitch || exit 1;

    touch ${chkpt}/.AGE_CLUSTERS
fi
