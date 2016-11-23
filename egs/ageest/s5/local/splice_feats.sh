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
mfccpitchdir_nopostprocess=`pwd`/arks/mfccpitch_nopostprocess/${gen}
vaddir=`pwd`/arks/vad/${gen}
ivecdir=`pwd`/arks/ivec/${gen}
num_components=2048 # Larger than this doesn't make much of a difference.
ivecdim=400

data=`pwd`/data/nist040506_swbd
exp=`pwd`/exp/${gen}

chkpt=data/${gen}/CHKPTS
[ ! -d $chkpt ] && mkdir -p $chkpt;

datadir=data/${gen}

# LABELS 
select-voiced-frames scp:$datadir/allfolds/lab_age.scp scp:$datadir/allfolds/vad.scp ark,scp:$PWD/arks/ruben/${gen}/lab_vad.ark,$PWD/$datadir/allfolds/lab_age_aftervad.scp || exit 1;

select-voiced-frames scp:$datadir/allfolds_pitch/lab_age.scp scp:$datadir/allfolds_pitch/vad.scp ark,scp:$PWD/arks/ruben/${gen}/lab_pitch_vad.ark,$PWD/$datadir/allfolds_pitch/lab_age_aftervad.scp || exit 1;

cp $PWD/$datadir/allfolds_pitch/lab_age_aftervad.scp $datadir/allfolds_pitch_no_postprocess/lab_age_aftervad.scp

exit 0;

# MFCC
add-deltas scp:$datadir/allfolds/feats.scp ark:- | select-voiced-frames ark:- scp:$datadir/allfolds/vad.scp ark,scp:$PWD/arks/ruben/${gen}/mfcc_vad.ark,$PWD/$datadir/allfolds/feats_aftervad.scp || exit 1

add-deltas scp:$datadir/allfolds/feats.scp ark:- | select-voiced-frames ark:- scp:$datadir/allfolds/vad.scp ark:- | splice-feats --left-context=10 --right-context=10 ark:- ark,scp:$PWD/arks/ruben/${gen}/mfcc_vad_splice.ark,$PWD/$datadir/allfolds/feats_aftervad_splice.scp || exit 1

# MFCC PITCH
add-deltas scp:$datadir/allfolds_pitch/feats.scp ark:- | select-voiced-frames ark:- scp:$datadir/allfolds_pitch/vad.scp ark,scp:$PWD/arks/ruben/${gen}/mfcc_pitch_vad.ark,$PWD/$datadir/allfolds_pitch/feats_aftervad.scp || exit 1

add-deltas scp:$datadir/allfolds_pitch/feats.scp ark:- | select-voiced-frames ark:- scp:$datadir/allfolds_pitch/vad.scp ark:- | splice-feats --left-context=10 --right-context=10 ark:- ark,scp:$PWD/arks/ruben/${gen}/mfcc_pitch_vad_splice.ark,$PWD/$datadir/allfolds_pitch/feats_aftervad_splice.scp || exit 1

# MFCC PITCH NO POST PROCESS
add-deltas scp:$datadir/allfolds_pitch_no_postprocess/feats.scp ark:- | select-voiced-frames ark:- scp:$datadir/allfolds_pitch/vad.scp ark,scp:$PWD/arks/ruben/${gen}/mfcc_pitch_no_process_vad.ark,$PWD/$datadir/allfolds_pitch_no_postprocess/feats_aftervad.scp || exit 1

add-deltas scp:$datadir/allfolds_pitch_no_postprocess/feats.scp ark:- | select-voiced-frames ark:- scp:$datadir/allfolds_pitch/vad.scp ark:- | splice-feats --left-context=10 --right-context=10 ark:- ark,scp:$PWD/arks/ruben/${gen}/mfcc_pitch_no_postprocess_vad_splice.ark,$PWD/$datadir/allfolds_pitch_no_postprocess/feats_aftervad_splice.scp || exit 1
