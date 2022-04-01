BENCHMARKS=(
  'tpcc,/Users/TimLing/Documents/CMU/3_15799/project2/tpcc.csv'
)

# Set VERBOSITY to 0 for grading, 2 for development.
VERBOSITY=2

# You should set up a user like this. The script will handle creating the database.
# postgres=# create user project1user with superuser encrypted password 'project1pass';
# CREATE ROLE
# Additionally, export these variables so that they are available to the grading subshells.
export DB_USER="project1user"
export DB_PASS="project1pass"
export DB_NAME="project1db"

# Setup the database using the global constants.
_setup_database() {
  # Drop the project database if it exists.
  PGPASSWORD=${DB_PASS} dropdb --host=localhost --username=${DB_USER} --if-exists ${DB_NAME}
  # Create the project database.
  PGPASSWORD=${DB_PASS} createdb --host=localhost --username=${DB_USER} ${DB_NAME}
}

_setup_benchmark() {
  benchmark="${1}"

  echo "Loading: ${benchmark}"

  # Modify the BenchBase benchmark configuration.
  mkdir -p artifacts/project/
  cp ./config/behavior/benchbase/${benchmark}_config.xml ./artifacts/project/${benchmark}_config.xml
  xmlstarlet edit --inplace --update '/parameters/url' --value "jdbc:postgresql://localhost:5432/${DB_NAME}?preferQueryMode=simple" ./artifacts/project/${benchmark}_config.xml
  xmlstarlet edit --inplace --update '/parameters/username' --value "${DB_USER}" ./artifacts/project/${benchmark}_config.xml
  xmlstarlet edit --inplace --update '/parameters/password' --value "${DB_PASS}" ./artifacts/project/${benchmark}_config.xml
  xmlstarlet edit --inplace --update '/parameters/scalefactor' --value "1" ./artifacts/project/${benchmark}_config.xml
  xmlstarlet edit --inplace --update '/parameters/works/work/time' --value "30" ./artifacts/project/${benchmark}_config.xml
  xmlstarlet edit --inplace --update '/parameters/works/work/rate' --value "unlimited" ./artifacts/project/${benchmark}_config.xml

  # Load the benchmark into the project database.
  doit --verbosity ${VERBOSITY} benchbase_run --benchmark="${benchmark}" --config="./artifacts/project/${benchmark}_config.xml" --args="--create=true --load=true"
}

_dump_database() {
  dump_path="${1}"

  # Dump the project database into directory format.
  rm -rf "./${dump_path}"
  PGPASSWORD=$DB_PASS pg_dump --host=localhost --username=$DB_USER --format=directory --file=./${dump_path} $DB_NAME

  echo "Dumped database to: ${dump_path}"
}

_restore_database() {
  dump_path="${1}"

  # Restore the project database from directory format.
  PGPASSWORD=${DB_PASS} pg_restore --host=localhost --username=$DB_USER --clean --if-exists --dbname=${DB_NAME} ./${dump_path}

  echo "Restored database from: ${dump_path}"
}

_clear_log_folder() {
  sudo bash -c "rm -rf /opt/homebrew/var/postgres/log/*"
  echo "Cleared all query logs."
}

_copy_logs() {
  save_path="${1}"

  # TODO(WAN): Is there a way to ensure all flushed?
  sleep 10
  sudo bash -c "cat /opt/homebrew/var/postgres/log/*.csv > ${save_path}"
  echo "Copied all query logs to: ${save_path}"
}

kill_descendant_processes() {
  local pid="$1"
  local and_self="${2:-false}"
  if children="$(pgrep -P "$pid")"; then
    for child in $children; do
      kill_descendant_processes "$child" true
    done
  fi
  if [[ "$and_self" == true ]]; then
    sudo kill -9 "$pid"
  fi
}

exit_cleanly() {
  kill_descendant_processes $$
}

main() {
  trap exit_cleanly SIGINT
  trap exit_cleanly SIGTERM

  set -e
  # Ask for sudo now, we're going to need it.
  sudo --validate
  # jq to parse parameters from student scripts.
  # sudo apt-get -qq install jq
  # xmlstarlet to edit BenchBase XML configurations.
  # sudo apt-get -qq install xmlstarlet

  # Clean up before running.
  rm -rf ./artifacts/
  rm -rf ./build/

  # Use Andy's version of BenchBase.
  doit benchbase_clone --repo_url="https://github.com/apavlo/benchbase.git" --branch_name="main"
  cp ./build/benchbase/config/postgres/15799_starter_config.xml ./config/behavior/benchbase/epinions_config.xml
  cp ./build/benchbase/config/postgres/15799_indexjungle_config.xml ./config/behavior/benchbase/indexjungle_config.xml

  benchmark_dump_folder="./artifacts/project/dumps"
  # Create the folder for all the benchmark dumps.
  mkdir -p "./${benchmark_dump_folder}"
  # Create the folder for all evaluation summaries.
  evaluations_folder="./artifacts/project/evaluations"
  mkdir -p "./${evaluations_folder}"

  for benchmark_spec in "${BENCHMARKS[@]}"; do
    while IFS=',' read -r benchmark workload_csv; do
      benchmark_dump_path="./${benchmark_dump_folder}/${benchmark}_primary"
      evaluation_baseline_path="${evaluations_folder}/${benchmark}/baseline/"

      # Create the project database.
      _setup_database
      # Load the benchmark data.
      _setup_benchmark "${benchmark}"
      # Dump the project database to benchmark_primary.
      _dump_database "${benchmark_dump_path}"
      # Generate the base workload CSV.
      _clear_log_folder

      doit project1_enable_logging
      doit benchbase_run --benchmark="${benchmark}" --config="./artifacts/project/${benchmark}_config.xml" --args="--execute=true"
      doit project1_disable_logging
      _copy_logs "${workload_csv}"
      _clear_log_folder
    done <<<"$benchmark_spec"
  done
}

main
exit_cleanly
