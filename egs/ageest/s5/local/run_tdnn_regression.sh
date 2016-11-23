#!/bin/bash

# this is an example to show a "tdnn" system in raw nnet configuration
# i.e. without a transition model

# At this script level we don't support not running on GPU, as it would be painfully slow.
# If you want to run without GPU you'd have to call train_tdnn.sh with --gpu false,
# --num-threads 16 and --minibatch-size 128.

if [ $# -ne 3 ]; then
  echo USAGE: $0 gen feat foldnum
  echo USAGE: $0 male mfcc_pitch_no_postprocess 1
  exit 0;
fi

gen=$1         # male or female
feattype=$2    # mfcc_pitch or mfcc
foldnum=$3     # 1-15

splice_ind="-2,-1,0,1,2 -1,2 -3,3 -7,2 0"
exp_num=`shuf --i=1-20 | head -1`


hl=`echo $splice_ind | awk '{print NF}'`
echo HIDDENLAYERS:$hl
relu_dim=512
stage=0
train_stage=-10
common_egs_dir=
num_data_reps=10

# "-2,-1,0,1,2 -1,2 -3,3 -7,2 0"
remove_egs=true

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh

set -e

if ! cuda-compiled; then
  cat <<EOF && exit 1
This script is intended to be used with GPUs but you have not compiled Kaldi with CUDA
If you want to use GPUs (and have them), go to src/, and configure and make on a machine
where "nvcc" is installed.
EOF
fi

for x in feats feats_aftervad feats_aftervad_splice; do

  dir=exp/tdnn_reg/$gen/${feattype}_ftype_${x}_testfold_${foldnum}_hl_${hl}_hdim_${relu_dim}

  data_dir_src=data/$gen/${feattype}_test_fold${foldnum}
  data_dir=$dir/data
  targets_scp=$dir/targets.scp
  test_targets_scp=$dir/test_targets.scp

  mkdir -p $dir/data

  touch ${dir}/splice_indexes && echo $splice_ind > ${dir}/splice_indexes

  for d in train test; do
    utils/copy_data_dir.sh $data_dir_src/${d} $data_dir/${d} || exit 1;
    rm $data_dir/${d}/feats*
    [ ! -f $data_dir_src/${d}/${x}.scp ] && echo "MISSING: $data_dir_src/${d}/${x}.scp" && exit 1;
    cp $data_dir_src/${d}/${x}.scp $data_dir/${d}/feats.scp
  done

  if [ $x == "feats" ]; then
    cp $data_dir/train/lab_age.scp $targets_scp
    cp $data_dir/test/lab_age.scp $test_targets_scp
  else
    cp $data_dir/test/lab_age_aftervad.scp $test_targets_scp
    cp $data_dir/train/lab_age_aftervad.scp $targets_scp
  fi

  if [ $stage -le 9 ]; then
    echo "$0: creating neural net configs";
  
    num_targets=`feat-to-dim scp:$targets_scp - 2>/dev/null` || exit 1

    # create the config files for nnet initialization
    python steps/nnet3/tdnn/make_configs.py  \
       --splice-indexes "$splice_ind"  \
       --feat-dir ${data_dir}/train \
       --relu-dim=$relu_dim \
       --add-lda=false \
       --objective-type=quadratic \
       --add-final-sigmoid=false \
       --include-log-softmax=false \
       --use-presoftmax-prior-scale=false \
       --num-targets=$num_targets \
       $dir/configs || exit 1;
  fi

  if [ $stage -le 10 ]; then
    if [[ $(hostname -f) == *.clsp.jhu.edu ]] && [ ! -d $dir/egs/storage ]; then
      utils/create_split_dir.pl \
       /export/b1{4,5,6,7}/$USER/kaldi-data/egs/ageest-$(date +'%m_%d_%H_%M')/s5/$dir/egs/storage $dir/egs/storage
    fi

    steps/nnet3/tdnn/train_raw_nnet.sh --stage $train_stage \
      --cmd "$decode_cmd" \
      --cmvn-opts "--norm-means=false --norm-vars=false" \
      --num-epochs 2 \
      --num-jobs-initial 3 \
      --num-jobs-final 16 \
      --initial-effective-lrate 0.0017 \
      --final-effective-lrate 0.00017 \
      --egs-dir "$common_egs_dir" \
      --remove-egs $remove_egs \
      --use-gpu true \
      --dense-targets true \
      ${data_dir}/train $targets_scp $dir || exit 1
  fi

  if [ $stage -le 11 ]; then
    nnet3dir=$dir
    data=${data_dir}/test

    steps/nnet3/get_output.sh --stage 0 \
      --cmd "$decode_cmd" \
      --cmvn-opts "--norm-means=false --norm-vars=false" \
      --nj 30 \
      ${data} $nnet3dir || exit 1

  fi

  if [ $stage -le 12 ]; then
    nnet3dir=$dir
    data=${data_dir}/train

    steps/nnet3/get_output.sh --stage 0 \
      --cmd "$decode_cmd" \
      --cmvn-opts "--norm-means=false --norm-vars=false" \
      --nj 30 \
      ${data} $nnet3dir || exit 1
  fi

  if [ $stage -le 13 ]; then
    nnet3dir=$dir
    data=${data_dir}

    # COMPUTE ERROR FOR TRAIN DATA
    x=train
    for j in `seq 1 30`; do
      cat $nnet3dir/fwd/$x/fwd_${x}.${j}.scp
    done > $nnet3dir/fwd/$x/out.scp || exit 1;

    matrix-sum --scale2=-1 scp:${targets_scp} scp:${nnet3dir}/fwd/train/out.scp ark,scp:$nnet3dir/fwd/train/error.ark,$nnet3dir/fwd/train/error.scp 
  
    # COMPUTE ERROR FOR TEST DATA
    x=test
    for j in `seq 1 30`; do
      cat $nnet3dir/fwd/$x/fwd_${x}.${j}.scp
    done > $nnet3dir/fwd/$x/out.scp || exit 1;

    matrix-sum --scale2=-1 scp:${test_targets_scp} scp:${nnet3dir}/fwd/test/out.scp ark,scp:$nnet3dir/fwd/test/error.ark,$nnet3dir/fwd/test/error.scp 
  
  fi

  if [ $stage -le 14 ]; then
    nnet3dir=$dir

    for x in test train; do
      python compute_mae.py "$nnet3dir/fwd/$x/error.scp" || exit 1;
    done
  fi

done
