#!/bin/bash

###
# Инициализация MongoDB с шардингом, репликацией и кэшированием
###

function check_status {
  local container=$1
  local port=$2

  echo "Ожидание готовности $container на порту $port..."
  until docker exec -i "$container" mongosh --port "$port" --eval "rs.status()" | grep -q "myState"
  do
    sleep 5
  done
}

echo "Запуск MongoDB-кластера через Docker Compose..."
docker compose up -d

echo "Ожидание полной инициализации контейнеров..."
sleep 20

# Настройка Config Server
echo "Инициализация Config Server..."
docker exec -i config_server mongosh --port 27019 <<EOF
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [{ _id: 0, host: "config_server:27019" }]
});
EOF

# Проверка готовности Config Server
check_status "config_server" 27019

# Настройка Shard 1
echo "Инициализация Shard1..."
docker exec -i shard1_primary mongosh --port 27018 <<EOF
rs.initiate({
  _id: "shard1ReplSet",
  members: [
    { _id: 0, host: "shard1_primary:27018" },
    { _id: 1, host: "shard1_secondary_1:27021" },
    { _id: 2, host: "shard1_secondary_2:27022" }
  ]
});
EOF

# Проверка готовности репликации Shard 1
check_status "shard1_primary" 27018

# Настройка Shard 2
echo "Инициализация Shard2..."
docker exec -i shard2_primary mongosh --port 27017 <<EOF
rs.initiate({
  _id: "shard2ReplSet",
  members: [
    { _id: 0, host: "shard2_primary:27017" },
    { _id: 1, host: "shard2_secondary_1:27023" },
    { _id: 2, host: "shard2_secondary_2:27024" }
  ]
});
EOF

# Проверка готовности репликации Shard 2
check_status "shard2_primary" 27017

echo "Ожидание полной инициализации шардов..."
sleep 10

# Добавление шардов в кластер через Mongo Router
echo "Добавление шардов в кластер и настройка шардирования..."
docker exec -i router mongosh --port 27020 <<EOF
sh.addShard("shard1ReplSet/shard1_primary:27018")
sh.addShard("shard2ReplSet/shard2_primary:27017")
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" })
EOF
sleep 10

# Добавление данных в базу данных
echo "Добавление данных в базу данных..."
docker exec -i router mongosh --port 27020 <<EOF
use somedb
for (var i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({ age: i, name: "ly"+i })
}
print("Документов в коллекции helloDoc:", db.helloDoc.countDocuments())
EOF
sleep 15

# Проверка данных в Shard1
echo "Проверка данных в Shard1..."
docker exec -i shard1_primary mongosh --port 27018 <<EOF
use somedb
console.log("Документов в первом шарде (Shard1):", db.helloDoc.countDocuments())
EOF

# Проверка данных в Shard2
echo "Проверка данных в Shard2..."
docker exec -i shard2_primary mongosh --port 27017 <<EOF
use somedb
console.log("Документов во втором шарде (Shard2):", db.helloDoc.countDocuments())
EOF

# Завершение работы
read -p "Нажмите Enter, чтобы завершить..."
