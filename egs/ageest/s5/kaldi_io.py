#!/usr/bin/env python
# Copyright 2014  Brno University of Technology (author: Karel Vesely)
#                 Brno University of Technology (author: Jan Pesan)
# Licensed under the Apache License, Version 2.0 (the "License")

import htk
import numpy as np
import struct, re
import scipy.io.wavfile as spiowav
import gzip

#################################################
# Data-type independent helper functions,

def open_or_fd(file, mode='rb'):
  """ fd = open_or_fd(file)
   Open file (or gzipped file), or forward the file-descriptor.
  """
  try:
    if file.split('.')[-1] == 'gz':
      fd = gzip.open(file, mode)
    else:
      fd = open(file, mode)
  except AttributeError:
    fd = file
  return fd

def read_key(fd):
  """ [str] = read_key(fd)
   Read utterance-key from file-descriptor.
  """
  str = ''
  while 1:
    char = fd.read(1)
    if char == '' : break
    if char == ' ' : break
    str += char
  str = str.strip()
  if str == '': return None # end of file,
  assert(re.match('^[\.a-zA-Z0-9_-]+$',str) != None) # check format,
  return str



#################################################
# Features as SCP file in HTK format,

def read_htk_scp(file_or_fd):
  """ generator(key,mat) = read_htk_scp(file)
   Create generator reading htk scp file, supports logical names and segments.
   file : filename or searchable file descriptor

   Hint, read scp to hash:
   d = dict((u,d) for u,d in pytel.kaldi_io.read_htk_scp(file))
  """
  fd = open_or_fd(file_or_fd, mode='r')
  try:
    for line in fd:
      line = line.strip() # no spaces,
      if line.find(' ') != -1: # 2 column kaldi scp -> logical=physical htk scp
        line = re.sub(' ','=',line)
      if line.find('=') != -1: # do we have 'logical=physical'?
        logical,physical = line.split('=')
      else:
        logical = physical = line # set logical name to physical,
      if physical.find('[') == -1: # do we have brackets?
        mat = htk.readhtk(physical)
      else:
        file,beg,end = re.sub('[\[\],]',' ',physical).strip().split(' ')
        mat = htk.readhtk_segment(file,int(beg),int(end))
      yield logical, mat
  finally:
    if fd is not file_or_fd: fd.close()



#################################################
# Integer vectors (alignments),

def read_ali_ark(file_or_fd):
  """ genrator(key,vec) = read_ali_ark(file_or_fd)
   Create generator of (key,vector<int>) tuples, which is reading from an ark file.
   file : filename or file-descriptor of ark-file

   Hint, read ark to hash:
   d = dict((u,d) for u,d in pytel.kaldi_io.read_ali_ark(file))
  """
  fd = open_or_fd(file_or_fd)
  try:
    key = read_key(fd)
    while key:
      ali = read_vec_int(fd)
      yield key, ali
      key = read_key(fd)
  finally:
    if fd is not file_or_fd: fd.close()

def read_vec_int(file_or_fd):
  """ [int-vec] = read_vec_int(file_or_fd)
   Read integer vector from file or file-descriptor, ascii or binary input,
  """
  fd = open_or_fd(file_or_fd)
  binary = fd.read(2)
  if binary == '\0B': # binary flag
    assert(fd.read(1) == '\4'); # int-size
    vec_size = struct.unpack('<i', fd.read(4))[0] # vector dim
    ans = np.zeros(vec_size, dtype=int)
    for i in range(vec_size):
      assert(fd.read(1) == '\4'); # int-size
      ans[i] = struct.unpack('<i', fd.read(4))[0] #data
    return ans
  else: # ascii,
    arr = (binary + fd.readline()).strip().split()
    try:
      arr.remove('['); arr.remove(']') # optionally
    except ValueError:
      pass
    ans = np.array(arr, dtype=int)
  if fd is not file_or_fd : fd.close() # cleanup
  return ans



#################################################
# Float vectors (confidences),

def read_vec_flt_ark(file_or_fd):
  """ genrator(key,vec) = read_vec_flt_ark(file_or_fd)
   Create generator of (key,vector<float>) tuples, which is reading from an ark file.
   file : filename or file-descriptor of ark-file

   Hint, read ark to hash:
   d = dict((u,d) for u,d in pytel.kaldi_io.read_ali_ark(file))
  """
  fd = open_or_fd(file_or_fd)
  try:
    key = read_key(fd)
    while key:
      ali = read_vec_flt(fd)
      yield key, ali
      key = read_key(fd)
  finally:
    if fd is not file_or_fd: fd.close()

def read_vec_flt(file_or_fd):
  """ [flt-vec] = read_vec_flt(file_or_fd)
   Read float vector from file or file-descriptor, ascii or binary input,
  """
  fd = open_or_fd(file_or_fd)
  binary = fd.read(2)
  if binary == '\0B': # binary flag
    # Data type,
    type = fd.read(3)
    if type == 'FV ': sample_size = 4 # floats
    if type == 'DV ': sample_size = 8 # doubles
    assert(sample_size > 0)
    # Dimension,
    assert(fd.read(1) == '\4'); # int-size
    vec_size = struct.unpack('<i', fd.read(4))[0] # vector dim
    # Read whole vector,
    buf = fd.read(vec_size * sample_size)
    if sample_size == 4 : ans = np.frombuffer(buf, dtype='float32') 
    elif sample_size == 8 : ans = np.frombuffer(buf, dtype='float64') 
    else : raise BadSampleSize
    return ans
  else: # ascii,
    arr = (binary + fd.readline()).strip().split()
    try:
      arr.remove('['); arr.remove(']') # optionally
    except ValueError:
      pass
    ans = np.array(arr, dtype=float)
  if fd is not file_or_fd : fd.close() # cleanup
  return ans



#################################################
# Float/double matrices,

# Reading,
def read_mat_scp(file_or_fd):
  """ generator(key,mat) = read_mat_scp(file_or_fd)
   Returns generator of (key,matrix) tuples, which are read from kaldi scp file.
   file : filename or opened scp-file descriptor

   Hint, read scp to hash:
   d = dict((u,d) for u,d in pytel.kaldi_io.read_mat_scp(file))
  """
  fd = open_or_fd(file_or_fd)
  try:
    for line in fd:
      (key,aux) = line.split(' ')
      (ark,offset) = aux.split(':')
      with open(ark,'rb') as f:
        f.seek(int(offset))
        mat = read_mat(f)
      yield key, mat
  finally:
    if fd is not file_or_fd : fd.close()

def read_mat_ark(file_or_fd):
  """ genrator(key,mat) = read_mat_ark(file_or_fd)
   Returns generator of (key,matrix) tuples, which reads ark file.
   file : filename or opened ark-file descriptor

   Hint, read scp to hash:
   d = dict((u,d) for u,d in pytel.kaldi_io.read_mat_ark(file))
  """
  fd = open_or_fd(file_or_fd)
  try:
    key = read_key(fd)
    while key:
      mat = read_mat(fd)
      yield key, mat
      key = read_key(fd)
  finally:
    if fd is not file_or_fd : fd.close()

def read_mat(file_or_fd):
  """ [mat] = read_mat(file_or_fd)
   Reads kaldi matrix from file or file-descriptor, can be ascii or binary.
  """
  fd = open_or_fd(file_or_fd)
  try:
    binary = fd.read(2)
    if binary == '\0B' : 
      mat = _read_mat_binary(fd)
    else:
      assert(binary == ' [')
      mat = _read_mat_ascii(fd)
  finally:
    if fd is not file_or_fd: fd.close()
  return mat

def _read_mat_binary(fd):
  # Data type
  type = fd.read(3)
  if type == 'FM ': sample_size = 4 # floats
  if type == 'DM ': sample_size = 8 # doubles
  assert(sample_size > 0)
  # Dimensions
  fd.read(1)
  rows = struct.unpack('<i', fd.read(4))[0]
  fd.read(1)
  cols = struct.unpack('<i', fd.read(4))[0]
  # Read whole matrix
  buf = fd.read(rows * cols * sample_size)
  if sample_size == 4 : vec = np.frombuffer(buf, dtype='float32') 
  elif sample_size == 8 : vec = np.frombuffer(buf, dtype='float64') 
  else : raise BadSampleSize
  mat = np.reshape(vec,(rows,cols))
  return mat

def _read_mat_ascii(fd):
  rows = []
  while 1:
    line = fd.readline()
    if (len(line) == 0) : raise BadInputFormat # eof, should not happen!
    if len(line.strip()) == 0 : continue # skip empty line
    arr = line.strip().split()
    if arr[-1] != ']':
      rows.append(np.array(arr,dtype='float32')) # not last line
    else: 
      rows.append(np.array(arr[:-1],dtype='float32')) # last line
      mat = np.vstack(rows)
      return mat

# Writing,
def write_mat(file_or_fd, m, key=''):
  """ write_mat(f, m, key='')
  Writes a binary kaldi matrix to filename or descriptor. Matrix can be float or double.
  Arguments:
   file_or_fd : filename of opened file descriptor for writing,
   m : matrix we are wrining,
   key (optional) : used for writing ark-file, the utterance-id gets written before the matrix.
  """
  fd = open_or_fd(file_or_fd, mode='wb')
  try:
    if key != '' : fd.write(key+' ') # ark-files have keys (utterance-id),
    fd.write('\0B') # we write binary!
    # Data-type,
    if m.dtype == 'float32': fd.write('FM ')
    elif m.dtype == 'float64': fd.write('DM ')
    else: raise MatrixDataTypeError
    # Dims,
    fd.write('\04')
    fd.write(struct.pack('I',m.shape[0])) # rows
    fd.write('\04')
    fd.write(struct.pack('I',m.shape[1])) # cols
    # Data,
    m.tofile(fd, sep="") # binary
  finally:
    if fd is not file_or_fd : fd.close()



#################################################
# Confusion Network bins,
# Typically composed of tuples (words/phones/states, posteriors),
# (uses Posterior datatype from Kaldi)
#

def read_cnet_ark(file_or_fd):
  """ [cnet-generator] = read_post_ark(file_or_fd)
   Alias of function 'read_post_ark'
  """
  return read_post_ark(file_or_fd)

def read_post_ark(file_or_fd):
  """ genrator(key,vec<vec<int,float>>) = read_post_ark(file)
   Returns generator of (key,posterior) tuples, which reads from ark file.
   file : filename or opened ark-file descriptor

   Hint, read scp to hash:
   d = dict((u,d) for u,d in pytel.kaldi_io.read_post_ark(file))
  """
  fd = open_or_fd(file_or_fd)
  try:
    key = read_key(fd)
    while key:
      post = read_post(fd)
      yield key, post
      key = read_key(fd)
  finally:
    if fd is not file_or_fd: fd.close()

def read_post(file_or_fd):
  """ [post] = read_post(file_or_fd)
   Reads kaldi Posterior in binary format. 
   
   Posterior is vec<vec<int,float>>, where outer-vector is over bins/frames, 
   inner vector is over words/phones/states, and inner-most tuple is composed 
   of an ID (integer) and POSTERIOR (float-value).
  """
  fd = open_or_fd(file_or_fd)
  ans=[]
  binary = fd.read(2); assert(binary == '\0B'); # binary flag
  assert(fd.read(1) == '\4'); # int-size
  outer_vec_size = struct.unpack('<i', fd.read(4))[0] # number of frames (or bins)
  for i in range(outer_vec_size):
    assert(fd.read(1) == '\4'); # int-size
    inner_vec_size = struct.unpack('<i', fd.read(4))[0] # number of records for frame (or bin)
    id = np.zeros(inner_vec_size, dtype=int) # buffer for integer id's
    post = np.zeros(inner_vec_size, dtype=float) # buffer for posteriors
    for j in range(inner_vec_size):
      assert(fd.read(1) == '\4'); # int-size
      id[j] = struct.unpack('<i', fd.read(4))[0] # id 
      assert(fd.read(1) == '\4'); # float-size
      post[j] = struct.unpack('<f', fd.read(4))[0] # post
    ans.append(zip(id,post))
  if fd is not file_or_fd: fd.close()
  return ans



#################################################
# Confusion Network begin/end times for the bins 
# (kaldi stores them separately), 
#

def read_cntime_ark(file_or_fd):
  """ genrator(key,vec<float,float>) = read_cntime_ark(file)
   Returns generator of (key,cntime) tuples, which are read from ark file.
   file_or_fd : filename or opened file-descriptor

   Hint, read scp to hash:
   d = dict((u,d) for u,d in pytel.kaldi_io.read_cntime_ark(file))
  """
  fd = open_or_fd(file_or_fd)
  try:
    key = read_key(fd)
    while key:
      cntime = read_cntime(fd)
      yield key, cntime
      key = read_key(fd)
  finally:
    if fd is not file_or_fd : fd.close()

def read_cntime(file_or_fd):
  """ [cntime] = read_cntime(file_or_fd)
   Reads structure representing begin/end times of bins in confusion network.
   Binary layout is '<num-bins> <beg1> <end1> <beg2> <end2> ...'
   file_or_fd : filename or opened file-descriptor
  """
  fd = open_or_fd(file_or_fd)
  binary = fd.read(2); assert(binary == '\0B'); # assuming it's binary
  assert(fd.read(1) == '\4'); # int-size
  vec_size = struct.unpack('<i', fd.read(4))[0] # number of frames (or bins)
  t_beg = np.zeros(vec_size, dtype=float)
  t_end = np.zeros(vec_size, dtype=float)
  for i in range(vec_size):
    assert(fd.read(1) == '\4'); # float-size
    t_beg[i] = struct.unpack('<f', fd.read(4))[0] # begin-time of bin
    assert(fd.read(1) == '\4'); # float-size
    t_end[i] = struct.unpack('<f', fd.read(4))[0] # end-time of bin
  ans = zip(t_beg,t_end)
  if fd is not file_or_fd : fd.close()
  return ans


#################################################
#################################################
# Kaldi NN I/O for 'theano', written by J.Pesan,

#################################################
# Helper methods to parse Kaldi NN configuration files
def getLayerDef(line):
  """
  Parses one line of Layer definition from proto file
  """
  allowed_keys = ["<OutputDim>","<InputDim>","<ParamStddev>","<BiasMean>","<BiasRange>","<LearnRateCoef>","<BiasLearnRateCoef>","<MaxNorm>"]
  params = {}
  for k,v in zip(line.split()[1:-2:2], line.split()[2::2]):
    if k not in allowed_keys:
      print "%s parameter is not known!" %(k)
      return None
    #print k[1:-1],np.float32(v)
    params[k[1:-1]] = np.float32(v)
  return params

def getLayerSize(line):
  """
  """
  affineTransformRe = re.compile('<AffineTransform> (.+) (.+)')
  m = re.match(affineTransformRe, line)
  return (int(m.group(2)), int(m.group(1))) if m else None

def getNonlinearity(line):
  """
  Parse nonlinearity name from Kaldi NN file
  """
  nonLinearityRe = re.compile('<(.+?)> .*')
  nl = re.match(nonLinearityRe, line).group(1)
  return nl

def sec2frames(start,end,fs):
  """
  Converts seconds to frames
  """
  return np.arange(int(float(start)*fs), int(float(end)*fs))

#################################################
# Reading Kaldi NN files

def read_wav_segments(scp_file, segments_file):
  """ 
  Reads wave segments from segments file according to scp_file.
  Returns generator of (logical_name,data) tuples
  scp_file : SCP 
  segments_file: data file which contains audio data
  """
  seg = open_or_fd(segments_file, mode='r')
  scp = open_or_fd(scp_file, mode='r')
  try:
    scp_dict = {l:p for l,p in  np.loadtxt(scp, dtype=object)}
    for (n,l,s,e) in np.loadtxt(seg, dtype=object):
      fs,data = spiowav.read(scp_dict[l])
      yield n, data[sec2frames(s,e,fs)]
  finally:
    if seg is not segments_file: seg.close()
    if scp is not scp_file: scp.close()

def read_nnet_ascii(file):
  """ 
  Reads wave NN ascii file and returns standard representation for
  pytel.nn as dictionary. 
  file: kaldi ascii representation of NN
  """
  f = open_or_fd(file, mode='r')
  try:
    params_dict = {}
    layer = 1
    while 1:
      row = f.readline().strip()
      if not row:
        return params_dict
      if len(row) == 0:
        continue
      if row[0] == "<":
        if row == "<Nnet>" or row == "</Nnet>":
          continue
        else:
          sizes = getLayerSize(row)
          if sizes: #we do have weights
            shittyFormat=False #matrices terminated with ] without \n
            rows = []
            f.readline() #skip one line
            for i in range(sizes[1]):
              row = f.readline().split()
              #print row
              if row[-1] != ']':
                if row[0] == '[': #first line
                  rows.append(np.array(row[1:],dtype='float32')) # not last line
                else:
                  rows.append(np.array(row,dtype='float32')) # not last line
              else: 
                shittyFormat=True
            if shittyFormat:
              rows.append(np.array(row[:-1],dtype='float32')) # last line
              W = np.vstack(rows).T
            else:
              W = np.vstack(rows).T
              f.readline()
            params_dict['W'+str(layer)] = W
            #now bias
            bias_row = f.readline().strip()
            bias = np.array(bias_row.split()[1:-1], dtype='float32')
            params_dict['b'+str(layer)] = bias
            #print "Reading Nonlinearity"
            nl = getNonlinearity(f.readline())
            params_dict['nl'+str(layer)] = nl
            layer +=1
          else:
            print row
            print "Not in desired format"
            return None
  finally:
    #print "%d layers read from file" % (layer-1)
    if f is not file: f.close()

def init_proto(file):
  """ 
  Reads standard Kaldi init.proto file and returns dictionary 
  with standard pytel.nn representation of NN
  file:  Kaldi init.proto file
  
  Notice: follows exact implementation as in Kaldi source
  """
  layer_params_default = {"ParamStddev":0.1, "BiasMean":-2.0, "BiasRange": 2.0,"LearnRateCoef":1.0,"BiasLearnRateCoef":1.0,"MaxNorm":0.0}
  params_dict = {}
  layer = 1
  f = open_or_fd(file, mode='r')
  try:
    while 1:
      row = f.readline().strip()
      if not row:
        return params_dict
      if row == "<NnetProto>" or row == "</NnetProto>":
          continue
      else:
        if "<AffineTransform>" in row:
          #print row
          layer_params = getLayerDef(row)
          [layer_params.setdefault(a, layer_params_default[a]) for a in layer_params_default]
          params_dict['W'+str(layer)] = np.random.randn(layer_params['InputDim'], layer_params['OutputDim']) * layer_params['ParamStddev']
          params_dict['b'+str(layer)] = layer_params['BiasMean'] + (np.random.random(layer_params['OutputDim']) - 0.5) * layer_params['BiasRange']
          row = f.readline().strip() #read non-linearity
          nl = getNonlinearity(row)
          params_dict['nl'+str(layer)] = nl
          layer +=1
  finally:
    if f is not file: f.close()
#################################################
# Writing Kaldi NN files

def write_nnet_ascii(file, param_dict):
  """ 
  Takes standard representation of NN and writes it to Kaldi compatible NN ascii file
  file:  file where to write NN
  param_dict:  standard representation of NN in pytel.nn
  """
  fd = open_or_fd(file, mode='r')
  try:
    import sys
    #fd = sys.stdout
    fd.write("<Nnet>\n")
    for i in range(1,(len(param_dict)/3)+1):
      fd.write("<AffineTransform> %d %d\n" % param_dict["W"+str(i)].shape[::-1])
      np.savetxt(fd, param_dict['W'+str(i)].T,fmt='%-5.10f', newline='\n  ',header='[',footer=']', comments='')
      np.savetxt(fd, param_dict['b'+str(i)],fmt='%-5.10f',newline=' ', header='[',footer=']', comments='')
      fd.write("\n")
      fd.write("<%s> %d %d\n" % (param_dict['nl'+str(i)], len(param_dict['b'+str(i)]) ,len(param_dict['b'+str(i)])))
    fd.write("</Nnet>\n")
  finally:
    if fd is not file: fd.close()

# END (Kaldi NN I/O for 'theano')
#################################################
#################################################
