#!/bin/bash

###
# Инициализация MongoDB с шардингом
###

echo "Запуск MongoDB-кластера через Docker Compose..."
docker compose up -d

echo "Ожидание полной инициализации контейнеров..."
sleep 10

# Настройка Config Server
echo "Инициализация Config Server..."
docker exec -it config_server mongosh --port 27019 <<EOF
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [{ _id: 0, host: "config_server:27019" }]
});
EOF

# Настройка Shard 1
echo "Инициализация Shard1..."
docker exec -it shard1 mongosh --port 27018 <<EOF
rs.initiate({
  _id: "shard1ReplSet",
  members: [{ _id: 0, host: "shard1:27018" }]
});
EOF

# Настройка Shard 2
echo "Инициализация Shard2..."
docker exec -it shard2 mongosh --port 27017 <<EOF
rs.initiate({
  _id: "shard2ReplSet",
  members: [{ _id: 1, host: "shard2:27017" }]
});
EOF

echo "Ожидание полной инициализации шардов..."
sleep 10

# Настройка маршрутизатора (router) и заполнение БД
echo "Добавление шардов в кластер..."
docker exec -it router mongosh --port 27020 <<EOF
sh.addShard("shard1ReplSet/shard1:27018")
sh.addShard("shard2ReplSet/shard2:27017")
sh.enableSharding("somedb")
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } )
use somedb
for (var i = 0; i < 1000; i++) db.helloDoc.insertOne({ age: i, name: "ly"+i })
print("Документов в коллекции helloDoc:", db.helloDoc.countDocuments())
EOF

# Проверка распределения данных по шардам
echo "Проверка..."
docker exec -it shard1 mongosh --port 27018 <<EOF
use somedb;
console.log("Документов в первом шарде: ", db.helloDoc.countDocuments())
EOF

read -p "Нажмите Enter, чтобы завершить..."