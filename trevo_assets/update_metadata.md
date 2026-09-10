# Обновление метаданных в Trevo Vault

Этот документ описывает процесс обновления дефолтных метаданных в приложении Trevo Vault.

## Что такое метаданные?

Метаданные содержат информацию о структуре блокчейна (типы данных, методы, события). Они нужны для корректного отображения транзакций и взаимодействия с сетью.

## Зачем обновлять метаданные?

- При обновлении runtime сети (например, с версии 1003 на 1005)
- При добавлении новых функций в блокчейн
- Для поддержки новых типов транзакций

## Структура системы метаданных

```
rust/defaults/
├── release_metadata/     # Метаданные для релизной версии приложения
├── test_metadata/        # Метаданные для тестов
└── src/lib.rs           # Функции загрузки метаданных
```

## Пошаговый процесс обновления

### 1. Получение новых метаданных

```bash
# Переходим в папку generate_message
cd rust/generate_message

# Загружаем метаданные с RPC узла
cargo run load-metadata -d -u wss://rpc.api.trevo.finance
```

Это создаст файл `../files/in_progress/sign_me_load_metadata_trevo-asset-hubV[VERSION]`

### 2. Подготовка файла метаданных

```bash
# Переходим в корень проекта
cd ../..

# Конвертируем бинарный файл в hex формат
xxd -p rust/files/in_progress/sign_me_load_metadata_trevo-asset-hubV[VERSION] | tr -d '\n' > temp_metadata

# Удаляем заголовок и добавляем префикс 0x
sed -E 's/^.{8}/0x/' temp_metadata > rust/defaults/release_metadata/trevo-asset-hub[VERSION]

# Удаляем временный файл
rm temp_metadata
```

### 3. Очистка старых метаданных

```bash
# Удаляем старые файлы метаданных (если нужно)
cd rust/defaults/release_metadata/
rm trevo-asset-hub* # удаляем старые версии
```

### 4. Проверка функции release_metadata()

Убедитесь, что в файле `rust/defaults/src/lib.rs` функция `release_metadata()` выглядит так:

```rust
/// Read metadata set for release cold database from `release_metadata` folder
#[cfg(feature = "active")]
pub fn release_metadata() -> Result<Vec<MetaValues>> {
    metadata("../defaults/release_metadata")
}
```

Если там `Ok(vec![])`, замените на код выше.

### 5. Создание холодной базы данных

```bash
# Переходим в generate_message
cd rust/generate_message

# Создаем холодную базу данных с новыми метаданными
cargo run make-cold-release
```

### 6. Обновление QR генератора (если нужно)

Если изменилась версия runtime, обновите версию в `trevo_assets/generate_qr.sh`:

```bash
# Найдите строку с версией и обновите её
generate_chain_qr "trevo-asset-hub" $ASSET_HUB_RPC "[NEW_VERSION]"
```

### 7. Генерация нового QR кода

```bash
cd trevo_assets
./generate_qr.sh
```

## Проверка результата

1. Убедитесь, что команда `make-cold-release` выполнилась без ошибок
2. Проверьте, что QR код сгенерировался с новой версией
3. При сборке приложения метаданные будут автоматически включены

## Автоматизированный скрипт

Для упрощения процесса создан скрипт `update_metadata.sh` (см. следующий файл).

## Важные замечания

- ⚠️ Всегда делайте backup перед обновлением метаданных
- ⚠️ Проверяйте, что RPC узел доступен и возвращает корректные данные
- ⚠️ Тестируйте обновленное приложение перед релизом
- 📝 Записывайте версию метаданных для отслеживания изменений

## Troubleshooting

### Ошибка "Failed to parse metadata"
- Проверьте формат файла (должен начинаться с "0x")
- Убедитесь, что удален заголовок "920d1900"

### Ошибка "Network not found"
- Убедитесь, что сеть определена в defaults
- Проверьте правильность имени файла метаданных

### Genesis hash изменился
Если изменился genesis hash сети (например, после обновления runtime):
- Обновите значение в `rust/defaults/src/lib.rs` строка 193
- Текущий genesis hash: `6d32fee54448c79868e083fc2179f662edc8a348c8b3c92407056f2ef286ea31`
- Пересоздайте холодную базу данных: `cargo run make-cold-release`

### RPC недоступен
- Проверьте подключение к интернету
- Убедитесь, что RPC узел работает
- Попробуйте другой RPC endpoint
