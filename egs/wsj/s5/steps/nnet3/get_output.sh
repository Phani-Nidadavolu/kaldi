#!/bin/bash

# Copyright 2012-2015 Johns Hopkins University (Author: Daniel Povey).  
#           2015-2016 Vimal Manohar
# Apache 2.0.

# This script is similar to steps/nnet3/get_egs.sh but used
# when getting general targets (not from alignment directory) for raw nnet 
#
# This script, which will generally be called from other neural-net training
# scripts, extracts the training examples used to train the neural net (and also
# the validation examples used for diagnostics), and puts them in separate archives.
#
# This script dumps egs with several frames of labels, controlled by the
# frames_per_eg config variable (default: 8).  This takes many times less disk
# space because typically we have 4 to 7 frames of context on the left and
# right, and this ends up getting shared.  This is at the expense of slightly
# higher disk I/O while training.


# Begin configuration section.
cmd=run.pl
feat_type=raw       # set it to 'lda' to use LDA features.
target_type=sparse  # dense to have dense targets, 
                    # sparse to have posteriors targets
num_targets=        # required for target-type=sparse with raw nnet
frames_per_eg=8   # number of frames of labels per example.  more->less disk space and
                  # less time preparing egs, but more I/O during training.
                  # note: the script may reduce this if reduce_frames_per_eg is true.
left_context=4    # amount of left-context per eg (i.e. extra frames of input features
                  # not present in the output supervision).
right_context=4   # amount of right-context per eg.
valid_left_context=   # amount of left_context for validation egs, typically used in
                      # recurrent architectures to ensure matched condition with
                      # training egs
valid_right_context=  # amount of right_context for validation egs
compress=true   # set this to false to disable compression (e.g. if you want to see whether
                # results are affected).

reduce_frames_per_eg=true  # If true, this script may reduce the frames_per_eg
                           # if there is only one archive and even with the
                           # reduced frames_per_eg, the number of
                           # samples_per_iter that would result is less than or
                           # equal to the user-specified value.
num_utts_subset=300     # number of utterances in validation and training
                        # subsets used for shrinkage and diagnostics.
num_valid_frames_combine=0 # #valid frames for combination weights at the very end.
num_train_frames_combine=10000 # # train frames for the above.
num_frames_diagnostic=4000 # number of frames for "compute_prob" jobs
samples_per_iter=400000 # this is the target number of egs in each archive of egs
                        # (prior to merging egs).  We probably should have called
                        # it egs_per_iter. This is just a guideline; it will pick
                        # a number that divides the number of samples in the
                        # entire data.

transform_dir=     

stage=0
nj=6         # This should be set to the maximum number of jobs you are
             # comfortable to run in parallel; you can increase it if your disk
             # speed is greater and you have more machines.
online_ivector_dir=  # can be used if we are including speaker information as iVectors.
cmvn_opts=  # can be used for specifying CMVN options, if feature type is not lda (if lda,
            # it doesn't make sense to use different options than were used as input to the
            # LDA transform).  This is used to turn off CMVN in the online-nnet experiments.

echo "$0 $@"  # Print the command line for logging

if [ -f path.sh ]; then . ./path.sh; fi
. parse_options.sh || exit 1;

if [ $# != 2 ]; then
  echo "Usage: $0 [opts] <data> <nnet3dir>"
  echo " e.g.: $0 data/train exp/nnet3/train"
  echo ""
  echo "Main options (for others, see top of script file)"
  echo "  --config <config-file>                           # config file containing options"
  echo "  --nj <nj>                                        # The maximum number of jobs you want to run in"
  echo "                                                   # parallel (increase this only if you have good disk and"
  echo "                                                   # network speed).  default=6"
  echo "  --cmd (utils/run.pl;utils/queue.pl <queue opts>) # how to run jobs."
  echo "  --samples-per-iter <#samples;400000>             # Target number of egs per archive (option is badly named)"
  echo "  --feat-type <lda|raw>                            # (raw is the default).  The feature type you want"
  echo "                                                   # to use as input to the neural net."
  echo "  --frames-per-eg <frames;8>                       # number of frames per eg on disk"
  echo "  --left-context <width;4>                         # Number of frames on left side to append for feature input"
  echo "  --right-context <width;4>                        # Number of frames on right side to append for feature input"
  echo "  --num-frames-diagnostic <#frames;4000>           # Number of frames used in computing (train,valid) diagnostics"
  echo "  --num-valid-frames-combine <#frames;10000>       # Number of frames used in getting combination weights at the"
  echo "                                                   # very end."
  echo "  --stage <stage|0>                                # Used to run a partially-completed training process from somewhere in"
  echo "                                                   # the middle."

  exit 1;
fi

data=$1
nnet3dir=$2

mode=`basename $data`
dir=$nnet3dir/fwd/$mode

# Check some files.
[ ! -z "$online_ivector_dir" ] && \
  extra_files="$online_ivector_dir/ivector_online.scp $online_ivector_dir/ivector_period"

model=$nnet3dir/final.raw

for f in $data/feats.scp $model; do
  [ ! -f $f ] && echo "$0: no such file $f" && exit 1;
done

sdata=$data/split$nj
utils/split_data.sh $data $nj

mkdir -p $dir/log $dir/info

if [ ! -z "$transform_dir" ] && [ -f $transform_dir/trans.1 ] && [ $feat_type != "raw" ]; then
  echo "$0: using transforms from $transform_dir"
  if [ $stage -le 0 ]; then
    $cmd $dir/log/copy_transforms.log \
      copy-feats "ark:cat $transform_dir/trans.* |" "ark,scp:$dir/trans.ark,$dir/trans.scp"
  fi
fi

if [ -f $transform_dir/raw_trans.1 ] && [ $feat_type == "raw" ]; then
  echo "$0: using raw transforms from $transform_dir"
  if [ $stage -le 0 ]; then
    $cmd $dir/log/copy_transforms.log \
      copy-feats "ark:cat $transform_dir/raw_trans.* |" "ark,scp:$dir/trans.ark,$dir/trans.scp"
  fi
fi

## Set up features.
echo "$0: feature type is $feat_type"

case $feat_type in
  raw) feats="ark,s,cs:copy-feats scp:$sdata/JOB/feats.scp ark:- | apply-cmvn $cmvn_opts --utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp scp:- ark:- |"
    echo $cmvn_opts >$dir/cmvn_opts # caution: the top-level nnet training script should copy this to its own dir now.
   ;;
  lda)
    splice_opts=`cat $transform_dir/splice_opts 2>/dev/null`
    # caution: the top-level nnet training script should copy these to its own dir now.
    cp $transform_dir/{splice_opts,cmvn_opts,final.mat} $dir || exit 1;
    [ ! -z "$cmvn_opts" ] && \
       echo "You cannot supply --cmvn-opts option if feature type is LDA." && exit 1;
    cmvn_opts=$(cat $dir/cmvn_opts)
    feats="ark,s,cs:copy-feats scp:$sdata/JOB/feats.scp ark:- | apply-cmvn $cmvn_opts --utt2spk=ark:$sdata/JOB/utt2spk scp:$sdata/JOB/cmvn.scp scp:- ark:- | splice-feats $splice_opts ark:- ark:- | transform-feats $dir/final.mat ark:- ark:- |"
    ;;
  *) echo "$0: invalid feature type --feat-type '$feat_type'" && exit 1;
esac

if [ -f $dir/trans.scp ]; then
  feats="$feats transform-feats --utt2spk=ark:$sdata/JOB/utt2spk scp:$dir/trans.scp ark:- ark:- |"
fi

if [ ! -z "$online_ivector_dir" ]; then
  ivector_dim=$(feat-to-dim scp:$online_ivector_dir/ivector_online.scp -) || exit 1;
  echo $ivector_dim > $dir/info/ivector_dim
  ivector_period=$(cat $online_ivector_dir/ivector_period) || exit 1;

  ivector_opt="--ivectors='ark,s,cs:utils/filter_scp.pl $sdata/JOB/utt2spk $online_ivector_dir/ivector_online.scp | subsample-feats --n=-$ivector_period scp:- ark:- |'"
else
  echo 0 >$dir/info/ivector_dim
fi

egs_opts="--left-context=$left_context --right-context=$right_context --compress=$compress"

[ -z $valid_left_context ] &&  valid_left_context=$left_context;
[ -z $valid_right_context ] &&  valid_right_context=$right_context;
valid_egs_opts="--left-context=$valid_left_context --right-context=$valid_right_context --compress=$compress"

echo $left_context > $dir/info/left_context
echo $right_context > $dir/info/right_context

if [ $stage -le 3 ]; then
  echo "$0: Getting validation and training subset examples."
  $cmd JOB=1:$nj $dir/log/get_out.$mode.JOB.log \
    nnet3-compute --use-gpu=no \
    "$model" scp:$sdata/JOB/feats.scp ark,scp:$dir/fwd_$mode.JOB.ark,$dir/fwd_$mode.JOB.scp || exit 1;
fi

echo "$0: Finished preparing output"
