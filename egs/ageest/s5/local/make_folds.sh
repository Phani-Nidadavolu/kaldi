. ./path.sh
. ./cmd.sh

if [ $# -ne 1 ]; then
  echo USAGE $0 gender
  exit 1;
fi

gen=$1

datadir=data/${gen}
listdir=fromAnna/${gen}_lists_modified

awk ' {print $2"-"$1}' fromAnna/srcdata_modified/all_${gen}.txt | sort -u > ${listdir}/allutts.txt

# MFCC
add-deltas scp:$datadir/allfolds/feats.scp ark:- | apply-cmvn-sliding --norm-vars=false --center=true --cmn-window=300 ark:- ark:- | select-voiced-frames ark:- scp:$datadir/allfolds/vad.scp ark,scp:$PWD/arks/ruben/${gen}/feats.ark,$PWD/$datadir/allfolds/feats_ruben_aftervad.scp || exit 1;

for x in `seq 1 15`; do
    for utt in `cat ${listdir}/list${x}`; do
        newutt=`awk -v utt=$utt ' $1 == utt {print $2"-"$1}' fromAnna/srcdata_modified/all_${gen}.txt`
        echo $newutt
    done |sort -u > ${listdir}/uttlist${x}.txt
    utils/subset_data_dir.sh --utt-list ${listdir}/uttlist${x}.txt ${datadir}/allfolds ${datadir}/mfcc_test_fold${x}/test || exit 1;
    comm -23 ${listdir}/allutts.txt ${listdir}/uttlist${x}.txt > ${listdir}/uttlist${x}_train.txt

    utils/subset_data_dir.sh --utt-list ${listdir}/uttlist${x}_train.txt ${datadir}/allfolds ${datadir}/mfcc_test_fold${x}/train || exit 1;
done

# MFCC PITCH
add-deltas scp:$datadir/allfolds_pitch/feats.scp ark:- | apply-cmvn-sliding --norm-vars=false --center=true --cmn-window=300 ark:- ark:- | select-voiced-frames ark:- scp:$datadir/allfolds_pitch/vad.scp ark,scp:$PWD/arks/ruben/${gen}/feats.ark,$PWD/$datadir/allfolds_pitch/feats_ruben_aftervad.scp || exit 1;

for x in `seq 1 15`; do
    for utt in `cat ${listdir}/list${x}`; do
        newutt=`awk -v utt=$utt ' $1 == utt {print $2"-"$1}' fromAnna/srcdata_modified/all_${gen}.txt`
        echo $newutt
    done |sort -u > ${listdir}/uttlist${x}.txt
    utils/subset_data_dir.sh --utt-list ${listdir}/uttlist${x}.txt ${datadir}/allfolds_pitch ${datadir}/mfcc_pitch_test_fold${x}/test || exit 1;
    comm -23 ${listdir}/allutts.txt ${listdir}/uttlist${x}.txt > ${listdir}/uttlist${x}_train.txt

    utils/subset_data_dir.sh --utt-list ${listdir}/uttlist${x}_train.txt ${datadir}/allfolds_pitch ${datadir}/mfcc_pitch_test_fold${x}/train || exit 1;
done
