# Гайд: метаданные Trevo и сборка

Цель: держать в коде и вшивать в сборку актуальные метаданные Trevo Asset Hub. Genesis hash меняется со временем, поэтому всегда проверяем и обновляем перед сборкой.

---

## Текущее состояние
- `rust/defaults/src/lib.rs`: genesis hash сейчас `6d32fee54448c79868e083fc2179f662edc8a348c8b3c92407056f2ef286ea31`; verifier public key 0x2405ad269ad0e6ca50f74226f193d7bfd1b51ef4064493c48a99f82a5a9b5374.
- `rust/defaults/release_metadata/`: одна версия `trevo-asset-hub1011` (держим только свежую).
- `android/src/main/assets/Database/`: пересобрана под 1011 (через `./generate_database.sh`).

---

## Обновить метаданные (новая версия Vxxxx)
```bash
# 1) Скачать сырые метаданные с RPC
cd rust/generate_message
cargo run --locked load-metadata -d -u wss://rpc.api.trevo.finance

# 2) Определить версию (файл в rust/files/in_progress/sign_me_load_metadata_trevo-asset-hubVXXXX)
ls ../files/in_progress/sign_me_load_metadata_trevo-asset-hubV*

# 3) Конвертировать в hex и положить в release_metadata
cd ../..
xxd -p rust/files/in_progress/sign_me_load_metadata_trevo-asset-hubV1011 | tr -d '\\n' > /tmp/meta.hex
# Снимаем 4-байтовый SCALE compact-length заголовок и добавляем префикс 0x
sed -E 's/^.{8}/0x/' /tmp/meta.hex > rust/defaults/release_metadata/trevo-asset-hub1011
rm /tmp/meta.hex

# 4) Удалить старые версии (оставляем только свежую, напр. 1011)
rm -f rust/defaults/release_metadata/trevo-asset-hub1010
```

**Важно:** Перед шагом 3 сверить/обновить genesis hash в `rust/defaults/src/lib.rs` на актуальный (через polkadot.js или RPC `chain_getBlockHash(0)`).

---

## Вшить метаданные в приложение
```bash
# Создать cold DB и перенести метаданные, затем скопировать в Android assets
cd android
./generate_database.sh   # вызывает cargo run make-cold-release + transfer-meta и кладёт в src/main/assets/Database

# Собрать APK
./gradlew assembleDebug   # или assembleRelease
```

---

## Сгенерировать QR для ручного обновления
```bash
cd trevo_assets
# Внутри generate_qr.sh правим VERSION на нужную (сейчас 1011)
./generate_qr.sh
# Итоговый файл: trevo_assets/load_metadata_trevo-asset-hubV1011.png
```

---

## Минимальный чек-лист перед релизом
1) `rust/defaults/src/lib.rs`: genesis hash актуальный; verifier key без изменений.  
2) `rust/defaults/release_metadata/`: лежит только свежий `trevo-asset-hubXXXX`.  
3) `android/src/main/assets/Database/`: обновлена через `generate_database.sh` после добавления метаданных.  
4) QR пересобран под ту же версию, что в release_metadata.  
5) APK собран из свежих артефактов.
