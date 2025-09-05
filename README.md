# MAC Address Changer для macOS

Профессиональный инструмент для смены MAC-адресов сетевых интерфейсов на macOS с поддержкой автоматической службы и расширенными функциями безопасности.

## 🚀 Возможности

### Основные функции
- **Ручная смена MAC-адреса** - смена MAC-адреса с помощью простых команд
- **Автоматическая служба** - автоматическая смена MAC-адреса каждые 6 часов
- **Восстановление оригинального MAC** - возможность вернуть оригинальный MAC-адрес
- **История операций** - ведение журнала всех операций смены MAC
- **Валидация MAC-адресов** - проверка корректности и безопасности MAC-адресов

### Функции безопасности
- **Аудит операций** - логирование всех действий с MAC-адресами
- **Ограничение частоты операций** - защита от злоупотреблений
- **Валидация путей** - защита от path traversal атак
- **Проверка прав доступа** - контроль безопасности файлов
- **Криптографически стойкая генерация** - использование /dev/urandom

## 📁 Структура проекта

```
TTL/
├── change_mac.sh              # Основной скрипт для смены MAC-адреса
├── mac_changer_service.sh     # Системная служба для автоматической смены
├── install_service.sh         # Скрипт установки системной службы
├── com.macchanger.daemon.plist # Конфигурация LaunchDaemon
├── LICENSE                    # Лицензия MIT
└── README.md                  # Документация проекта
```

## 🛠 Установка

### Требования
- macOS (протестировано на macOS 10.15+)
- Права администратора (sudo)
- Bash 4.0+

### Установка системной службы

1. **Клонируйте репозиторий:**
   ```bash
   git clone <repository-url>
   cd TTL
   ```

2. **Установите службу:**
   ```bash
   sudo ./install_service.sh install
   ```

3. **Проверьте статус:**
   ```bash
   sudo ./install_service.sh status
   ```

## 📖 Использование

### Ручная смена MAC-адреса

#### Основные команды

```bash
# Сменить MAC-адрес на случайный для интерфейса en0
sudo ./change_mac.sh

# Сменить MAC для конкретного интерфейса
sudo ./change_mac.sh -i en1

# Установить конкретный MAC-адрес
sudo ./change_mac.sh -m 02:11:22:33:44:55

# Восстановить оригинальный MAC-адрес
sudo ./change_mac.sh -r

# Показать текущий MAC-адрес
sudo ./change_mac.sh -s

# Показать доступные интерфейсы
sudo ./change_mac.sh -l

# Показать историю смены MAC-адресов
sudo ./change_mac.sh -H
```

#### Параметры командной строки

| Параметр | Описание |
|----------|----------|
| `-i, --interface` | Сетевой интерфейс (по умолчанию: en0) |
| `-m, --mac` | Конкретный MAC-адрес для установки |
| `-r, --restore` | Восстановить оригинальный MAC-адрес |
| `-l, --list` | Показать доступные интерфейсы |
| `-s, --show` | Показать текущий MAC-адрес |
| `-H, --history` | Показать историю смены MAC-адресов |
| `-h, --help` | Показать справку |

### Управление системной службой

#### Команды службы

```bash
# Запустить службу
sudo /usr/local/bin/mac_changer_service.sh start

# Остановить службу
sudo /usr/local/bin/mac_changer_service.sh stop

# Перезапустить службу
sudo /usr/local/bin/mac_changer_service.sh restart

# Проверить статус службы
sudo /usr/local/bin/mac_changer_service.sh status

# Принудительно сменить MAC-адрес
sudo /usr/local/bin/mac_changer_service.sh change

# Восстановить оригинальный MAC-адрес
sudo /usr/local/bin/mac_changer_service.sh restore

# Показать детальную информацию о MAC-адресе
sudo /usr/local/bin/mac_changer_service.sh info

# Показать историю смены MAC-адресов
sudo /usr/local/bin/mac_changer_service.sh history

# Показать логи службы
sudo /usr/local/bin/mac_changer_service.sh logs
```

#### Управление через LaunchDaemon

```bash
# Проверить статус службы
sudo launchctl list | grep macchanger

# Остановить службу
sudo launchctl unload /Library/LaunchDaemons/com.macchanger.daemon.plist

# Запустить службу
sudo launchctl load /Library/LaunchDaemons/com.macchanger.daemon.plist
```

## 🔧 Конфигурация

### Файлы конфигурации

- **Логи службы:** `/var/log/mac_changer.log`
- **Логи демона:** `/var/log/mac_changer_daemon.log`
- **Ошибки демона:** `/var/log/mac_changer_daemon_error.log`
- **PID файл:** `/var/run/mac_changer.pid`
- **Оригинальный MAC:** `/var/lib/mac_changer/original_mac.txt`
- **История операций:** `/var/lib/mac_changer/mac_history.txt`

### Настройка интерфейса

По умолчанию служба работает с интерфейсом `en0`. Для изменения интерфейса отредактируйте переменную `INTERFACE` в файле `mac_changer_service.sh`:

```bash
INTERFACE="en1"  # Изменить на нужный интерфейс
```

## 🔒 Безопасность

### Валидация MAC-адресов

Скрипт проверяет:
- **Формат MAC-адреса** - корректность структуры XX:XX:XX:XX:XX:XX
- **Локально администрируемые адреса** - второй байт должен быть 2, 6, A или E
- **Зарезервированные адреса** - блокировка multicast и broadcast адресов

### Аудит и логирование

- **Детальное логирование** всех операций с MAC-адресами
- **Аудит безопасности** с указанием UID, PID и временных меток
- **Ограничение частоты операций** для предотвращения злоупотреблений
- **Проверка прав доступа** к файлам конфигурации

### Защита от атак

- **Path traversal защита** - валидация всех путей к файлам
- **Null byte защита** - проверка на null bytes в путях
- **Rate limiting** - ограничение количества операций в единицу времени

## 📊 Мониторинг

### Просмотр логов

```bash
# Просмотр основных логов
sudo tail -f /var/log/mac_changer.log

# Просмотр логов демона
sudo tail -f /var/log/mac_changer_daemon.log

# Просмотр ошибок
sudo tail -f /var/log/mac_changer_daemon_error.log
```

### Проверка статуса

```bash
# Статус службы
sudo /usr/local/bin/mac_changer_service.sh status

# Информация о MAC-адресе
sudo /usr/local/bin/mac_changer_service.sh info

# История операций
sudo /usr/local/bin/mac_changer_service.sh history
```

## 🗑 Удаление

### Удаление службы

```bash
# Удалить службу и восстановить оригинальный MAC
sudo ./install_service.sh uninstall
```

### Ручная очистка

```bash
# Остановить службу
sudo launchctl unload /Library/LaunchDaemons/com.macchanger.daemon.plist

# Удалить файлы
sudo rm -f /Library/LaunchDaemons/com.macchanger.daemon.plist
sudo rm -f /usr/local/bin/mac_changer_service.sh

# Восстановить оригинальный MAC (если сохранен)
if [ -f "/var/lib/mac_changer/original_mac.txt" ]; then
    original_mac=$(cat "/var/lib/mac_changer/original_mac.txt")
    sudo ifconfig en0 down
    sudo ifconfig en0 ether "$original_mac"
    sudo ifconfig en0 up
fi

# Удалить файлы конфигурации
sudo rm -rf /var/lib/mac_changer
sudo rm -f /var/run/mac_changer.pid
```

## ⚠️ Предупреждения

### Правовые аспекты
- **Используйте только в законных целях** - тестирование, исследования, защита приватности
- **Соблюдайте местное законодательство** - в некоторых юрисдикциях смена MAC-адресов может быть ограничена
- **Уведомляйте администраторов сети** - при использовании в корпоративных сетях

### Технические ограничения
- **Требуются права администратора** - скрипт должен запускаться с sudo
- **Временная смена** - MAC-адрес сбрасывается при перезагрузке системы
- **Совместимость** - протестировано на macOS 10.15+, может не работать на старых версиях

### Безопасность сети
- **Может нарушить подключение** - некоторые сети привязывают устройства к MAC-адресам
- **VPN и фильтрация** - может потребоваться перенастройка VPN и сетевых фильтров
- **Мониторинг** - изменения MAC-адресов могут быть зафиксированы в логах сети

## 🐛 Устранение неполадок

### Частые проблемы

#### Служба не запускается
```bash
# Проверить логи ошибок
sudo tail -f /var/log/mac_changer_daemon_error.log

# Проверить права доступа
ls -la /usr/local/bin/mac_changer_service.sh
ls -la /Library/LaunchDaemons/com.macchanger.daemon.plist
```

#### MAC-адрес не меняется
```bash
# Проверить активность интерфейса
ifconfig en0

# Проверить права администратора
sudo -v

# Проверить логи
sudo tail -f /var/log/mac_changer.log
```

#### Интерфейс не найден
```bash
# Показать все интерфейсы
ifconfig -l

# Показать доступные интерфейсы
sudo ./change_mac.sh -l
```

### Диагностика

```bash
# Полная диагностика
sudo /usr/local/bin/mac_changer_service.sh info
sudo /usr/local/bin/mac_changer_service.sh status
sudo /usr/local/bin/mac_changer_service.sh logs
```

## 📝 Лицензия

Этот проект распространяется под лицензией MIT. См. файл [LICENSE](LICENSE) для подробностей.

## 🤝 Вклад в проект

Мы приветствуем вклад в развитие проекта! Пожалуйста:

1. Форкните репозиторий
2. Создайте ветку для новой функции (`git checkout -b feature/amazing-feature`)
3. Зафиксируйте изменения (`git commit -m 'Add amazing feature'`)
4. Отправьте в ветку (`git push origin feature/amazing-feature`)
5. Откройте Pull Request

## 📞 Поддержка

Если у вас возникли вопросы или проблемы:

1. Проверьте раздел [Устранение неполадок](#-устранение-неполадок)
2. Изучите логи системы
3. Создайте issue в репозитории с подробным описанием проблемы

## 🔄 История версий

### v1.0.0
- Первоначальный релиз
- Ручная смена MAC-адресов
- Автоматическая системная служба
- Расширенные функции безопасности
- Полная документация

---

**⚠️ ВАЖНО:** Этот инструмент предназначен только для образовательных и тестовых целей. Пользователи несут полную ответственность за соблюдение всех применимых законов и правил при использовании данного программного обеспечения.
