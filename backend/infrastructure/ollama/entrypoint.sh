#!/bin/sh
# Запускаем Ollama и подтягиваем модель при первом старте
ollama serve &
SERVER_PID=$!

# Ждём готовности сервера
sleep 5

# Скачиваем модель если ещё не скачана
ollama pull llama3.1:8b

wait $SERVER_PID
