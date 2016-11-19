#!/bin/bash

# this is an example to show a "tdnn" system in raw nnet configuration
# i.e. without a transition model

# At this script level we don't support not running on GPU, as it would be painfully slow.
# If you want to run without GPU you'd have to call train_tdnn.sh with --gpu false,
# --num-threads 16 and --minibatch-size 128.

if [ $# -ne 3 ]; then
  echo USAGE: $0 gen feat foldnum
  echo USAGE: $0 male mfcc_pitch 2
  exit 0;
fi

gen=$1         # male or female
feattype=$2    # mfcc_pitch or mfcc
foldnum=$3     # 1-15

splice_ind="-4,-3,-2,-1,0,1,2,3,4 -7,5 0"
exp_num=`shuf --i=1-20 | head -1`


hl=`echo $splice_ind | awk '{print NF}'`
echo HIDDENLAYERS:$hl
relu_dim=256
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

dir=exp/tdnn_reg/$gen/${feattype}_testfold_${foldnum}_hl_${hl}_reludim_${relu_dim}_expnum_${exp_num}

if [ -d $dir ]; then
    exp_num=`shuf --i=1-20 | head -1`
    dir=exp/tdnn_reg/$gen/${feattype}_testfold_${foldnum}_hl_${hl}_reludim_${relu_dim}_expnum_${exp_num}
fi

data_dir=data/$gen/${feattype}_test_fold${foldnum}
targets_scp=$dir/targets.scp

mkdir -p $dir
touch ${dir}/splice_indexes && echo $splice_ind > ${dir}/splice_indexes

cp $data_dir/train/lab_age.scp $targets_scp

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
    --cmvn-opts "--norm-means=true --norm-vars=true" \
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

  for x in test train; do
    for j in `seq 1 30`; do
      cat $nnet3dir/fwd/$x/fwd_${x}.${j}.scp
    done > $nnet3dir/fwd/$x/out.scp || exit 1;

    [ ! -f $data_dir/${x}/lab_age.scp ] && echo missing:$data_dir/${x}/lab_age.scp && exit 1;
    matrix-sum --scale2=-1 scp:${data_dir}/${x}/lab_age.scp scp:${nnet3dir}/fwd/$x/out.scp ark,scp:$nnet3dir/fwd/$x/error.ark,$nnet3dir/fwd/$x/error.scp 
  done
  
fi

if [ $stage -le 14 ]; then
  nnet3dir=$dir

  for x in test train; do
      python compute_mae.py "$nnet3dir/fwd/$x/error.scp" || exit 1;
  done
fi
