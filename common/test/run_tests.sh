#!/bin/sh

export INCFLAGS=`../../FoX-config --fcflags --wxml`
make clean
rm -f passed.score failed.score
touch passed.score failed.score
rm -f tests.out failed.out

for t in test_xml*.sh
do
  ./$t
done

echo "Testing integer to string conversion"
echo Scalars:
for i in '0 0' '1 1' '-1 -1' '10 10' '-356 -356'
do
  ./test_str.sh $i
done
echo Arrays:
./test_str.sh "(/0, 1, 2, 3/)" "0 1 2 3"
./test_str.sh "(/0, 1, -2, -100/)" "0 1 -2 -100"
./test_str.sh "(/0/)" "0"
echo Matrices:
./test_str.sh "reshape((/0,1,2,3,4,5/), (/3,2/))" "0 1 2 3 4 5"
./test_str.sh "reshape((/0,1,2,3,4,5,4,5,6,7,8,9/),(/3,4/))" "0 1 2 3 4 5 4 5 6 7 8 9"

echo "Testing logical to string conversion"

echo Scalars:
for i in '.True. true' '.False. false';
do
  ./test_str.sh $i
done
echo Arrays:
./test_str.sh "(/.true./)" "true"
./test_str.sh "(/.false./)" "false"
./test_str.sh "(/.true., .false./)" "true false"
./test_str.sh "(/.false., .true., .false./)" "false true false"
echo Matrices:
./test_str.sh "reshape((/.true.,.true.,.true.,.false.,.false.,.false./),(/3,2/))" "true true true false false false"
./test_str.sh "reshape((/.true.,.true.,.false.,.false.,.true.,.true./),(/2,3/))" "true true false false true true"

echo "Testing single precision to string conversion"
echo Scalars:
for i in \
         '0.50e0,"s1" 5e-1' \
         '0.50e0,"s2" 5.0e-1' \
         '0.50e0,"s3" 5.00e-1' \
         '0.50e0,"s4" 5.000e-1' \
         '0.50e0,"s5" 5.0000e-1' \
         '0.50e0,"r0" 0' \
         '0.50e0,"r1" 0.5' \
         '0.50e0,"r2" 0.50' \
         '0.50e0,"r3" 0.500' \
         '0.50e0,"r4" 0.5000' \
         '0.00e0,"s1" 0e0' \
         '0.00e0,"s2" 0.0e0' \
         '0.00e0,"s3" 0.00e0' \
         '0.00e0,"s4" 0.000e0' \
         '0.00e0,"s5" 0.0000e0' \
         '0.00e0,"r0" 0' \
         '0.00e0,"r1" 0.0' \
         '0.00e0,"r2" 0.00' \
         '0.00e0,"r3" 0.000' \
         '0.00e0,"r4" 0.0000' \
         '1.00e0,"s1" 1e0' \
         '1.00e0,"s2" 1.0e0' \
         '1.00e0,"s3" 1.00e0' \
         '1.00e0,"s4" 1.000e0' \
         '1.00e0,"s5" 1.0000e0' \
         '1.00e0,"r0" 1' \
         '1.00e0,"r1" 1.0' \
         '1.00e0,"r2" 1.00' \
         '1.00e0,"r3" 1.000' \
         '1.00e0,"r4" 1.0000' \
         '-1.00e0,"s1" -1e0' \
         '-1.00e0,"s2" -1.0e0' \
         '-1.00e0,"s3" -1.00e0' \
         '-1.00e0,"s4" -1.000e0' \
         '-1.00e0,"s5" -1.0000e0' \
         '-1.00e0,"r0" -1' \
         '-1.00e0,"r1" -1.0' \
         '-1.00e0,"r2" -1.00' \
         '-1.00e0,"r3" -1.000' \
         '-1.00e0,"r4" -1.0000' \
         '1.00e1,"s1" 1e1' \
         '1.00e1,"s2" 1.0e1' \
         '1.00e1,"s3" 1.00e1' \
         '1.00e1,"s4" 1.000e1' \
         '1.00e1,"s5" 1.0000e1' \
         '1.00e1,"r0" 10' \
         '1.00e1,"r1" 10.0' \
         '1.00e1,"r2" 10.00' \
         '1.00e1,"r3" 10.000' \
         '1.00e1,"r4" 10.0000' \
         '-1.00e1,"s1" -1e1' \
         '-1.00e1,"s2" -1.0e1' \
         '-1.00e1,"s3" -1.00e1' \
         '-1.00e1,"s4" -1.000e1' \
         '-1.00e1,"s5" -1.0000e1' \
         '-1.00e1,"r0" -10' \
         '-1.00e1,"r1" -10.0' \
         '-1.00e1,"r2" -10.00' \
         '-1.00e1,"r3" -10.000' \
         '-1.00e1,"r4" -10.0000' \
         '-1.00e4,"s1" -1e4' \
         '-1.00e4,"s2" -1.0e4' \
         '-1.00e4,"s3" -1.00e4' \
         '-1.00e4,"s4" -1.000e4' \
         '-1.00e4,"s5" -1.0000e4' \
         '-1.00e4,"r0" -10000' \
         '-1.00e4,"r1" -10000.0' \
         '-1.00e4,"r2" -10000.00' \
         '-1.00e4/3.0e0,"s1" -3e3' \
         '-1.00e4/3.0e0,"s2" -3.3e3' \
         '-1.00e4/3.0e0,"s3" -3.33e3' \
         '-1.00e4/3.0e0,"s4" -3.333e3' \
         '-1.00e4/3.0e0,"s5" -3.3333e3' \
         '-1.00e4/3.0e0,"r0" -3333' \
         '-1.00e4/3.0e0,"r1" -3333.3' \
         '-1.00e4/3.0e0,"r2" -3333.33' \
         '-1.00e4/3.0e0,"r3" -3333.333' \
         '-2.00e4/3.0e0,"s1" -7e3' \
         '-2.00e4/3.0e0,"s2" -6.7e3' \
         '-2.00e4/3.0e0,"s3" -6.67e3' \
         '-2.00e4/3.0e0,"s4" -6.667e3' \
         '-2.00e4/3.0e0,"s5" -6.6667e3' \
         '-2.00e4/3.0e0,"r0" -6667' \
         '-2.00e4/3.0e0,"r1" -6666.7' \
         '-2.00e4/3.0e0,"r2" -6666.67' \
         '-2.00e4/3.0e0,"r3" -6666.667' \
         '-99.9e0,"s1" -1e2' \
         '-99.9e0,"s2" -1.0e2' \
         '-99.9e0,"s3" -9.99e1' \
         '-99.9e0,"s4" -9.990e1' \
         '-99.9e0,"s5" -9.9900e1' \
         '-99.9e0,"r0" -100' \
         '-99.9e0,"r1" -99.9' \
         '-99.9e0,"r2" -99.90' \
         '-99.9e0,"r3" -99.900' \
         '-99.9e0,"r4" -99.9000'
do
  ./test_str.sh $i
done
echo Arrays:
./test_str.sh '(/0.0e0/),"s3"' "0.00e0"
./test_str.sh '(/0.0e0, 1.0e0/),"s5"' "0.0000e0 1.0000e0"
./test_str.sh '(/0.0e0, 100e0/),"s3"' "0.00e0 1.00e2"
./test_str.sh '(/0.35e0, 0.0e0, 100e0/),"s3"' "3.50e-1 0.00e0 1.00e2"
echo Matrices
./test_str.sh 'reshape((/0.0,1.0,3.0,4.0,4.0,5.0/),(/3,2/),"r1"' "0.0 1.0 3.0 4.0 4.0 5.0"
./test_str.sh 'reshape((/0.0,1.0,2.0,3.0,4.0,5.0/), (/3,2/)),"r1"' "0.0 1.0 2.0 3.0 4.0 5.0"

echo "Testing double precision to string conversion"
echo Scalars:
for i in \
         '0.50e0,"s1" 5e-1' \
         '0.50e0,"s2" 5.0e-1' \
         '0.50e0,"s3" 5.00e-1' \
         '0.50e0,"s4" 5.000e-1' \
         '0.50e0,"s5" 5.0000e-1' \
         '0.50e0,"r0" 0' \
         '0.50e0,"r1" 0.5' \
         '0.50e0,"r2" 0.50' \
         '0.50e0,"r3" 0.500' \
         '0.00d0,"s1" 0e0' \
         '0.00d0,"s2" 0.0e0' \
         '0.00d0,"s3" 0.00e0' \
         '0.00d0,"s4" 0.000e0' \
         '0.00d0,"s5" 0.0000e0' \
         '0.00d0,"r0" 0' \
         '0.00d0,"r1" 0.0' \
         '0.00d0,"r2" 0.00' \
         '0.00d0,"r3" 0.000' \
         '0.00d0,"r4" 0.0000' \
         '1.00d0,"s1" 1e0' \
         '1.00d0,"s2" 1.0e0' \
         '1.00d0,"s3" 1.00e0' \
         '1.00d0,"s4" 1.000e0' \
         '1.00d0,"s5" 1.0000e0' \
         '1.00d0,"r0" 1' \
         '1.00d0,"r1" 1.0' \
         '1.00d0,"r2" 1.00' \
         '1.00d0,"r3" 1.000' \
         '1.00d0,"r4" 1.0000' \
         '-1.00d0,"s1" -1e0' \
         '-1.00d0,"s2" -1.0e0' \
         '-1.00d0,"s3" -1.00e0' \
         '-1.00d0,"s4" -1.000e0' \
         '-1.00d0,"s5" -1.0000e0' \
         '-1.00d0,"r0" -1' \
         '-1.00d0,"r1" -1.0' \
         '-1.00d0,"r2" -1.00' \
         '-1.00d0,"r3" -1.000' \
         '-1.00d0,"r4" -1.0000' \
         '1.00d1,"s1" 1e1' \
         '1.00d1,"s2" 1.0e1' \
         '1.00d1,"s3" 1.00e1' \
         '1.00d1,"s4" 1.000e1' \
         '1.00d1,"s5" 1.0000e1' \
         '1.00d1,"r0" 10' \
         '1.00d1,"r1" 10.0' \
         '1.00d1,"r2" 10.00' \
         '1.00d1,"r3" 10.000' \
         '1.00d1,"r4" 10.0000' \
         '-1.00d1,"s1" -1e1' \
         '-1.00d1,"s2" -1.0e1' \
         '-1.00d1,"s3" -1.00e1' \
         '-1.00d1,"s4" -1.000e1' \
         '-1.00d1,"s5" -1.0000e1' \
         '-1.00d1,"r0" -10' \
         '-1.00d1,"r1" -10.0' \
         '-1.00d1,"r2" -10.00' \
         '-1.00d1,"r3" -10.000' \
         '-1.00d1,"r4" -10.0000' \
         '-1.00d4,"s1" -1e4' \
         '-1.00d4,"s2" -1.0e4' \
         '-1.00d4,"s3" -1.00e4' \
         '-1.00d4,"s4" -1.000e4' \
         '-1.00d4,"s5" -1.0000e4' \
         '-1.00d4,"r0" -10000' \
         '-1.00d4,"r1" -10000.0' \
         '-1.00d4,"r2" -10000.00' \
         '-1.00d4,"r3" -10000.000' \
         '-1.00d4,"r4" -10000.0000' \
         '-1.00d4/3.0d0,"s1" -3e3' \
         '-1.00d4/3.0d0,"s2" -3.3e3' \
         '-1.00d4/3.0d0,"s3" -3.33e3' \
         '-1.00d4/3.0d0,"s4" -3.333e3' \
         '-1.00d4/3.0d0,"s5" -3.3333e3' \
         '-1.00d4/3.0d0,"r0" -3333' \
         '-1.00d4/3.0d0,"r1" -3333.3' \
         '-1.00d4/3.0d0,"r2" -3333.33' \
         '-1.00d4/3.0d0,"r3" -3333.333' \
         '-1.00d4/3.0d0,"r4" -3333.3333' \
         '-2.00d4/3.0d0,"s1" -7e3' \
         '-2.00d4/3.0d0,"s2" -6.7e3' \
         '-2.00d4/3.0d0,"s3" -6.67e3' \
         '-2.00d4/3.0d0,"s4" -6.667e3' \
         '-2.00d4/3.0d0,"s5" -6.6667e3' \
         '-2.00d4/3.0d0,"r0" -6667' \
         '-2.00d4/3.0d0,"r1" -6666.7' \
         '-2.00d4/3.0d0,"r2" -6666.67' \
         '-2.00d4/3.0d0,"r3" -6666.667' \
         '-2.00d4/3.0d0,"r4" -6666.6667' \
         '-99.9d0,"s1" -1e2' \
         '-99.9d0,"s2" -1.0e2' \
         '-99.9d0,"s3" -9.99e1' \
         '-99.9d0,"s4" -9.990e1' \
         '-99.9d0,"s5" -9.9900e1' \
         '-99.9d0,"r0" -100' \
         '-99.9d0,"r1" -99.9' \
         '-99.9d0,"r2" -99.90' \
         '-99.9d0,"r3" -99.900' \
         '-99.9d0,"r4" -99.9000'
do
  ./test_str.sh $i
done
echo Arrays:
./test_str.sh '(/0.0d0/),"s3"' "0.00e0"
./test_str.sh '(/0.0d0, 1.0d0/),"s5"' "0.0000e0 1.0000e0"
./test_str.sh '(/0.0d0, 100d0/),"s3"' "0.00e0 1.00e2"
./test_str.sh '(/0.35d0, 0.0d0, 100d0/),"s3"' "3.50e-1 0.00e0 1.00e2"
echo Matrices
./test_str.sh 'reshape((/0.0d0,1.0d0,3.0d0,4.0d0,4.0d0,5.0d0/),(/3,2/),"r1"' "0.0 1.0 3.0 4.0 4.0 5.0"
./test_str.sh 'reshape((/0.0d0,1.0d0,2.0d0,3.0d0,4.0d0,5.0d0/), (/3,2/)),"r1"' "0.0 1.0 2.0 3.0 4.0 5.0"

echo "Testing complex float to string conversion"
echo "Scalars:"
./test_str.sh '(0.50e0, 0.50e0),"s1"' '(5e-1)+i(5e-1)'
./test_str.sh '(-0.50e0, 0.50e0),"s1"' '(-5e-1)+i(5e-1)'
./test_str.sh '(0.50e0, -0.50e0),"s1"' '(5e-1)+i(-5e-1)'
./test_str.sh '(-0.50e0, -0.50e0),"s1"' '(-5e-1)+i(-5e-1)'
echo "Arrays:"
./test_str.sh '(/(0.50e0, 0.50e0), (1e0, 1e0)/),"s1"' '(5e-1)+i(5e-1) (1e0)+i(1e0)'
./test_str.sh '(/(0.50e0, 0.50e0), (1e0, 1e0), (2e0, 2e0), (-2e0, -2e0)/),"s1"' '(5e-1)+i(5e-1) (1e0)+i(1e0) (2e0)+i(2e0) (-2e0)+i(-2e0)'
echo "Matrices:"
./test_str.sh 'reshape((/(0.50e0, 0.50e0), (1e0, 1e0), (2e0, 2e0), (-2e0, -2e0)/),(/1,4/)),"s1"' '(5e-1)+i(5e-1) (1e0)+i(1e0) (2e0)+i(2e0) (-2e0)+i(-2e0)'
./test_str.sh 'reshape((/(0.50e0, 0.50e0), (1e0, 1e0), (2e0, 2e0), (-2e0, -2e0)/),(/2,2/)),"s1"' '(5e-1)+i(5e-1) (1e0)+i(1e0) (2e0)+i(2e0) (-2e0)+i(-2e0)'


echo "Testing complex double to string conversion"
echo "Scalars:"
./test_str.sh '(0.50d0, 0.50d0),"s1"' '(5e-1)+i(5e-1)'
./test_str.sh '(-0.50d0, 0.50d0),"s1"' '(-5e-1)+i(5e-1)'
./test_str.sh '(0.50d0, -0.50d0),"s1"' '(5e-1)+i(-5e-1)'
./test_str.sh '(-0.50d0, -0.50d0),"s1"' '(-5e-1)+i(-5e-1)'
echo "Arrays:"
./test_str.sh '(/(0.50d0, 0.50d0), (1d0, 1d0)/),"s1"' '(5e-1)+i(5e-1) (1e0)+i(1e0)'
./test_str.sh '(/(0.50d0, 0.50d0), (1d0, 1d0), (2d0, 2d0), (-2d0, -2d0)/),"s1"' '(5e-1)+i(5e-1) (1e0)+i(1e0) (2e0)+i(2e0) (-2e0)+i(-2e0)'
echo "Matrices:"
./test_str.sh 'reshape((/(0.50d0, 0.50d0), (1d0, 1d0), (2d0, 2d0), (-2d0, -2d0)/),(/1,4/)),"s1"' '(5e-1)+i(5e-1) (1e0)+i(1e0) (2e0)+i(2e0) (-2e0)+i(-2e0)'
./test_str.sh 'reshape((/(0.50d0, 0.50d0), (1d0, 1d0), (2d0, 2d0), (-2d0, -2d0)/),(/2,2/)),"s1"' '(5e-1)+i(5e-1) (1e0)+i(1e0) (2e0)+i(2e0) (-2e0)+i(-2e0)'

echo Test Results:
echo Passed: `wc -c passed.score`
echo Failed: `wc -c failed.score`

echo See failed.out for details of failed tests.
