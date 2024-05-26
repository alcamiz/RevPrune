all:
	/lusr/cuda-11.6/bin/nvcc -o pruning pruning.cu pruning_kernel.cu
