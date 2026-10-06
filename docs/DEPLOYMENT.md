# Публикация веб-версии

Хостинг: Sites, публичный доступ по ссылке. Идентификатор проекта сохранён в `.openai/hosting.json`.

Отдельный checkout публикации: `/Users/oleggrinev/.codex/builds/turnaround-site`.
Он содержит только готовую веб-сборку в `dist/`, без локальных файлов разработки и секретов.

Для обновления: собрать актуальный Flutter web release закреплённым Flutter SDK, обновить `dist/` в checkout публикации и выполнить штатный workflow Sites для существующего project_id. Не создавать новый сайт. В корневом Flutter-проекте hosting.json хранит связь с публикацией; упаковка выполняется из отдельного checkout.

Исходная проверенная сборка: `/Users/oleggrinev/.codex/builds/turnaround-preview/build/web`.
Прогресс игры хранится в браузере посетителя. Сохранения localhost не переносятся автоматически на публичный домен.

Публичный адрес: https://turnaround-airport.yasnypon.chatgpt.site
Версия 1 опубликована 29 сентября 2026, статус Sites: succeeded.
