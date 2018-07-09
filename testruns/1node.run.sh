#!/bin/bash
nodes=1
ppn=4
let nmpi=$nodes*$ppn
grid=2x2x1_12.cmg
order=16
groups=32
type=2
polar=8
azim=4
#--------------------------------------
cat >batch.job <<EOF
#BSUB -o %J.out
#BSUB -e %J.err
#BSUB -R "span[ptile=${ppn}]"
#BSUB -R "rusage[ngpus_shared=4]"
#BSUB -n ${nmpi}
#BSUB -x
#BSUB -q excl
##BSUB -W 30
#BSUB -env "all,LSB_START_JOB_MPS=N"
#---------------------------------------
export OMP_NUM_THREADS=20
export OMP_WAIT_POLICY=active
export HPM_GROUP_LIST=10,21



mpirun --bind-to none -np $nmpi ./set_device_and_bind.sh ../Teton/SuOlsonTest $grid $groups $type $order $polar $azim

EOF
#---------------------------------------
bsub <batch.job
