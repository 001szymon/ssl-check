#!/usr/bin/env bash
#
# Source code: https://github.com/001szymon/ssl-check
#
# Last Update: 21-MAR-2021
#

# Cleanup temp files if they exist
trap cleanup EXIT INT TERM QUIT

PATH=/bin:/usr/bin:/sbin:/usr/sbin:/usr/local/bin:/usr/local/ssl/bin:/usr/sfw/bin
export PATH

# Location of system binaries
AWK=$(command -v awk)
DATE=$(command -v date)
GREP=$(command -v grep)
OPENSSL=$(command -v openssl)
PRINTF=$(command -v printf)
SED=$(command -v sed)
MKTEMP=$(command -v mktemp)
FIND=$(command -v find)

#####################################################
# Purpose: Remove temporary files if the script doesn't
#          exit() cleanly
#####################################################
cleanup() {
    if [ -f "${CERT_TMP}" ]; then
        rm -f "${CERT_TMP}"
    fi

    if [ -f "${ERROR_TMP}" ]; then
     rm -f "${ERROR_TMP}"
    fi
}


#############################################################################
# Purpose: Convert a date from MONTH-DAY-YEAR to Julian format
# Arguments:
#   $1 -> Month (e.g., 06)
#   $2 -> Day   (e.g., 08)
#   $3 -> Year  (e.g., 2006)
#############################################################################
date2julian() {

    if [ "${1}" != "" ] && [ "${2}" != "" ] && [ "${3}" != "" ]; then
        ## Since leap years add aday at the end of February,
        ## calculations are done from 1 March 0000 (a fictional year)
        d2j_tmpmonth=$((12 * $3 + $1 - 3))

        ## If it is not yet March, the year is changed to the previous year
        d2j_tmpyear=$(( d2j_tmpmonth / 12))

        ## The number of days from 1 March 0000 is calculated
        ## and the number of days from 1 Jan. 4713BC is added
        echo $(( (734 * d2j_tmpmonth + 15) / 24
                 - 2 * d2j_tmpyear + d2j_tmpyear/4
                 - d2j_tmpyear/100 + d2j_tmpyear/400 + $2 + 1721119 ))
    else
        echo 0
    fi
}

#############################################################################
# Purpose: Convert a string month into an integer representation
# Arguments:
#   $1 -> Month name (e.g., Sep)
#############################################################################
getmonth()
{
    case ${1} in
        Jan) echo 1 ;;
        Feb) echo 2 ;;
        Mar) echo 3 ;;
        Apr) echo 4 ;;
        May) echo 5 ;;
        Jun) echo 6 ;;
        Jul) echo 7 ;;
        Aug) echo 8 ;;
        Sep) echo 9 ;;
        Oct) echo 10 ;;
        Nov) echo 11 ;;
        Dec) echo 12 ;;
          *) echo 0 ;;
    esac
}

#############################################################################
# Purpose: Calculate the number of seconds between two dates
#############################################################################
date_diff()
{
    if [ "${1}" != "" ] && [ "${2}" != "" ]; then
        echo $((${2} - ${1}))
    else
        echo 0
    fi
}

#####################################################################
# Purpose: Print a line with the expiraton interval
# Arguments:
#   $1 -> Hostname
#   $2 -> TCP Port
#   $3 -> isValid
#   $4 -> Issuer
#   $5 -> Common Name
#####################################################################
prints()
{
    ${PRINTF} "%-35s %-17s %-8s\n" "$5" "$4" "$3"
    #${PRINTF} "%-35s %-17s %-8s\n" "$1" "$4" "$3"
}

print_heading()
{
    ${PRINTF} "\n%-35s %-17s %-8s\n" "subject" "issuer" "isValid"
    echo "----------------------------------- ----------------- --------"
}

##########################################
# Help
##########################################
usage()
{
    echo "Usage: $0 [-h]"
    echo "       { [ -s common_name ] && [ -p port] }"
    echo ""
    echo "  -h                : Print this screen"
    echo "  -p port           : Port to connect to (default:443)"
    echo "  -s commmon_name   : Server to connect to"
    echo ""
}

##########################################################################
# Purpose: Connect to a server ($1) and port ($2) to see if a certificate
#          has expired
##########################################################################
check_server_status() {

    PORT="$2"
    case "$PORT" in
        smtp|25|submission|587) TLSFLAG="-starttls smtp";;
        pop3|110)               TLSFLAG="-starttls pop3";;
        imap|143)               TLSFLAG="-starttls imap";;
        ftp|21)                 TLSFLAG="-starttls ftp";;
        xmpp|5222)              TLSFLAG="-starttls xmpp";;
        xmpp-server|5269)       TLSFLAG="-starttls xmpp-server";;
        irc|194)                TLSFLAG="-starttls irc";;
        postgres|5432)          TLSFLAG="-starttls postgres";;
        mysql|3306)             TLSFLAG="-starttls mysql";;
        lmtp|24)                TLSFLAG="-starttls lmtp";;
        nntp|119)               TLSFLAG="-starttls nntp";;
        sieve|4190)             TLSFLAG="-starttls sieve";;
        ldap|389)               TLSFLAG="-starttls ldap";;
        *)                      TLSFLAG="";;
    esac

    OPTIONS="-connect ${1}:${2} -servername ${1} $TLSFLAG"
    
    echo "" | "${OPENSSL}" s_client $OPTIONS 2> "${ERROR_TMP}" 1> "${CERT_TMP}"

    if "${GREP}" -i "Connection refused" "${ERROR_TMP}" > /dev/null; then
        prints "${1}" "${2}" "Connection refused" "Unknown"
    elif "${GREP}" -i "No route to host" "${ERROR_TMP}" > /dev/null; then
        prints "${1}" "${2}" "No route to host" "Unknown"
    elif "${GREP}" -i "gethostbyname failure" "${ERROR_TMP}" > /dev/null; then
        prints "${1}" "${2}" "Cannot resolve domain" "Unknown"
    elif "${GREP}" -i "Operation timed out" "${ERROR_TMP}" > /dev/null; then
        prints "${1}" "${2}" "Operation timed out" "Unknown"
    elif "${GREP}" -i "ssl handshake failure" "${ERROR_TMP}" > /dev/null; then
        prints "${1}" "${2}" "SSL handshake failed" "Unknown"
    elif "${GREP}" -i "connect: Connection timed out" "${ERROR_TMP}" > /dev/null; then
        prints "${1}" "${2}" "Connection timed out" "Unknown"
    elif "${GREP}" -i "Name or service not known" "${ERROR_TMP}" > /dev/null; then
        prints "${1}" "${2}" "Unable to resolve the DNS name ${1}" "Unknown"
    else
        check_file_status "${CERT_TMP}" "${1}" "${2}"
    fi
}

#####################################################
### Check the expiration status of a certificate file
#####################################################
check_file_status() {

    CERTFILE="${1}"
    HOST="${2}"
    PORT="${3}"

    ### Check to make sure the certificate file exists
    if [ ! -r "${CERTFILE}" ] || [ ! -s "${CERTFILE}" ]; then
        echo "ERROR: The file named ${CERTFILE} is unreadable or doesn't exist"
        echo "ERROR: Please check to make sure the certificate for ${HOST}:${PORT} is valid"
        return
    fi

    # Extract the expiration date from the ceriticate
    CERTDATE=$("${OPENSSL}" x509 -in "${CERTFILE}" -enddate -noout -inform pem | \
                    "${SED}" 's/notAfter\=//')

    # Extract the issuer from the certificate
    CERTISSUER=$("${OPENSSL}" x509 -in "${CERTFILE}" -issuer -noout -inform pem | \
                     "${AWK}" 'BEGIN {RS=", " } $0 ~ /^O =/ { print substr($0,5,17)}')

    ### Grab the common name (CN) from the X.509 certificate
    COMMONNAME=$("${OPENSSL}" x509 -in "${CERTFILE}" -subject -noout -inform pem | \
                     "${SED}" -e 's/.*CN = //' | \
                     "${SED}" -e 's/, .*//')

    ### Split the result into parameters, and pass the relevant pieces to date2julian
    echo "TEEEEEEEEEEEEEEEEEEEESTTTTTTTTTTTT"
    echo ${CERTDATE}
    echo "TEEEEEEEEEEEEEEEEEEEESTTTTTTTTTTTT"
    set -- ${CERTDATE}
    MONTH=$(getmonth "${1}")
    echo ${MONTH}
    echo "TEEEEEEEEEEEEEEEEEEEESTTTTTTTTTTTT"

    # Convert the date to seconds, and get the diff between NOW and the expiration date
    CERTJULIAN=$(date2julian "${MONTH#0}" "${2#0}" "${4}")
    CERTDIFF=$(date_diff "${NOWJULIAN}" "${CERTJULIAN}")

    if [ "${CERTDIFF}" -lt 0 ]; then
        prints "${HOST}" "${PORT}" "False" "${CERTISSUER}" "${COMMONNAME}"
    else
        prints "${HOST}" "${PORT}" "True" "${CERTISSUER}" "${COMMONNAME}"
    fi  
}

#################################
### Start of main program
#################################
while getopts :hp:s: option
do
    case "${option}" in
        h) usage
           exit 1;;
        p) PORT=$OPTARG;;
        s) HOST=$OPTARG;;
       \?) usage
           exit 1;;
    esac
done

### Check to make sure a openssl utility is available
if [ ! -f "${OPENSSL}" ]; then
    echo "ERROR: The openssl binary does not exist in ${OPENSSL}."
    echo "FIX: Please modify the \${OPENSSL} variable in the program header."
    exit 1
fi

### Check to make sure a date utility is available
if [ ! -f "${DATE}" ]; then
    echo "ERROR: The date binary does not exist in ${DATE} ."
    echo "FIX: Please modify the \${DATE} variable in the program header."
    exit 1
fi

### Check to make sure a grep and find utility is available
if [ ! -f "${GREP}" ] || [ ! -f "${FIND}" ]; then
    echo "ERROR: Unable to locate the grep and find binary."
    echo "FIX: Please modify the \${GREP} and \${FIND} variables in the program header."
    exit 1
fi

### Check to make sure the mktemp and printf utilities are available
if [ ! -f "${MKTEMP}" ] || [ -z "${PRINTF}" ]; then
    echo "ERROR: Unable to locate the mktemp or printf binary."
    echo "FIX: Please modify the \${MKTEMP} and \${PRINTF} variables in the program header."
    exit 1
fi

### Check to make sure the sed and awk binaries are available
if [ ! -f "${SED}" ] || [ ! -f "${AWK}" ]; then
    echo "ERROR: Unable to locate the sed or awk binary."
    echo "FIX: Please modify the \${SED} and \${AWK} variables in the program header."
    exit 1
fi

# Place to stash temporary files
CERT_TMP=$($MKTEMP /var/tmp/cert.XXXXXX)
ERROR_TMP=$($MKTEMP /var/tmp/error.XXXXXX)

### Baseline the dates so we have something to compare to
MONTH=$(${DATE} "+%m")
DAY=$(${DATE} "+%d")
YEAR=$(${DATE} "+%Y")
NOWJULIAN=$(date2julian "${MONTH#0}" "${DAY#0}" "${YEAR}")

### Touch the files prior to using them
if [ -n "${CERT_TMP}" ] && [ -n "${ERROR_TMP}" ]; then
    touch "${CERT_TMP}" "${ERROR_TMP}"
else
    echo "ERROR: Problem creating temporary files"
    echo "FIX: Check that mktemp works on your system"
    exit 1
fi

### If a HOST was passed on the cmdline, use that value
if [ "${HOST}" != "" ]; then
    print_heading
    check_server_status "${HOST}" "${PORT:=443}"
else
    usage
    exit 1
fi

exit 0
