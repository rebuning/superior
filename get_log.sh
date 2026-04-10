#!/bin/bash
# Version: 1.0.0.20251202
# Version: 1.1.0.20260130

# # # get_log # # #
function get_log() {
  PRJ_LOG="$1"
  AMB_LOG="$2"
  AMB_FILTER="$3"

  shift 3

  echo "       Project is ${PRJ_LOG}"
  echo "   Environment is ${AMB_LOG}"
  echo "Adapter filter is ${AMB_FILTER}"

 case "${PRJ_LOG}" in
  SUPG)
      case "${AMB_LOG}" in
          STG1)
              PWD_LOG="eyaCR]ng5cr#1kkK_zGM"
              DEFAULT_URL="https://axlkzc72fp8r.swiftobjectstorage.us-phoenix-1.oci.customer-oci.com/v1/axlkzc72fp8r/rcib-logs-bucket-stg1"
              ;;
          PRD1)
              PWD_LOG="KGFH)E)WcI96Momf#9L0"
              DEFAULT_URL="https://axlkzc72fp8r.swiftobjectstorage.us-phoenix-1.oci.customer-oci.com/v1/axlkzc72fp8r/rcib-logs-bucket-prd1"
              ;;
          *)
              echo "Invalid environment: ${AMB_LOG} for ${PRJ_LOG}"
              exit 1
              ;;
      esac
      ;;
  *)
      echo "Invalid project: ${PRJ_LOG}"
      exit 1
      ;;
esac

  # If blank - fetches list of logs
  if [ -z "$1" ]; then
    FLAG_LIST=1
    URL_LOG=${DEFAULT_URL}
  else
    FLAG_LIST=0

    # And do not pass URL - concatenate URL + parameter
    if [[ "$1" != https://* ]]; then
      URL_LOG="${DEFAULT_URL}/$1"
    else
      URL_LOG="$1"
    fi

  fi

  FIL_LOG="rcib-logs-bucket-${AMB_LOG}"
  FIL_LOG=$(echo "${FIL_LOG}" | tr '[:upper:]' '[:lower:]')

  if [ -n "${HOST_MACHINE}" ] && [ "${HOST_MACHINE}" == "GIT" ]; then
    # Pasta de logs
    cd "/c/Users/${USERNAME}/Downloads/logs_oci/${PRJ_LOG}/${AMB_LOG}" || return
    pwd
  else
    echo "HOST_MACHINE = ${HOST_MACHINE}. No action taken."
  fi

  #if [ -n "${AMB_FILTER}" ]; then
  #  URL_LOG="${URL_LOG}?prefix=${AMB_FILTER}"
  #  echo ${URL_LOG}
  #fi

  # Extract the last token after '/' to get the file name
  FILE_FROM_URL="${URL_LOG##*/}"

  HTTP_CODE_CURL=$(curl -u "${AMB_LOG}/rcib_logs_bucket:${PWD_LOG}" -O -X GET "${URL_LOG}" -w "%{http_code}")

  #echo ${HTTP_CODE_CURL}

  if [[ "${HTTP_CODE_CURL}" -lt 200 || "${HTTP_CODE_CURL}" -ge 300 ]]; then
    echo "HTTP Error ${HTTP_CODE_CURL}"
    echo "Server response:"
    cat ${FILE_FROM_URL}
    exit 1
  fi

  # listed - rename the file to .json
  if [ "$FLAG_LIST" -eq 1 ]; then
    if [ -f ${FIL_LOG} ]; then
      mv "${FIL_LOG}" "${FIL_LOG}.json"
    else
      echo "File ${FIL_LOG} not found."
    fi
  else    

    if [[ "${FILE_FROM_URL,,}" == *.zip ]]; then
      echo "ZIP file detected: ${FILE_FROM_URL}"

      # Unzip the file into the current directory
      # Unzip into the current directory
      if unzip -oq "${FILE_FROM_URL}"; then
        echo "Unzip successful. Deleting ZIP file..."
        rm -f "${FILE_FROM_URL}"
      else
        echo "Unzip failed. ZIP file was not deleted."
      fi

      echo "Unzipped in current directory."
    else
      echo "The file is not a .zip archive. No action taken."
    fi

  fi
}
# # # get_log # # #

set +x

# Default Parameter
PRJ_SHELL="SUPG"
AMB_SHELL="STG1"
FILTER_SHELL="NULL"

# Parsing of the -p parameter
while getopts "p:a:f:d" opt; do
  case "$opt" in
    p) PRJ_SHELL="$OPTARG" ;;
    a) AMB_SHELL="$OPTARG" ;;
    f) FILTER_SHELL="$OPTARG" ;;
    d) set -x ;;
    *) echo "Usage: $0 [-p PRJ_SHELL] [-a AMB_SHELL] param1 param2"; exit 1 ;;
  esac
done

# Remove the parameters already read
shift $((OPTIND -1))

get_log ${PRJ_SHELL} ${AMB_SHELL} ${FILTER_SHELL} $@
 