#!/usr/bin/env bash
# Benchmark determinista de pesos en Hostgroup 20 (2 o 3 réplicas) para demostración en vivo.
set -e

W1="${1:-1000}"
W2="${2:-1000}"
LABEL="${3:-B1_Simetrico}"
NODES="${4:-2}"
N_QUERIES="${5:-200}"
KEY="${6:-weights_b1}"

if [ "$NODES" -eq 3 ]; then
    mysql -h proxysql -P 6032 -u radmin -pradmin -e "UPDATE mysql_servers SET weight=1000 WHERE hostgroup_id=20; LOAD MYSQL SERVERS TO RUNTIME;" 2>/dev/null
    q1a=$(mysql -h proxysql -P 6032 -u radmin -pradmin -Nse "SELECT COALESCE(SUM(Queries),0) FROM stats_mysql_connection_pool WHERE srv_host='mysql-slave-1' AND hostgroup=20;" 2>/dev/null)
    q2a=$(mysql -h proxysql -P 6032 -u radmin -pradmin -Nse "SELECT COALESCE(SUM(Queries),0) FROM stats_mysql_connection_pool WHERE srv_host='mysql-slave-2' AND hostgroup=20;" 2>/dev/null)
    q3a=$(mysql -h proxysql -P 6032 -u radmin -pradmin -Nse "SELECT COALESCE(SUM(Queries),0) FROM stats_mysql_connection_pool WHERE srv_host='mysql-slave-3' AND hostgroup=20;" 2>/dev/null)
    for i in $(seq 1 "$N_QUERIES"); do
        mysql -h proxysql -P 6033 -u cluster_app -pAppPassword2026! telematicos_db -e "SELECT @@hostname;" >/dev/null 2>&1
    done
    q1b=$(mysql -h proxysql -P 6032 -u radmin -pradmin -Nse "SELECT COALESCE(SUM(Queries),0) FROM stats_mysql_connection_pool WHERE srv_host='mysql-slave-1' AND hostgroup=20;" 2>/dev/null)
    q2b=$(mysql -h proxysql -P 6032 -u radmin -pradmin -Nse "SELECT COALESCE(SUM(Queries),0) FROM stats_mysql_connection_pool WHERE srv_host='mysql-slave-2' AND hostgroup=20;" 2>/dev/null)
    q3b=$(mysql -h proxysql -P 6032 -u radmin -pradmin -Nse "SELECT COALESCE(SUM(Queries),0) FROM stats_mysql_connection_pool WHERE srv_host='mysql-slave-3' AND hostgroup=20;" 2>/dev/null)
    d1=$((q1b - q1a)); d2=$((q2b - q2a)); d3=$((q3b - q3a)); tot=$((d1 + d2 + d3))
    awk -v l="$LABEL" -v d1="$d1" -v d2="$d2" -v d3="$d3" -v tot="$tot" \
        'BEGIN { printf ">>> %s (%d queries): slave-1=%d (%.1f%%) | slave-2=%d (%.1f%%) | slave-3=%d (%.1f%%)\n", l, tot, d1, d1*100/tot, d2, d2*100/tot, d3, d3*100/tot }'
    awk -v k="$KEY" -v d1="$d1" -v d2="$d2" -v d3="$d3" -v tot="$tot" \
        'BEGIN { printf "{\"%s\":{\"slave_1_queries\":%d,\"slave_2_queries\":%d,\"slave_3_queries\":%d,\"slave_1_pct\":%.1f,\"slave_2_pct\":%.1f,\"slave_3_pct\":%.1f,\"total\":%d}}\n", k, d1, d2, d3, d1*100/tot, d2*100/tot, d3*100/tot, tot }' > "/workspace/results/.${KEY}.json"
else
    mysql -h proxysql -P 6032 -u radmin -pradmin -e "UPDATE mysql_servers SET weight=${W1} WHERE hostname='mysql-slave-1' AND hostgroup_id=20; UPDATE mysql_servers SET weight=${W2} WHERE hostname='mysql-slave-2' AND hostgroup_id=20; LOAD MYSQL SERVERS TO RUNTIME;" 2>/dev/null
    q1a=$(mysql -h proxysql -P 6032 -u radmin -pradmin -Nse "SELECT COALESCE(SUM(Queries),0) FROM stats_mysql_connection_pool WHERE srv_host='mysql-slave-1' AND hostgroup=20;" 2>/dev/null)
    q2a=$(mysql -h proxysql -P 6032 -u radmin -pradmin -Nse "SELECT COALESCE(SUM(Queries),0) FROM stats_mysql_connection_pool WHERE srv_host='mysql-slave-2' AND hostgroup=20;" 2>/dev/null)
    for i in $(seq 1 "$N_QUERIES"); do
        mysql -h proxysql -P 6033 -u cluster_app -pAppPassword2026! telematicos_db -e "SELECT @@hostname;" >/dev/null 2>&1
    done
    q1b=$(mysql -h proxysql -P 6032 -u radmin -pradmin -Nse "SELECT COALESCE(SUM(Queries),0) FROM stats_mysql_connection_pool WHERE srv_host='mysql-slave-1' AND hostgroup=20;" 2>/dev/null)
    q2b=$(mysql -h proxysql -P 6032 -u radmin -pradmin -Nse "SELECT COALESCE(SUM(Queries),0) FROM stats_mysql_connection_pool WHERE srv_host='mysql-slave-2' AND hostgroup=20;" 2>/dev/null)
    d1=$((q1b - q1a)); d2=$((q2b - q2a)); tot=$((d1 + d2))
    awk -v l="$LABEL" -v d1="$d1" -v d2="$d2" -v tot="$tot" \
        'BEGIN { printf ">>> %s (%d queries): slave-1=%d (%.1f%%) | slave-2=%d (%.1f%%)\n", l, tot, d1, d1*100/tot, d2, d2*100/tot }'
    awk -v k="$KEY" -v d1="$d1" -v d2="$d2" -v tot="$tot" \
        'BEGIN { printf "{\"%s\":{\"slave_1_queries\":%d,\"slave_2_queries\":%d,\"slave_1_pct\":%.1f,\"slave_2_pct\":%.1f,\"total\":%d}}\n", k, d1, d2, d1*100/tot, d2*100/tot, tot }' > "/workspace/results/.${KEY}.json"
fi
