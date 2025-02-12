#!/bin/bash
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=24
#SBATCH -t 12:00:00
#SBATCH --mem=40G
#SBATCH -o out.%j
#SBATCH -e err.%j
#SBATCH -J #DONT_MODIFY_THIS
#SBATCH -p shared
#SBATCH --constraint="lustre"
#SBATCH --account= #YOUR_ACCOUNT
#SBATCH --export=ALL
#SBATCH --signal=B:USR1@180


function email (){
    #email an update
    echo -e "Subject: ${SLURM_JOB_NAME}_${SLURM_JOB_ID}\n${SLURM_JOB_NAME}_${SLURM_JOB_ID} geometrey optimization and nmr params have started!\n"  > mail_${SLURM_JOB_ID}.txt
    echo -e  $1 >> mail_${SLURM_JOB_ID}.txt
    squeue -u your_username >> mail_${SLURM_JOB_ID}.txt
    wait
    curl -s --ssl-reqd   --url 'smtps://smtp.gmail.com:465'   --user 'your_email:Password' \
    --mail-from 'test'   --mail-rcpt 'your_email'   --upload-file mail_${SLURM_JOB_ID}.txt
    rm mail_${SLURM_JOB_ID}.txt
}

# Create new scratch directory and add a variable for the new directory name
NEW_DIR="/expanse/lustre/scratch/${USER}/temp_project/castep/${SLURM_JOB_NAME}_${SLURM_JOB_ID}"
DATA="/home/${USER}/project/${SLURM_JOB_NAME}/"

# Create the new directory
mkdir -p "$NEW_DIR"
[ -d ${DATA} ] || mkdir ${DATA}

# Load necessary modules
module reset
module load cpu/0.15.4
module load gcc
module load openmpi
module load fftw
module load intel-mkl
# module load castep # CASTEP is NOT installed on sdsc expanse. Used local castep mpi instead. 
#cp -R /home/${USER}/CASTEP-24.1/bin/linux_x86_64_gfortran10--mpi/ /expanse/lustre/scratch/${USER}/temp_project/CASTEP_24.1

export PATH="/expanse/lustre/scratch/${USER}/temp_project/CASTEP_24.1/linux_x86_64_gfortran10--mpi/:$PATH"
# Copy the CASTEP input files to the new directory
cp ${SLURM_JOB_NAME}* "$NEW_DIR"/ # change to your current working directory
cp ${SLURM_JOB_NAME}* ${DATA}

# Move to the new directory
cd "$NEW_DIR"

# Data Backup Function
data_backup()
{
    echo Time out in 180 seconds. Backing up at `date`
    cp ${SLURM_JOB_NAME}.check ${DATA}
    cp ${SLURM_JOB_NAME}.cst_esp ${DATA}
    cp ${SLURM_JOB_NAME}.castep* ${DATA}
    cp ${SLURM_JOB_NAME}-out.cif ${DATA}
    cp ${SLURM_JOB_NAME}.magres ${DATA}
}
trap 'data_backup' USR1

# Uncomment GeoOpt, Comment NMR
sed -i ':a;s/#task : geometryoptimisation/task : geometryoptimisation/g;ta' ${SLURM_JOB_NAME}.param
sed -i '0,/task : magres/s//#task : magres/' ${SLURM_JOB_NAME}.param
sed -i '0,/magres_task : NMR/s//#magres_task : NMR/' ${SLURM_JOB_NAME}.param

# Disable OpenMP multi-threading
export OMP_NUM_THREADS=1

#run castep script - GeoOpt
counter=0
sed -i 's/GEOM_MAX_ITER        : \w\w\w/GEOM_MAX_ITER        : 004/' *.param
while ! grep -q 'LBFGS: Geometry optimization completed successfully.'  ${SLURM_JOB_NAME}.castep ; do
    echo loop $(( $counter + 1 )) starts at `date`
    SEED=`shuf -i 1-100000000 -n 1`
    sed -i '0,/RAND_SEED = .*/s//RAND_SEED = '$SEED'/' *.param
    echo Random Seed for this loop is $SEED
    if ! mpirun -np 24 castep.mpi ${SLURM_JOB_NAME} ; then
        echo CASTEP runtime error at `date`
        break
    fi &
    wait
    counter=$(( $counter + 1 ))
    if [ $counter -eq 6 ] ; then
        sed -i 's/GEOM_MAX_ITER        : \w\w\w/GEOM_MAX_ITER        : 010/' *.param
    else 
        if [ $counter -eq 10 ] ; then
            sed -i 's/GEOM_MAX_ITER        : \w\w\w/GEOM_MAX_ITER        : 200/' *.param
        else
            if [ $counter -eq 12 ] ; then
                break
            fi
        fi
    fi
done

#run castep script - NMR
if grep -q 'LBFGS: Geometry optimization completed successfully.'  ${SLURM_JOB_NAME}.castep
then
    echo GeoOpt finished. NMR calculation starts at `date`
    sed -i '0,/task : geometryoptimisation/s//#task : geometryoptimisation/' ${SLURM_JOB_NAME}.param
    sed -i ':a;s/#task : magres/task : magres/g;ta' ${SLURM_JOB_NAME}.param
    sed -i ':a;s/#magres_task : NMR/magres_task : NMR/g;ta' ${SLURM_JOB_NAME}.param
    mpirun -np 24 castep.mpi ${SLURM_JOB_NAME}
    echo NMR calculation finished at `date`
else
    echo WARNING: GeoOpt may not be finished. NMR calculation NOT starting `date`
fi


# Optional: Post-processing steps, if required
cp ${SLURM_JOB_NAME}.check ${DATA}
cp ${SLURM_JOB_NAME}.cst_esp ${DATA}
cp ${SLURM_JOB_NAME}.castep* ${DATA}
cp ${SLURM_JOB_NAME}-out.cif ${DATA}
cp ${SLURM_JOB_NAME}.magres ${DATA}

# Move back to the original directory
cd -
