# Статус модулей

Обновлено: 2026-10-23. Первая успешная unsigned-сборка: GitHub Actions run
39971247853 (ветка `feature/ci-and-privacy-center`, коммит `631865dd`).
IPA 73 МБ, Bundle ID `com.rufogram.rufat`, arm64, версия 12.0 (31349).
На устройстве приложение не запускалось.

| Модуль | Статус | Файлы |
|---|---|---|
| Аудит | Готово | `docs/AUDIT.md` |
| CI workflow | Unsigned: собирается; signed: не запускался | `.github/workflows/ios-build.yml`, `tools/ci/*` |
| Генерация тестовых профилей под наш Bundle ID | Проверено локально (10 профилей) | `tools/ci/generate-fake-codesigning.py` |
| Подстановка API credentials из Secrets | Проверено локально | `tools/ci/prepare-configuration.py` |
| Privacy Center | Компилируется в CI; на устройстве не проверен | `Swiftgram/SGSettingsUI/Sources/PrivacyCenterController.swift` |
| Локальный архив сообщений | Не начат | — |
| Брендинг | Не начат | — |
| Подписанная сборка | Ждёт Secrets и первой успешной unsigned-сборки | — |

## Privacy Center

Вход: Настройки Swiftgram → «Центр приватности».

- Supported: скрытие номера в интерфейсе настроек, подтверждение перед открытием историй.
- PartiallySupported: Stealth mode для историй. Клиент не отправляет `markStoryAsSeen`
  (`TelegramEngineMessages.swift`), но анонимность не гарантируется; это указано в UI.
  Переключатель показывается, только если `canUseStealthMode`.
- Unsupported (только текст, без переключателей): скрытие прочтений от сервера,
  невидимость в сети, гарантированно анонимный просмотр историй без Premium,
  восстановление неполученных сообщений.
- Ссылка на штатный экран «Конфиденциальность» Telegram для серверных настроек.

## GitHub Secrets для CI

| Secret | Нужен для |
|---|---|
| `RUFATGRAM_API_ID`, `RUFATGRAM_API_HASH` | вход в аккаунт (my.telegram.org) |
| `RUFATGRAM_TEAM_ID`, `RUFATGRAM_BUNDLE_ID` | подпись; без них остаются заглушки |
| `BUILD_CERTIFICATE_BASE64`, `P12_PASSWORD`, `KEYCHAIN_PASSWORD` | signed-сборка |
| `PROVISIONING_PROFILE_BASE64` или `PROFILES_JSON_BASE64` | signed-сборка |
