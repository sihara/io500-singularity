#!/bin/bash
#SBATCH -p src
#SBATCH --nodes=10
#SBATCH --ntasks-per-node=1
#SBATCH -o io_500_out_%j
#SBATCH -e io_500_err_%J
#SBATCH --overcommit

./myio500.sh myio500.ini
