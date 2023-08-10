#!/bin/bash
#Chose the number of brokers you want to start
kafka_number_of_brokers=3

# Define the network name
NETWORK_NAME=kafka-network
# Create the network if it doesn't exist
#docker network create $NETWORK_NAME 2>/dev/null || true

#zookeeper
zookeeper_hostname=zookeeper-0
zookeeper_admin_port=2182
zookeeper_admin_url="http://localhost:$zookeeper_admin_port"
# kafka
kafka_hostname_prefix="kafka-"
wireshark_hostname=wireshark
intern_port_suffix=9092
extern_port_suffix=9093
bootstrap_server_hostname_inside_docker="$kafka_hostname_prefix"1:1$intern_port_suffix
bootstrap_server_hostname_EXTERNAL=locahost:1$extern_port_suffix

check_broker_elected() {
    local json_data=$(curl -s "$zookeeper_admin_url/commands/dump")
    local brokers_count=0
    local controller_count=0

    local brokers_count=$(echo "$json_data" | grep -o '/brokers/ids/[0-9]*' | sort -u | wc -l)
    printf "brokers_count: $brokers_count\n"
    local controller_count=$(echo "$json_data" | grep -o '/controller' | wc -l)
    printf "controller_count: $controller_count\n"

    if [[ $brokers_count -eq $kafka_number_of_brokers && $controller_count -eq 1 ]]; then
        return 0  # True
    else
        return 1  # False
    fi
}
wait_for_zookeeper_and_kafka(){
  MAX_RETRIES=10
  RETRY_INTERVAL=5
  attempt=1
  while [[ $attempt -le $MAX_RETRIES ]]; do
      if check_broker_elected; then
          echo "ZooKeeper & broker are available"
          exit 0
      else
          echo "ZooKeeper is not yet available (attempt $attempt)"
          sleep $RETRY_INTERVAL
          ((attempt++))
      fi
  done

  echo "Max retries reached. ZooKeeper is not available."
  exit 1
}

#docker rm -f -v $zookeeper_hostname $kafka_hostname 2>/dev/null || true
# Start ZooKeeper
up_zookeeper() {
#8080 is for the admin server ZOOKEEPER_ADMIN_ENABLE_SERVER=true
docker run -d \
  --name $zookeeper_hostname \
  --network $NETWORK_NAME \
  -p 2181:2181 \
  -p $zookeeper_admin_port:8080 \
  -e ZOOKEEPER_CLIENT_PORT=2181 \
  -e ZOOKEEPER_ADMIN_ENABLE_SERVER=true \
  -e ZOOKEEPER_ADMIN_SERVER_PORT=8080 \
  -e ZOOKEEPER_4LW_COMMANDS_WHITELIST='*' \
  confluentinc/cp-zookeeper:7.2.2
}

# Start two Kafka brokers function
up_kafka_broker() {
broker_id=$1
max_number_of_brokers=$kafka_number_of_brokers
max_number_of_consumers_among_a_group=3 #The number of partitions in the topic that can be consumed in parallel by the consumer group.
kafka_hostname="$kafka_hostname_prefix$broker_id"
intern_port=$broker_id$intern_port_suffix
extern_port=$broker_id$extern_port_suffix

docker run -d \
  --name $kafka_hostname \
  --network $NETWORK_NAME \
  -p $intern_port:$intern_port \
  -p $extern_port:$extern_port \
  -e KAFKA_BROKER_ID=$broker_id \
  -e KAFKA_ZOOKEEPER_CONNECT="$zookeeper_hostname:2181" \
  -e KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR=$max_number_of_brokers \
  -e KAFKA_DEFAULT_REPLICATION_FACTOR=$max_number_of_brokers \
  -e KAFKA_NUM_PARTITIONS=$max_number_of_consumers_among_a_group \
  -e KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR=$max_number_of_brokers \
  -e KAFKA_TRANSACTION_STATE_LOG_MIN_ISR=$max_number_of_brokers \
  -e KAFKA_LISTENERS="BROKER://:$intern_port,EXTERNAL://:$extern_port" \
  -e KAFKA_LISTENER_SECURITY_PROTOCOL_MAP='BROKER:PLAINTEXT,EXTERNAL:PLAINTEXT' \
  -e KAFKA_INTER_BROKER_LISTENER_NAME='BROKER' \
  -e KAFKA_ADVERTISED_LISTENERS="BROKER://$kafka_hostname:$intern_port,EXTERNAL://localhost:$extern_port" \
  -e KAFKA_CONFLUENT_SUPPORT_METRICS_ENABLE='false' \
  -e KAFKA_JMX_PORT="${broker_id}9091" \
  -e KAFKA_AUTO_CREATE_TOPICS_ENABLE='true' \
  -e KAFKA_AUTHORIZER_CLASS_NAME='kafka.security.authorizer.AclAuthorizer' \
  -e KAFKA_ALLOW_EVERYONE_IF_NO_ACL_FOUND='true' \
  confluentinc/cp-kafka:7.2.2
}

#Start wireshark
up_wireshark() {

docker run -d \
  --name=$wireshark_hostname \
  --network=host \
  --privileged \
  --cap-add=NET_ADMIN \
  --security-opt seccomp=unconfined `#optional` \
  -e PUID=1000 \
  -e PGID=1000 \
  -e TZ=Etc/UTC \
  -p 3000:3000 `#optional` \
  -p 3001:3001 `#optional` \
  --restart unless-stopped \
  lscr.io/linuxserver/wireshark:latest
}

#Start AKHQ using docker
up_akhq() {

  micraunaute_conf=$(cat <<EOF

akhq:
  connections:
    docker-kafka-server:
      properties:
        bootstrap.servers: "$bootstrap_server_hostname_inside_docker"
EOF
)

  docker run -d \
  --name="akhq" \
  --network=$NETWORK_NAME \
  -p 8080:8080 \
  -e AKHQ_CONFIGURATION="$micraunaute_conf" \
  tchiotludo/akhq:0.20.0
}

# function to force remove container and volume if exists with name
down() {
  docker rm -f -v $1 2>/dev/null || true
}

restart_all() {
  down $zookeeper_hostname
  up_zookeeper

  restart_kafka $kafka_number_of_brokers

  down akhq
  up_akhq
}
down_all() {
  down $zookeeper_hostname
  for i in $(seq 1 "$1")
    do
      down $kafka_hostname_prefix"$i"
    done
  down $wireshark_hostname
  down akhq
}
restart_kafka() {
  #for each do down and up
  for i in $(seq 1 "$1")
  do
    down $kafka_hostname_prefix"$i"
    up_kafka_broker "$i"
  done
}


run_application() {
    if [[ "$1" == "run" ]]; then
        restart_all
        wait_for_zookeeper_and_kafka
    fi
}
pwd
run_application $1
## pause container
#docker pause $kafka_hostname
# resume container
#docker unpause $kafka_hostname
#down $wireshark_hostname
#up_wireshark

# print git diff in xclip
# git diff | xclip -selection clipboard