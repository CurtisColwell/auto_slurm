#!/bin/bash
set -e

SCRIPTS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORKING_DIR=$(dirname "$SCRIPTS_DIR")
INPUT_DIR="$WORKING_DIR/input"
OUTPUT_DIR="$WORKING_DIR/output"

main() {
	if [ -z $GROUP_NAME ]; then
		echo "Please input group name for submissions"
		read GROUP_NAME
		echo "export GROUP_NAME=$GROUP_NAME" >> ~/.bashrc;
	fi

	echo "Submitting under group name $GROUP_NAME"

	if [ ! -d "$INPUT_DIR" ]; then
		echo "No input file directory found."
		echo "Users must place their input files in the auto_slurm/input/ directory."
		exit
	fi

	# Setup folders if they don't already exist
	mkdir -p "$OUTPUT_DIR"

	read_args "$@"

	if [ -z "$ARG_NO_UPDATE" ]; then
		update_repo
	fi
	check_for_jobs
}

read_args()
{
	ARG_NO_UPDATE=
	PARTITION="${1:-"short"}"
	for arg in "$@"; do
		case $arg in
			-n)
				ARG_NO_UPDATE="true";;
			*)
				PARTITION="$arg";;
		esac
	done
}

update_repo() {
	cd "$SCRIPTS_DIR"
	git checkout -q master
	PULL_RESULT=$(git pull)
	if [ ! "$PULL_RESULT" == "Already up-to-date." ]; then
		echo "Scripts have been updated, please run the script again."
		exit
	fi
}

check_for_jobs()
{
	echo ""
	cd "$INPUT_DIR"

	# Find input files
	INPUT_NAMES=()
	while IFS=  read -r -d $'\0'; do
		# Remove the leading .
		INPUT_NAME=${REPLY##*/}
		INPUT_NAME=${INPUT_NAME%.*}
		INPUT_NAMES+=("$INPUT_NAME")
	done < <(find . -type f -print0)

	# Submit new job if input file has no corresponding output file
	num_jobs=0
	for input_name in "${INPUT_NAMES[@]}"; do
		if [ ! -e "$OUTPUT_DIR/$input_name.out" ]; then
			if submit_job "$INPUT_DIR/$input_name.inp"; then
				num_jobs=$((num_jobs + 1))
			fi
		fi
	done

	echo ""
	echo "$num_jobs jobs submitted."
	echo "Output, checkpoint and formatted checkpoint files will be placed under:"
	echo "$OUTPUT_DIR/"
	echo "Use the following command to check on your job queue:"
	echo '	squeue -u' $USER
}

submit_job()
{
	INPUT_FILE="$1"

	JOB_NAME=${INPUT_FILE##*/}
	JOB_NAME=${JOB_NAME%.*}

	# Check if input file exists
	if [ ! -e "$INPUT_FILE" ]; then
		echo "Input file could not be found."
		echo "	$INPUT_FILE"
		return 1
	fi

	# Check if job already exists
  QUEUE_NAME=${JOB_NAME%.*}
	if squeue -u $USER | grep -n "${QUEUE_NAME:0:8}"; then
		echo "A job named $JOB_NAME is already in the queue."
		return 1
	fi

	echo "Submitting job named $JOB_NAME"

	# Call the job script with the given arguments
	sbatch --job-name="$JOB_NAME" --output="$OUTPUT_DIR/$JOB_NAME.out" --partition=$PARTITION --account=$GROUP_NAME "$SCRIPTS_DIR/gamess.srun"
}

main "$@"
