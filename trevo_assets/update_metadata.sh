#!/bin/bash

# Скрипт для обновления метаданных в Trevo Vault
# Автор: AI Assistant
# Дата: $(date +%Y-%m-%d)

set -e  # Останавливаем выполнение при любой ошибке

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция для вывода сообщений
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверяем, что мы в корневой папке проекта
if [ ! -f "rust/Cargo.toml" ]; then
    log_error "Скрипт должен запускаться из корневой папки проекта trevo-vault"
    exit 1
fi

# Настройки
RPC_URL="wss://rpc.api.trevo.finance"
NETWORK_NAME="trevo-asset-hub"
BACKUP_DIR="backup_metadata_$(date +%Y%m%d_%H%M%S)"

log_info "🚀 Начинаем обновление метаданных для Trevo Vault"
log_info "RPC URL: $RPC_URL"
log_info "Сеть: $NETWORK_NAME"

# Создаем backup существующих метаданных
log_info "📦 Создаем backup существующих метаданных..."
mkdir -p "$BACKUP_DIR"
if [ -d "rust/defaults/release_metadata" ]; then
    cp -r rust/defaults/release_metadata/* "$BACKUP_DIR/" 2>/dev/null || true
    log_success "Backup создан в папке: $BACKUP_DIR"
fi

# Переходим в папку generate_message
log_info "📥 Загружаем новые метаданные с RPC узла..."
cd rust/generate_message

# Загружаем метаданные
if ! cargo run --locked load-metadata -d -u "$RPC_URL"; then
    log_error "Не удалось загрузить метаданные с RPC узла"
    log_error "Проверьте подключение к интернету и доступность RPC узла"
    exit 1
fi

# Возвращаемся в корень проекта
cd ../..

# Ищем новый файл метаданных
METADATA_FILE=$(find rust/files/in_progress -maxdepth 1 -type f \
    -name "sign_me_load_metadata_${NETWORK_NAME}V*" | sort -V | tail -1)

if [ -z "$METADATA_FILE" ]; then
    log_error "Не найден файл с метаданными для сети $NETWORK_NAME"
    log_error "Проверьте, что метаданные были успешно загружены"
    exit 1
fi

# Извлекаем версию из имени файла
VERSION=$(echo "$METADATA_FILE" | grep -o 'V[0-9]*' | sed 's/V//')
log_success "Найдены метаданные версии: $VERSION"

# Подготавливаем файл метаданных
log_info "🔧 Подготавливаем файл метаданных..."

# Конвертируем в hex формат
xxd -p "$METADATA_FILE" | tr -d '\n' > temp_metadata

# Удаляем 4-байтовый SCALE compact-length заголовок и добавляем префикс 0x
sed -E 's/^.{8}/0x/' temp_metadata > "rust/defaults/release_metadata/${NETWORK_NAME}${VERSION}"

# Удаляем временный файл
rm temp_metadata

log_success "Файл метаданных подготовлен: rust/defaults/release_metadata/${NETWORK_NAME}${VERSION}"

# Очищаем старые метаданные
log_info "🧹 Очищаем старые метаданные..."
cd rust/defaults/release_metadata/
OLD_FILES=$(ls ${NETWORK_NAME}* 2>/dev/null | grep -v "${NETWORK_NAME}${VERSION}" || true)
if [ -n "$OLD_FILES" ]; then
    echo "$OLD_FILES" | xargs rm -f
    log_success "Удалены старые файлы метаданных: $OLD_FILES"
else
    log_info "Старых файлов метаданных не найдено"
fi

cd ../../..

# Проверяем функцию release_metadata()
log_info "🔍 Проверяем функцию release_metadata()..."
if grep -q "Ok(vec!\[\])" rust/defaults/src/lib.rs; then
    log_warning "Функция release_metadata() возвращает пустой вектор"
    log_info "Исправляем функцию release_metadata()..."
    
    # Создаем backup файла
    cp rust/defaults/src/lib.rs rust/defaults/src/lib.rs.backup
    
    # Заменяем функцию
    sed -i.tmp 's/Ok(vec!\[\])/metadata("..\/defaults\/release_metadata")/' rust/defaults/src/lib.rs
    rm rust/defaults/src/lib.rs.tmp
    
    log_success "Функция release_metadata() исправлена"
else
    log_success "Функция release_metadata() уже настроена правильно"
fi

# Создаем холодную базу данных
log_info "🗄️  Создаем холодную базу данных с новыми метаданными..."
cd rust/generate_message

if ! cargo run make-cold-release; then
    log_error "Не удалось создать холодную базу данных"
    log_error "Проверьте формат файла метаданных и genesis hash в defaults/src/lib.rs"
    log_warning "Возможно, изменился genesis hash сети. Проверьте значение в строке 193 файла rust/defaults/src/lib.rs"
    exit 1
fi

cd ../..

log_success "Холодная база данных создана успешно"

# Обновляем версию в QR генераторе
log_info "📱 Обновляем версию в QR генераторе..."
cd trevo_assets

if grep -q "generate_chain_qr \"$NETWORK_NAME\"" generate_qr.sh; then
    # Обновляем версию в скрипте
    sed -i.tmp "s/generate_chain_qr \"$NETWORK_NAME\" \$ASSET_HUB_RPC \"[0-9]*\"/generate_chain_qr \"$NETWORK_NAME\" \$ASSET_HUB_RPC \"$VERSION\"/" generate_qr.sh
    rm generate_qr.sh.tmp
    log_success "Версия в QR генераторе обновлена на: $VERSION"
else
    log_warning "Не найдена строка для обновления версии в generate_qr.sh"
fi

# Генерируем новый QR код
log_info "🔳 Генерируем новый QR код..."
if [ -f ".env" ]; then
    if ./generate_qr.sh; then
        log_success "QR код успешно сгенерирован"
    else
        log_warning "Не удалось сгенерировать QR код (возможно, проблема с переменными окружения)"
    fi
else
    log_warning "Файл .env не найден. QR код не сгенерирован."
    log_info "Для генерации QR кода создайте файл .env с переменными SIGNER_URI и VERIFIER_HEX"
fi

cd ..

# Итоговый отчет
echo
log_success "✅ Обновление метаданных завершено!"
echo -e "${GREEN}📊 Итоговый отчет:${NC}"
echo "  • Версия метаданных: $VERSION"
echo "  • Файл метаданных: rust/defaults/release_metadata/${NETWORK_NAME}${VERSION}"
echo "  • Backup создан в: $BACKUP_DIR"
echo "  • Холодная база данных обновлена"
echo "  • QR генератор обновлен"

echo
log_info "🔄 Следующие шаги:"
echo "  1. Протестируйте приложение с новыми метаданными"
echo "  2. Убедитесь, что QR код работает корректно"
echo "  3. Создайте коммит с изменениями"
echo "  4. При необходимости восстановите из backup: $BACKUP_DIR"

echo
log_success "🎉 Готово! Метаданные обновлены до версии $VERSION"
