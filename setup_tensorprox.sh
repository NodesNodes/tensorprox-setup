#!/bin/bash

set -e

echo ""
echo "Что вы хотите установить?"
echo "1) Moat (Майнер)"
echo "2) Генератор трафика / Кинг"
read -p "Введите номер (1 или 2): " NODE_CHOICE

case "$NODE_CHOICE" in
    1)
        NODE="moat"
        ;;
    2)
        NODE="generator"
        ;;
    *)
        echo "❌ Неверный выбор. Нужно ввести 1 или 2."
        exit 1
        ;;
esac

echo "Вы выбрали установку: $NODE"
echo ""

# Удаление старого nodejs, если есть
sudo apt remove -y nodejs npm || true

# Установка Node.js 18 LTS
echo "⏳ Устанавливаю Node.js 18..."
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

echo "✅ Node.js версия: $(node -v)"
echo "✅ npm версия: $(npm -v)"

# Установка PM2
sudo npm install -g pm2

# Установка Python и зависимостей
sudo apt update
sudo apt install -y python3-venv python3-pip git

# Создание и активация виртуального окружения
cd $HOME
python3 -m venv tp
source tp/bin/activate

# Установка gdown
if ! command -v gdown &> /dev/null; then
    pip install gdown
fi

# Клонирование репозитория
if [ ! -d "tensorprox" ]; then
    git clone https://github.com/shugo-labs/tensorprox.git
fi

cd tensorprox
pip install -r requirements.txt

if [ "$NODE" == "moat" ]; then
    CONFIG_DIR=~/config_download
    mkdir -p "$CONFIG_DIR"

    read -p "Вставь ID папки на Google Drive или полную ссылку для конфигов: " GDRIVE_INPUT

    if [[ "$GDRIVE_INPUT" =~ drive\/folders\/([^/?]+) ]]; then
        FOLDER_ID="${BASH_REMATCH[1]}"
    else
        FOLDER_ID="$GDRIVE_INPUT"
    fi

    echo "Использую ID папки: $FOLDER_ID"
    sleep 1

    cd "$CONFIG_DIR"
    gdown --folder --id "$FOLDER_ID"
    INNER_DIR=$(find . -mindepth 1 -maxdepth 1 -type d)

    REQUIRED_FILES=(".env.miner" ".env" "trafficgen_machines.csv" "id_ed25519")
    for file in "${REQUIRED_FILES[@]}"; do
        if [ ! -f "$INNER_DIR/$file" ]; then
            echo "❌ Файл $file не найден: $file"
            exit 1
        fi
    done

    cp "$INNER_DIR/.env.miner" ~/tensorprox/
    cp "$INNER_DIR/.env" ~/tensorprox/
    cp "$INNER_DIR/trafficgen_machines.csv" ~/tensorprox/
    mkdir -p /root/.ssh
    cp "$INNER_DIR/id_ed25519" /root/.ssh/id_ed25519
    chmod 600 /root/.ssh/id_ed25519

    cd ~
    rm -rf "$CONFIG_DIR"

    cd ~
    source tp/bin/activate
    cd tensorprox

    echo ""
    echo "ℹ️  Введите сид-фразу для восстановления Coldkey:"
    while true; do
        read -r -p "> " MNEMONIC
        if [ -n "$MNEMONIC" ]; then
            echo "$MNEMONIC" | btcli w regen-coldkey --wallet.name default --wallet.path ~/.bittensor/wallets
            break
        else
            echo "❌ Сид-фраза не может быть пустой. Повторите попытку:"
        fi
    done

    echo ""
    echo "ℹ️  Введите сид-фразу для восстановления Hotkey:"
    while true; do
        read -r -p "> " HOTKEY_MNEMONIC
        if [ -n "$HOTKEY_MNEMONIC" ]; then
            echo "$HOTKEY_MNEMONIC" | btcli wallet regen-hotkey --wallet.name default --wallet.hotkey default --wallet.path ~/.bittensor/wallets
            break
        else
            echo "❌ Сид-фраза не может быть пустой. Повторите попытку:"
        fi
    done

    echo ""
    read -p "❓ Включить мониторинг WandB? [y/N]: " USE_WANDB
    USE_WANDB=${USE_WANDB,,}

    if [[ "$USE_WANDB" != "y" ]]; then
        echo "⚙️  Отключаю WandB в settings.py..."
        sed -i 's/WANDB_ON: bool = Field(True, env="WANDB_ON")/WANDB_ON: bool = Field(False, env="WANDB_ON")/' ~/tensorprox/tensorprox/settings.py
        echo "✅ WandB отключён."
    else
        echo "✅ WandB оставлен включённым."
    fi

    echo ""
    echo "🚀 Запускаю Moat через pm2..."
    pm2 start "python3 neurons/miner.py" --name moat
    pm2 save
    pm2 status

else
    echo ""
    echo "✅ Установка генератора завершена. Репозиторий и окружение подготовлены."
    chmod 600 /root/.ssh/authorized_keys
fi
