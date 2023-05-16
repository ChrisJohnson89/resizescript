#!/bin/bash
MEM=$(free -g|sed -n 2p|awk '{print $2}')
​
# setParams elastic innodb redis_sess redis_cache redis_fpc varnish
function setParams(){
  ELASTICSEARCH=$1
  INNODB=$2
  REDIS_SESS=$3
  REDIS_POLICY_LRU="allkeys-lru"
  REDIS_CACHE=$4
  REDIS_FPC=$5
  REDIS_POLICY_LFU="allkeys-lfu"
  VARNISH=$6
  RABBITMQ="vm_memory_high_watermark.relative = 0.03"
}
​
# setParams                             elastic innodb r_sess r_cache  re_fpc varnish
if   [ "$MEM" -ge 32 ]; then  setParams      4g     8G 1000mb  3000mb  2000mb  5000mb
elif [ "$MEM" -ge 24 ]; then  setParams      2g     6G 1000mb  2000mb  2000mb  3500mb
elif [ "$MEM" -ge 14 ]; then  setParams    750m     4G  500mb  1500mb  1500mb  1000mb
else                          setParams    500m     2G  250mb   500mb   500mb   500mb
fi
​
#elasticsearch
echo "ELASTICSEARCH: "
cd /etc/elasticsearch/jvm.options.d/ && rm -i * .* 
cd /etc/elasticsearch/jvm.options.d/ && echo -Xm{s,x}$ELASTICSEARCH|awk '$1 = $1' OFS="\n" > mem_allocation.options
cat /etc/elasticsearch/jvm.options.d/mem_allocation.options
​
#mysql
echo
echo "MySQL:"
LIMIT=$(grep -o [[:digit:]] <<< $INNODB)
if [ -f "/etc/mysql/mysql.conf.d/mysqld.cnf" ]; then
  echo "  BEFORE: "
  grep -E "^innodb_buffer_pool_size.*=|[^#]innodb_buffer_pool_size.*=" /etc/mysql/mysql.conf.d/mysqld.cnf
  POOL_SIZE=$(grep -E "^innodb_buffer_pool_size.*=|[^#]innodb_buffer_pool_size.*=" /etc/mysql/mysql.conf.d/mysqld.cnf|grep -o [[:digit:]])
  [ $LIMIT -gt $POOL_SIZE ] && sed -i -E "s/^innodb_buffer_pool_size.*=.*|[^#]innodb_buffer_pool_size.*=.*/innodb_buffer_pool_size = $INNODB/" /etc/mysql/mysql.conf.d/mysqld.cnf
  echo "  AFTER: "
  grep -E "^innodb_buffer_pool_size.*=|[^#]innodb_buffer_pool_size.*=" /etc/mysql/mysql.conf.d/mysqld.cnf
fi
​
if [ -f "/etc/mysql/mariadb.conf.d/50-server.cnf" ]; then
  echo "  BEFORE: "
  grep -E "^innodb_buffer_pool_size.*=|[^#]innodb_buffer_pool_size.*=" /etc/mysql/mariadb.conf.d/50-server.cnf
  POOL_SIZE=$(grep -E "^innodb_buffer_pool_size.*=|[^#]innodb_buffer_pool_size.*=" /etc/mysql/mariadb.conf.d/50-server.cnf|grep -o [[:digit:]])
  [ $LIMIT -gt $POOL_SIZE ] && sed -i -E "s/^innodb_buffer_pool_size.*=.*|[^#]innodb_buffer_pool_size.*=.*/innodb_buffer_pool_size = $INNODB/" /etc/mysql/mariadb.conf.d/50-server.cnf
  echo "  AFTER: "
  grep -E "^innodb_buffer_pool_size.*=|[^#]innodb_buffer_pool_size.*=" /etc/mysql/mariadb.conf.d/50-server.cnf
fi
​
​
#varnish
echo
echo "VARNISH: "
echo "  BEFORE: "
grep -E "malloc,\w*" /etc/systemd/system/varnish.service.d/override.conf
sed -i -E "s/malloc,\w*/malloc,$VARNISH/" /etc/systemd/system/varnish.service.d/override.conf
echo "  AFTER:"
grep -E "malloc,\w*" /etc/systemd/system/varnish.service.d/override.conf
​
#rabitmq
echo
echo "RABBITMQ:"
cd /etc/rabbitmq/  && echo "$RABBITMQ" > rabbitmq.conf
cat /etc/rabbitmq/rabbitmq.conf
​
#redis
cd /etc/redis || exit 1 
REDIS_VERSION=$(redis-cli -v|grep -o [[:digit:]]|head -1)
echo
echo "REDIS:"
echo " BEFORE:"
grep -H -E "^[^#]*maxmemory " /etc/redis/redis-sessions.conf && sed -i -E "s/^[^#]*maxmemory .*/maxmemory $REDIS_SESS/" /etc/redis/redis-sessions.conf || echo "maxmemory $REDIS_SESS"  >> /etc/redis/redis-sessions.conf
grep -H -E "^[^#]*maxmemory " /etc/redis/redis-cache.conf    && sed -i -E "s/^[^#]*maxmemory .*/maxmemory $REDIS_CACHE/" /etc/redis/redis-cache.conf || echo "maxmemory $REDIS_CACHE" >> /etc/redis/redis-cache.conf
grep -H -E "^[^#]*maxmemory " /etc/redis/redis-fpc.conf      && sed -i -E "s/^[^#]*maxmemory .*/maxmemory $REDIS_FPC/"  /etc/redis/redis-fpc.conf || echo "maxmemory $REDIS_FPC"   >> /etc/redis/redis-fpc.conf
​
grep -H -E "^[^#]*maxmemory-policy" /etc/redis/redis-sessions.conf && sed -i -E "s/^[^#]*maxmemory-policy.*/maxmemory-policy $REDIS_POLICY_LRU/" /etc/redis/redis-sessions.conf || echo "maxmemory-policy $REDIS_POLICY_LRU" >> /etc/redis/redis-sessions.conf
grep -H -E "^[^#]*maxmemory-policy" /etc/redis/redis-cache.conf    && sed -i -E "s/^[^#]*maxmemory-policy.*/maxmemory-policy $REDIS_POLICY_LRU/" /etc/redis/redis-cache.conf || echo "maxmemory-policy $REDIS_POLICY_LRU" >> /etc/redis/redis-cache.conf
#Art updated info to only allkeys-lru
#if [ $REDIS_VERSION -eq 3 ];then REDIS_POLICY_LFU=$REDIS_POLICY_LRU;fi
#grep -H -E "^[^#]*maxmemory-policy" /etc/redis/redis-fpc.conf      && sed -i -E "s/^[^#]*maxmemory-policy.*/maxmemory-policy $REDIS_POLICY_LFU/" /etc/redis/redis-fpc.conf || echo "maxmemory-policy $REDIS_POLICY_LFU" >> /etc/redis/redis-fpc.conf
grep -H -E "^[^#]*maxmemory-policy" /etc/redis/redis-fpc.conf      && sed -i -E "s/^[^#]*maxmemory-policy.*/maxmemory-policy $REDIS_POLICY_LRU/" /etc/redis/redis-fpc.conf || echo "maxmemory-policy $REDIS_POLICY_LRU" >> /etc/    redis/redis-fpc.conf
​
​
echo "  AFTER:"
grep -H -E "^[^#]*maxmemory" /etc/redis/redis-sessions.conf
grep -H -E "^[^#]*maxmemory" /etc/redis/redis-cache.conf
grep -H -E "^[^#]*maxmemory" /etc/redis/redis-fpc.conf
​
