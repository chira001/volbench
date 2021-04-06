#!/usr/bin/env bash
# published at https://github.com/chira001/volbench - PR and comments welcome
# originally inspired by https://github.com/leeliu/dbench

# specify a space seperated set of files to use as tests. tests are run in paralled across all files
FIO_files="/tmp/volbenchtest1 /tmp/volbenchtest2"
# note: the test files are not deleted at the end, to make it easy to run multiple tests
#       please remember to delete the test files
# # specify the size of the test files
#FIO_size=10MB
# specify a ramp time before recording values - this should be around 10 seconds
#FIO_ramptime=10
# specify a runtime for each test - should be 30s minimum, but 120 is preferred
#FIO_runtime=120
# # specify the percentage of read requests in mixed tests
FIO_rwmixread=75
# specify how many write i/os before an fdatasync - 0 disables
FIO_fdatasync=0

# specify default number of jobs per file - default to 1 (don't change this)
FIO_numjobs=1
#specify default offset_increment - default to 0 (don't change this)
FIO_offset_increment=0

#define some colour escape codes
YELLOW='\033[1;33m'
GREEN='\033[1;32m'
CYAN='\033[1;34m'
NC='\033[0m'


# global setttings for all fio jobs
function fio-global {
	echo "[global]
bs=${FIO_blocksize}k
ioengine=libaio
iodepth=$FIO_queuedepth
thread
direct=1
fdatasync=$FIO_fdatasync
random_generator=tausworthe64
random_distribution=random
rw=$FIO_readwrite
rwmixread=$FIO_rwmixread
percentage_random=$FIO_percentage_random
group_reporting=0
time_based
ramp_time=$FIO_ramptime
runtime=$FIO_runtime"
	echo
}

# setup a job per test file
function fio-job {
	for inp in $*
	do
		echo "[$inp]"
		echo "numjobs=$FIO_numjobs"
		echo "filename=$inp"
		echo "size=$FIO_size"
		echo "offset=0"
		echo "offset_increment=$FIO_offset_increment"
	done
}

# parse the output of fio minimal data output
function fio-parse {
	awk -F';' 'BEGIN {printf "%30s %8s %9s %8s   %8s %9s %8s\n", "Test file", "R iops", "R lat ms", "R MB/s", "W iops", "W lat ms", "W MB/s"} {records +=1} {readsum += $8} {writesum += $49} {readmb += $7} {writemb += $48} {readlats += $40 } {writelats += $81} {printf "%30s '$YELLOW'%8d'$NC' '$GREEN'%9.3f'$NC' %8.1f   '$YELLOW'%8d'$NC' '$GREEN'%9.3f'$NC' %8.1f  \n", $3, $8, $40/1000, $7/1024, $49, $81/1000, $48/1024} END {printf "'$CYAN'%30s %8d %9.3f %8.1f   %8d %9.3f %8.1f'$NC'\n\n", "TOTAL/Average", readsum, (readlats/records)/1000, readmb/1024, writesum, (writelats/records)/1000, writemb/1024}'
}

#return a field from the minimal fio
function fio-getfield {
	awk -F';' '{records +=1} {readsum += $8} {writesum += $49} {readmb += $7} {writemb += $48} {readlats += $40 } {writelats += $81} END {printf "%d %.3f %.1f %d %.3f %.1f\n", readsum, (readlats/records)/1000, readmb/1024, writesum, (writelats/records)/1000, writemb/1024}' | awk '{print $'$1'}'
}

# sync and clear the caches, then run the fio job
function fio-run {
	sync
	
	#if we are root, then drop the kernel caches
	if [ $UID -eq 0 ]
		then echo 1 > /proc/sys/vm/drop_caches
	fi

	#combine the global params and the jobspec and run fio
	( fio-global ; fio-job $FIO_files ) | fio --minimal -
}


#start the suite of tests
echo
echo "Starting VolBench tests ..."
echo
echo "Test parameters:"
echo "FIO_files=$FIO_files"
echo "FIO_size=$FIO_size  FIO_ramptime=$FIO_ramptime  FIO_runtime=$FIO_runtime"
echo ; echo


# test concurrent random read iops - e.g. db queries/message bus
echo Testing read iops ...
FIO_blocksize=4k FIO_queuedepth=16 FIO_readwrite=randread FIO_percentage_random=100
FIO_output=$(fio-run)
echo "$FIO_output" | fio-parse
READ_IOPS=`echo "$FIO_output" | fio-getfield 1`

# test concurrent randdom write iops - e.g. db commits
echo Testing write iops ...
FIO_blocksize=4k FIO_queuedepth=16 FIO_readwrite=randwrite FIO_percentage_random=100
FIO_output=$(fio-run)
echo "$FIO_output" | fio-parse
WRITE_IOPS=`echo "$FIO_output" | fio-getfield 4`

# test read throughput
echo Testing read throughput ...
FIO_blocksize=128k FIO_queuedepth=16 FIO_readwrite=randread FIO_percentage_random=100
FIO_output=$(fio-run)
echo "$FIO_output" | fio-parse
READ_MB=`echo "$FIO_output" | fio-getfield 3`

# test write throughput
echo Testing write throughput ...
FIO_blocksize=128k FIO_queuedepth=16 FIO_readwrite=randwrite FIO_percentage_random=100
FIO_output=$(fio-run)
echo "$FIO_output" | fio-parse
WRITE_MB=`echo "$FIO_output" | fio-getfield 6`

# test read latency, low concurrency
echo Testing read latency ...
FIO_blocksize=4k FIO_queuedepth=4 FIO_readwrite=randread FIO_percentage_random=100
FIO_output=$(fio-run)
echo "$FIO_output" | fio-parse
READ_LAT=`echo "$FIO_output" | fio-getfield 2`

# test write latency, low concurrency
echo Testing write latency ...
FIO_blocksize=4k FIO_queuedepth=4 FIO_readwrite=randwrite FIO_percentage_random=100
FIO_output=$(fio-run)
echo "$FIO_output" | fio-parse
WRITE_LAT=`echo "$FIO_output" | fio-getfield 5`

# test concurrent read and write iops
echo Testing mixed iops ...
FIO_blocksize=4k FIO_queuedepth=16 FIO_readwrite=randrw FIO_percentage_random=100
FIO_output=$(fio-run)
echo "$FIO_output" | fio-parse
READ_MIXED=`echo "$FIO_output" | fio-getfield 1`
WRITE_MIXED=`echo "$FIO_output" | fio-getfield 4`

# update FIO_size and set increment to be able to split across 4 jobs
FIO_unit=`echo $FIO_size | sed 's/[0-9]//g'`
FIO_sizenumber=`echo $FIO_size | sed 's/[a-z]//ig'`
FIO_offset_increment=`expr $FIO_sizenumber / 4`$FIO_unit
FIO_oldsize=$FIO_size
FIO_size=$FIO_offset_increment

# test read sequental throughput
echo Testing read seqential ...
FIO_blocksize=1M FIO_queuedepth=4 FIO_readwrite=read FIO_percentage_random=0 FIO_numjobs=4
FIO_output=$(fio-run)
echo "$FIO_output" | fio-parse
READ_SEQ=`echo "$FIO_output" | fio-getfield 3`

# test write sequention throughput
echo Testing write seqential ...
FIO_blocksize=1M FIO_queuedepth=4 FIO_readwrite=write FIO_percentage_random=0 FIO_numjobs=4
FIO_output=$(fio-run)
echo "$FIO_output" | fio-parse
WRITE_SEQ=`echo "$FIO_output" | fio-getfield 6`


#output final report
echo
printf "%22s  %10s      %10s     \n" "VolBench Summary" "Reads" "Writes" 
echo "---------------------------------------------------------"
printf "%22s: %10s iops %10s iops\n" "I/O operations" ${READ_IOPS} ${WRITE_IOPS}
printf "%22s: %10s iops %10s iops\n" "Mixed I/O" ${READ_MIXED} ${WRITE_MIXED}
printf "%22s: %10s ms   %10s ms  \n" "Latency" ${READ_LAT} ${WRITE_LAT}
printf "%22s: %10s MB/s %10s MB/s\n" "Random throughput" ${READ_MB} ${WRITE_MB}
printf "%22s: %10s MB/s %10s MB/s\n" "Sequential throughput" ${READ_SEQ} ${WRITE_SEQ}
echo ; echo

exit
