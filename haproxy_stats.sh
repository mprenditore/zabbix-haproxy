#!/bin/bash
set -o pipefail

debug() {
    if [[ "${DEBUG}" -eq 1 ]]; then  # return immediately if debug is disabled
        local T=$(date +"%Y-%m-%d_%H:%M:%S.%N")
        echo "$T $$ (DEBUG) $@" >> ${STATS_LOG_FILE}
        if [[ "${DEBUG_ONLY_LOG}" -ne 1 ]]; then
            echo >&2 "$T $$ (DEBUG) $@"
        fi
    fi
}

fail() {
    local _exit_code=${1:-1}
    shift 1
    if [[ -n "$1" ]]; then
        if [[ "${DEBUG}" -eq 1 ]]; then
            debug "$@"
        fi
        echo >&2 "$@"
    fi
    rm -f ${TMPFILE} ${RESTTMPFILE}
    exit $_exit_code
}


metric_type="$1"
[[ $metric_type != "stat" ]] && [[ $metric_type != "info" ]] && fail 128 "ERROR: Metric '$metric_type' NOT SUPPORTED"
shift
if [[ $metric_type == "stat" ]]; then
    pxname="$1"
    svname="$2"
    stat="$3"
else
    stat=$1
fi

SCRIPT_DIR=`dirname $0`
CONF_FILE="${SCRIPT_DIR}/haproxy_zbx.conf"

# default constant values - can be overridden by the $CONF_FILE
DEBUG=0
DEBUG_ONLY_LOG=0  # only debug in logfile
HAPROXY_SOCKET="/var/run/haproxy/info.sock"
HAPROXY_STATS_IP=""  # set it to the HAProxy IP to use TCP instead SOCKET
QUERYING_METHOD="SOCKET"
CACHE_STATS_FILEPATH="/var/tmp/haproxy_stat.cache"
CACHE_STATS_EXPIRATION=60  # in seconds
CACHE_INFO_FILEPATH="/var/tmp/haproxy_info.cache"  ## unused ATM
CACHE_INFO_EXPIRATION=60  # in seconds ## unused ATM
STATS_LOG_FILE="/var/tmp/haproxy_stat.log"
GET_STATS=1  # when you update stats cache outsise of the script
GET_INFO=1  # when you update info cache outsise of the script
SOCAT_BIN="$(which socat)"
FLOCK_BIN="$(which flock)"
FLOCK_WAIT=15 # maximum number of seconds that "flock" waits for acquiring a lock
FLOCK_SUFFIX='.lock'
CUR_TIMESTAMP="$(date '+%s')"

TMPFILE=`mktemp`
RESTTMPFILE=`mktemp`

# constants override
if [ -f ${CONF_FILE} ]; then
    source ${CONF_FILE}
fi

if [[ "$HAPROXY_STATS_IP" =~ (25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?):[0-9]{1,5} ]]; then
    QUERYING_METHOD="TCP"
    NC_BIN="$(which nc)"
fi

if [[ $metric_type == "stat" ]]; then
    CACHE_FILEPATH=$CACHE_STATS_FILEPATH
    CACHE_EXPIRATION=$CACHE_STATS_EXPIRATION
    GET_TYPE=$GET_STATS
else
    CACHE_FILEPATH=$CACHE_INFO_FILEPATH
    CACHE_EXPIRATION=$CACHE_INFO_EXPIRATION
    GET_TYPE=$GET_INFO
fi

debug "DEBUG_ONLY_LOG         => $DEBUG_ONLY_LOG"
debug "STATS_LOG_FILE         => $STATS_LOG_FILE"
debug "SOCAT_BIN              => $SOCAT_BIN"
debug "NC_BIN                 => $NC_BIN"
debug "metric_type            => $metric_type"
debug "CACHE_FILEPATH         => $CACHE_FILEPATH"
debug "CACHE_EXPIRATION       => $CACHE_EXPIRATION seconds"
debug "HAPROXY_SOCKET         => $HAPROXY_SOCKET"
debug "pxname   => ${pxname:-(NOT NEEDED FOR INFO)}"
debug "svname   => ${svname:-(NOT NEEDED FOR INFO)}"
debug "stat     => $stat"

# check if socat is available in path
if [ "$GET_STATS" -eq 1 ] && [[ $QUERYING_METHOD == "SOCKET" && -z "$SOCAT_BIN" ]] || [[ $QUERYING_METHOD == "TCP" &&  -z "$NC_BIN" ]]
then
  fail 126 'ERROR: cannot find socat binary'
fi

# check cache files

check_cache(){
    # if we are getting stats:
    #   check if we can write to cache file, if it exists
    #     or cache file path, if it does not exist
    #   check if HAPROXY socket is writable
    # if we are NOT getting stats:
    #   check if we can read the stats cache file
    if [ "$GET_TYPE" -eq 1 ]; then
        if [ -e "$HAPROXY_SOCKET" ]; then
            if [ ! -r "$HAPROXY_SOCKET" ]; then
                fail 126 'ERROR: cannot read socket file'
            fi
        else
            fail 126 "ERROR: HAProxy Socket file ($HAPROXY_SOCKET) doesn't exists"
        fi

        if [ -e "$CACHE_FILEPATH" ]; then
            if [ ! -w "$CACHE_FILEPATH" ]; then
                fail 126 "ERROR: $metric_type cache file exists, but is not writable"
            elif [ ! -s "$CACHE_FILEPATH" ]; then
                debug "ERROR: $metric_type cache file exists, but it's empty -> destroying it!"
                rm -f "$CACHE_FILEPATH"
                if [ $? -ne 0 ]; then
                    fail 126 "ERROR: problems deleting $metric_type cache file, please check permissions!"
                fi
            fi
        fi
        if [[ $QUERYING_METHOD == "SOCKET" && ! -w $HAPROXY_SOCKET ]]; then
            fail 126 "ERROR: haproxy socket is not writable"
        fi
    elif [ ! -r "$CACHE_FILEPATH" ]; then
        fail 126 "ERROR: cannot read $metric_type cache file"
    fi
}

# index:name:default
STATS_MAP="
1:pxname:@
2:svname:@
3:qcur:9999999999
4:qmax:0
5:scur:9999999999
6:smax:0
7:slim:0
8:stot:@
9:bin:9999999999
10:bout:9999999999
11:dreq:9999999999
12:dresp:9999999999
13:ereq:9999999999
14:econ:9999999999
15:eresp:9999999999
16:wretr:9999999999
17:wredis:9999999999
18:status:UNK
19:weight:9999999999
20:act:9999999999
21:bck:9999999999
22:chkfail:9999999999
23:chkdown:9999999999
24:lastchg:9999999999
25:downtime:0
26:qlimit:0
27:pid:@
28:iid:@
29:sid:@
30:throttle:9999999999
31:lbtot:9999999999
32:tracked:9999999999
33:type:9999999999
34:rate:9999999999
35:rate_lim:@
36:rate_max:@
37:check_status:@
38:check_code:@
39:check_duration:9999999999
40:hrsp_1xx:@
41:hrsp_2xx:@
42:hrsp_3xx:@
43:hrsp_4xx:@
44:hrsp_5xx:@
45:hrsp_other:@
46:hanafail:@
47:req_rate:9999999999
48:req_rate_max:@
49:req_tot:9999999999
50:cli_abrt:9999999999
51:srv_abrt:9999999999
52:comp_in:0
53:comp_out:0
54:comp_byp:0
55:comp_rsp:0
56:lastsess:9999999999
57:last_chk:@
58:last_agt:@
59:qtime:0
60:ctime:0
61:rtime:0
62:ttime:0
0:srvtot:CUSTOM
0:alljson:CUSTOM
"

INFO_MAP="
Name
Version
Release_date
Nbthread
Nbproc
Process_num
Pid
Uptime
Uptime_sec
Memmax_MB
PoolAlloc_MB
PoolUsed_MB
PoolFailed
Ulimit-n
Maxsock
Maxconn
Hard_maxconn
CurrConns
CumConns
CumReq
MaxSslConns
CurrSslConns
CumSslConns
Maxpipes
PipesUsed
PipesFree
ConnRate
ConnRateLimit
MaxConnRate
SessRate
SessRateLimit
MaxSessRate
SslRate
SslRateLimit
MaxSslRate
SslFrontendKeyRate
SslFrontendMaxKeyRate
SslFrontendSessionReuse_pct
SslBackendKeyRate
SslBackendMaxKeyRate
SslCacheLookups
SslCacheMisses
CompressBpsIn
CompressBpsOut
CompressBpsRateLim
ZlibMemUsage
MaxZlibMemUsage
Tasks
Run_queue
Idle_pct
node
info_alljson
"
if [[ $metric_type == "stat" ]]; then
    _STAT=$(echo -e "$STATS_MAP" | grep :${stat}:)
    _INDEX=${_STAT%%:*}
    _DEFAULT=${_STAT##*:}
    debug "_STAT    => $_STAT"
    debug "_INDEX   => $_INDEX"
    debug "_DEFAULT => $_DEFAULT"
else
    _STAT=$(echo -e "$INFO_MAP" | grep ${stat})
    debug "_STAT    => $_STAT"
fi

# check if requested stat is supported
if [ -z "${_STAT}" ]
then
  fail 127 "ERROR: $stat is unsupported"
fi

# method to retrieve data from haproxy stats
# usage:
# query_stats "show stat"
query_stats() {
    if [[ ${QUERYING_METHOD} == "SOCKET" ]]; then
        echo $1 | socat ${HAPROXY_SOCKET} stdio 2>/dev/null
    elif [[ ${QUERYING_METHOD} == "TCP" ]]; then
        echo $1 | nc ${HAPROXY_STATS_IP//:/ } 2>/dev/null
    fi
}

# a generic cache management function, that relies on 'flock'
cache_gen() {
    local cache_filemtime
    cache_filemtime=$(stat -c '%Y' "${CACHE_FILEPATH}" 2> /dev/null)
    if [[ $((cache_filemtime+CACHE_EXPIRATION)) -ge ${CUR_TIMESTAMP} && -s "${CACHE_FILEPATH}" ]]; then
        debug "${metric_type} file found, results are at most ${CACHE_EXPIRATION} seconds stale..."
    elif "${FLOCK_BIN}" --exclusive --wait "${FLOCK_WAIT}" 200; then
        cache_filemtime=$(stat -c '%Y' "${CACHE_FILEPATH}" 2> /dev/null)
        if [[ $((cache_filemtime+CACHE_EXPIRATION)) -ge ${CUR_TIMESTAMP} && -s "${CACHE_FILEPATH}" ]]; then
            debug "$(ls -al $CACHE_FILEPATH)"
            debug "${metric_type} file found, results have just been updated by another process..."
        else
            debug "${metric_type} file expired/empty/not_found, querying haproxy to refresh it"
            query_stats "show ${metric_type}" > "${CACHE_FILEPATH}"
        fi
    fi 200> "${CACHE_FILEPATH}${FLOCK_SUFFIX}"
}

get_resources() {
    # $1: string to search for
    # $2: [OPTIONAL] file where to save resource extracted. (useful if multiple resources
    #     are returned because else the ${_res} var will be a single line)
    local _res
    local _flock_parsing
    local error_message
    # using different  error message "stat" and "info"
    if [[ $metric_type == "stat" ]]; then
        _error_message="ERROR: bad $pxname/$svname"
    else
        _error_message="ERROR: info stat is unsupported"
    fi
    # extract resources from flocked cache file
    if [[ -z $2 ]]; then
        _res="$("${FLOCK_BIN}" --shared --wait "${FLOCK_WAIT}" "${CACHE_FILEPATH}${FLOCK_SUFFIX}" grep "$1" "${CACHE_FILEPATH}" | grep -v ^$)"
    else
        _res="$("${FLOCK_BIN}" --shared --wait "${FLOCK_WAIT}" "${CACHE_FILEPATH}${FLOCK_SUFFIX}" grep "$1" "${CACHE_FILEPATH}" | grep -v ^$ | tee "$2")"
    fi
    [[ -z ${_res} ]] && fail 127 "${_error_message}"  # fail if no resource is found
    debug "full_line resource stats: ${_res}"
    [[ -z $2 ]] && echo ${_res}
}

# get requested stat from cache file using INDEX offset defined in STATS_MAP
# return default value if stat is ""
get() {
    # $1: pxname/svname for "stat"; stat for "info"
    local _res
    local _ret_type="_res"
    get_resources "$1" ${RESTTMPFILE}
    if [[ $metric_type == "info" ]]; then
        _res=$(cat ${RESTTMPFILE} | cut -d: -f2 | tr -d '[:space:]')
    else
        _res="$(cat $RESTTMPFILE | cut -d, -f ${_INDEX})"
        # TODO: find out what to return if default is "@"
        if [ -z "${_res}" ] && [[ "${_DEFAULT}" != "@" ]]; then
            _ret_type="default"
            _res="${_DEFAULT}"
        elif [ "${_res}" == "-1" ]; then 
            _ret_type="default"
            _res="0"
        fi
    fi
    debug "return value ($_ret_type) = ${_res}"
    echo "${_res}"
}

# get number of total servers in "active" mode
# this is needed to check the number of server there should be "UP"
get_srvtot () {
    local _srvtot=0
    get_resources "$1" ${RESTTMPFILE}
    $(cat ${RESTTMPFILE} | grep -v "BACKEND" | grep -v "FRONTEND" > ${TMPFILE})
    while read line; do
        debug "LINE: ${line}"
        if [[ "$(echo \"${line}\" | cut -d, -f 20 )" -eq "1" ]]; then
            _srvtot=$((_srvtot+1))
        fi
    done < ${TMPFILE}
    echo "${_srvtot}"
}

render_final_json(){
    local _json_vals=$(echo ${1} | sed "s/\s/,/g")
    debug "RETURNED_VALUE: {\"haproxy_data\": {${_json_vals}}}"
    echo "{\"haproxy_data\": {${_json_vals}}}"
}

get_alljson () {
    local _pxname=$( echo ${1%%,*} | sed 's/\^//g')
    get_resources "$1" ${RESTTMPFILE}
    local _res=$(cat ${RESTTMPFILE})
    local _json_vals
    local _stat
    local _key
    local _value
    local _index
    for s in $STATS_MAP; do
        _index=${s%%:*}
        [[ ${_index} -eq 0 ]] && continue
        _stat_val=${s#*:}
        _key=${_stat_val%:*}
        _value=$(echo $_res | cut -d, -f${_index})
        [[ -z "${_value}" ]] && _value=${_stat_val#*:}  # if empty value set it to Default val from STATS_MAP
            _json_vals="${_json_vals} \"${_key}\":\"${_value}\""
    done
    _value=$(get_srvtot "^${_pxname},")
    _json_vals="${_json_vals} \"srvtot\":\"${_value}\""

    render_final_json "${_json_vals}" "\s"
}

get_info_alljson(){
    get_resources "" ${RESTTMPFILE} > /dev/null
    local _json_vals
    local _key
    local _value
    while read line; do
        debug "LINE: ${line}"
        _key="${line%:*}"
        _value="$(echo ${line#*:} | tr -d '[:space:]')"
        _json_vals="${_json_vals} \"${_key}\":\"${_value}\""
    done < ${RESTTMPFILE}
    render_final_json "${_json_vals}"
}

check_cache
cache_gen


# this allows for overriding default method of getting stats
# name a function by stat name for additional processing, custom returns, etc.
if type get_${stat} >/dev/null 2>&1
then
    debug "found custom query function"
    case ${stat} in
        "srvtot")
            get_${stat} "^${pxname},"
            ;;
        alljson)
            get_${stat} "^${pxname},${svname},"
            ;;
        *) 
            get_${stat}
            ;;
    esac
else
    debug "using default get() method"
    if [[ $metric_type == "stat" ]]; then
        get "^${pxname},${svname},"
    else
        get "${stat}"
    fi
fi
rm -f ${TMPFILE} ${RESTTMPFILE}
