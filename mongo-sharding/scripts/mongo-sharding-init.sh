#!/bin/bash

# Запуск контейнеров
echo "Запуск контейнеров..."
docker compose up -d
sleep 15

# Функция для проверки состояния репликации
check_rs_status() {
  local container=$1
  local port=$2
  until docker exec $container mongosh --port $port --eval "rs.status()" | grep -q "myState"
  do
    echo "Ожидание готовности репликации на $container..."
    sleep 5
  done
}

# Настройка Config Server
echo "Инициализация Config Server..."
docker exec -i config_server mongosh --port 27019 <<EOF
rs.initiate({
  _id: "configReplSet",
  configsvr: true,
  members: [{ _id: 0, host: "config_server:27019" }]
});
EOF

# Ожидание готовности репликации Config Server
check_rs_status config_server 27019
sleep 5

# Настройка Shard 1
echo "Инициализация Shard1..."
docker exec -i shard1 mongosh --port 27018 <<EOF
rs.initiate({
  _id: "shard1ReplSet",
  members: [{ _id: 0, host: "shard1:27018" }]
});
EOF

# Ожидание готовности Shard 1
check_rs_status shard1 27018
sleep 5

# Настройка Shard 2
echo "Инициализация Shard2..."
docker exec -i shard2 mongosh --port 27017 <<EOF
rs.initiate({
  _id: "shard2ReplSet",
  members: [{ _id: 0, host: "shard2:27017" }]
});
EOF

# Ожидание готовности Shard 2
check_rs_status shard2 27017
sleep 5

# Добавление шардов в кластер
echo "Добавление шардов в кластер..."
docker exec -i router mongosh --port 27020 <<EOF
sh.addShard("shard1ReplSet/shard1:27018");
sh.addShard("shard2ReplSet/shard2:27017");
EOF

# Создание базы данных и коллекции
echo "Создание базы данных и коллекции..."
docker exec -i router mongosh --port 27020 <<EOF
use somedb;
db.createCollection("helloDoc");
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { name: "hashed" });
EOF

# Добавление данных в коллекцию
echo "Добавление данных в базу данных..."
docker exec -i router mongosh --port 27020 <<EOF
use somedb;
for (var i = 0; i < 1000; i++) {
  db.helloDoc.insertOne({ age: i, name: "user" + i });
}
print("Документов в коллекции helloDoc:", db.helloDoc.countDocuments());
EOF

# Проверка данных в первом шарде
echo "Проверка данных в первом шарде..."
docker exec -i shard1 mongosh --port 27018 <<EOF
use somedb;
print("Документов в первом реплике первого шарда:", db.helloDoc.countDocuments());
EOF

# Завершение работы
read -p "Нажмите Enter, чтобы завершить..."
