#!/bin/bash

# Системная служба для автоматической смены MAC-адреса на macOS
# Назначение: Автоматическая смена MAC-адреса интерфейса en0 каждые 6 часов

set -e

# Конфигурация
INTERFACE="en0"
LOG_FILE="/var/log/mac_changer.log"
PID_FILE="/var/run/mac_changer.pid"
CONFIG_FILE="/etc/mac_changer.conf"
ORIGINAL_MAC_FILE="/var/lib/mac_changer/original_mac.txt"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция для логирования
log_message() {
    local level=$1
    local message=$2
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    
    # Также выводим в консоль если не в режиме демона
    if [ "$DAEMON_MODE" != "true" ]; then
        case $level in
            "INFO") echo -e "${BLUE}[INFO]${NC} $message" ;;
            "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
            "WARNING") echo -e "${YELLOW}[WARNING]${NC} $message" ;;
            "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        esac
    fi
}

# Функция для генерации случайного MAC-адреса
generate_random_mac() {
    # Генерируем MAC с локально администрируемым битом
    local prefixes=("02" "06" "0A" "0E")
    local prefix=${prefixes[$RANDOM % ${#prefixes[@]}]}
    local suffix
    
    # Используем /dev/urandom для криптографически стойкой генерации
    if [ -r /dev/urandom ]; then
        suffix=$(od -An -N5 -tx1 /dev/urandom | tr -d ' \n' | sed 's/\(..\)/\1:/g; s/.$//')
    else
        # Fallback на openssl
        suffix=$(openssl rand -hex 5 | sed 's/\(..\)/\1:/g; s/.$//')
    fi
    
    echo "${prefix}:${suffix}"
}

# Функция для валидации MAC-адреса
validate_mac_address() {
    local mac="$1"
    
    # Проверяем базовый формат
    if [[ ! "$mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
        return 1
    fi
    
    # Проверяем, что это локально администрируемый MAC
    local second_byte="${mac:3:2}"
    if [[ ! "$second_byte" =~ ^(02|06|0A|0E|2|6|A|E)$ ]]; then
        log_message "WARNING" "MAC-адрес не является локально администрируемым: $mac"
        return 1
    fi
    
    # Проверяем на зарезервированные адреса
    local reserved_macs=(
        "00:00:00:00:00:00"
        "FF:FF:FF:FF:FF:FF"
        "01:00:5E:*"
        "01:80:C2:*"
        "33:33:*"
    )
    
    for reserved in "${reserved_macs[@]}"; do
        if [[ "$mac" == $reserved ]]; then
            log_message "ERROR" "MAC-адрес зарезервирован: $mac"
            return 1
        fi
    done
    
    return 0
}


# Функция для ограничения частоты операций службы
check_service_rate_limit() {
    local max_attempts=10
    local time_window=3600  # 1 час
    local rate_file="/var/run/mac_changer_rate.txt"
    
    local current_time=$(date +%s)
    local cutoff_time=$((current_time - time_window))
    
    # Очищаем старые записи
    if [ -f "$rate_file" ]; then
        while IFS= read -r line; do
            if [ "$line" -gt "$cutoff_time" ]; then
                echo "$line" >> "${rate_file}.tmp"
            fi
        done < "$rate_file"
        mv "${rate_file}.tmp" "$rate_file" 2>/dev/null || true
    fi
    
    # Подсчитываем текущие попытки
    local attempts=0
    if [ -f "$rate_file" ]; then
        attempts=$(wc -l < "$rate_file")
    fi
    
    if [ "$attempts" -ge "$max_attempts" ]; then
        log_message "WARNING" "Превышен лимит операций службы: $attempts/$max_attempts за $time_window секунд"
        return 1
    fi
    
    # Добавляем текущую попытку
    echo "$current_time" >> "$rate_file"
    return 0
}

# Функция для получения текущего MAC-адреса
get_current_mac() {
    local interface=$1
    ifconfig "$interface" 2>/dev/null | grep -o -E '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}' | head -1
}

# Функция для проверки активности интерфейса
is_interface_active() {
    local interface=$1
    ifconfig "$interface" 2>/dev/null | grep -q "status: active"
}

# Функция для логирования сравнения MAC-адресов
log_mac_comparison() {
    local old_mac=$1
    local new_mac=$2
    local interface=$3
    local status=$4
    
    log_message "INFO" "=== СРАВНЕНИЕ MAC-АДРЕСОВ ==="
    log_message "INFO" "Интерфейс: $interface"
    log_message "INFO" "БЫЛО:  $old_mac"
    log_message "INFO" "СТАЛО: $new_mac"
    log_message "INFO" "СТАТУС: $status"
    log_message "INFO" "=============================="
}

# Функция для смены MAC-адреса
change_mac() {
    local interface=$1
    local new_mac=$2
    local old_mac
    old_mac=$(get_current_mac "$interface")
    
    
    # Проверяем лимит операций
    if ! check_service_rate_limit; then
        log_message "WARNING" "Превышен лимит операций службы"
        return 1
    fi
    
    # Валидируем MAC-адрес
    if ! validate_mac_address "$new_mac"; then
        log_message "ERROR" "Невалидный MAC-адрес: $new_mac"
        return 1
    fi
    
    log_message "INFO" "Меняем MAC-адрес для интерфейса $interface"
    log_message "INFO" "Старый MAC: $old_mac"
    log_message "INFO" "Новый MAC:  $new_mac"
    
    # Проверяем активность интерфейса
    if ! is_interface_active "$interface"; then
        log_message "WARNING" "Интерфейс $interface неактивен, пропускаем смену MAC"
        return 1
    fi
    
    # Создаем резервную копию состояния интерфейса
    local backup_file="/var/run/mac_backup_${interface}_$(date +%s).txt"
    ifconfig "$interface" > "$backup_file" 2>/dev/null
    
    # Отключаем интерфейс
    if ! ifconfig "$interface" down; then
        log_message "ERROR" "Не удалось отключить интерфейс $interface"
        return 1
    fi
    sleep 1
    
    # Меняем MAC-адрес
    if ! ifconfig "$interface" ether "$new_mac"; then
        log_message "ERROR" "Не удалось установить новый MAC $new_mac для $interface"
        # Пытаемся восстановить интерфейс
        ifconfig "$interface" up
        return 1
    fi
    sleep 1
    
    # Включаем интерфейс
    if ! ifconfig "$interface" up; then
        log_message "ERROR" "Не удалось включить интерфейс $interface"
        return 1
    fi
    sleep 3
    
    # Проверяем, что MAC изменился
    local current_mac
    current_mac=$(get_current_mac "$interface")
    if [ "$current_mac" = "$new_mac" ]; then
        log_message "SUCCESS" "MAC-адрес успешно изменен!"
        log_mac_comparison "$old_mac" "$current_mac" "$interface" "УСПЕШНО ИЗМЕНЕН"
        save_to_history "$old_mac" "$current_mac" "УСПЕШНО ИЗМЕНЕН"
        # Удаляем резервную копию при успехе
        rm -f "$backup_file"
        return 0
    else
        log_message "ERROR" "Не удалось изменить MAC-адрес"
        log_mac_comparison "$old_mac" "$current_mac" "$interface" "ОШИБКА ИЗМЕНЕНИЯ"
        save_to_history "$old_mac" "$current_mac" "ОШИБКА ИЗМЕНЕНИЯ"
        return 1
    fi
}

# Функция для сохранения оригинального MAC
save_original_mac() {
    local interface=$1
    local original_mac=$2
    
    # Создаем директорию если не существует
    mkdir -p "$(dirname "$ORIGINAL_MAC_FILE")"
    
    echo "$original_mac" > "$ORIGINAL_MAC_FILE"
    log_message "INFO" "Оригинальный MAC-адрес сохранен: $original_mac"
}

# Функция для восстановления оригинального MAC
restore_original_mac() {
    if [ -f "$ORIGINAL_MAC_FILE" ]; then
        local original_mac
        local current_mac
        original_mac=$(cat "$ORIGINAL_MAC_FILE")
        current_mac=$(get_current_mac "$INTERFACE")
        
        log_message "INFO" "Восстанавливаем оригинальный MAC-адрес"
        log_message "INFO" "Текущий MAC:  $current_mac"
        log_message "INFO" "Оригинальный: $original_mac"
        
        if [ "$current_mac" = "$original_mac" ]; then
            log_message "WARNING" "MAC-адрес уже соответствует оригинальному"
            log_mac_comparison "$current_mac" "$original_mac" "$INTERFACE" "УЖЕ ОРИГИНАЛЬНЫЙ"
        else
            change_mac "$INTERFACE" "$original_mac"
            log_message "SUCCESS" "Оригинальный MAC-адрес восстановлен"
        fi
    else
        log_message "WARNING" "Файл с оригинальным MAC-адресом не найден"
        log_message "INFO" "Попробуйте сначала сменить MAC-адрес, чтобы сохранить оригинальный"
    fi
}

# Функция для инициализации службы
init_service() {
    log_message "INFO" "Инициализация службы смены MAC-адреса"
    
    # Проверяем существование интерфейса
    if ! ifconfig "$INTERFACE" >/dev/null 2>&1; then
        log_message "ERROR" "Интерфейс $INTERFACE не найден"
        exit 1
    fi
    
    # Получаем текущий MAC-адрес
    local current_mac
    current_mac=$(get_current_mac "$INTERFACE")
    if [ -z "$current_mac" ]; then
        log_message "ERROR" "Не удалось получить текущий MAC-адрес для $INTERFACE"
        exit 1
    fi
    
    log_message "INFO" "Текущий MAC-адрес для $INTERFACE: $current_mac"
    
    # Сохраняем оригинальный MAC (если еще не сохранен)
    if [ ! -f "$ORIGINAL_MAC_FILE" ]; then
        save_original_mac "$INTERFACE" "$current_mac"
    fi
}

# Функция для выполнения смены MAC
perform_mac_change() {
    local new_mac
    new_mac=$(generate_random_mac)
    log_message "INFO" "Сгенерирован новый MAC-адрес: $new_mac"
    
    if change_mac "$INTERFACE" "$new_mac"; then
        log_message "SUCCESS" "MAC-адрес успешно изменен на $new_mac"
        return 0
    else
        log_message "ERROR" "Не удалось изменить MAC-адрес"
        return 1
    fi
}

# Функция для работы в режиме демона
run_daemon() {
    log_message "INFO" "Запуск службы в режиме демона"
    
    # Инициализация
    init_service
    
    # Основной цикл
    while true; do
        # Ждем 6 часов (21600 секунд)
        sleep 21600
        
        # Проверяем, что служба все еще должна работать
        if [ -f "$PID_FILE" ] && [ "$(cat "$PID_FILE")" = "$$" ]; then
            log_message "INFO" "Выполняем плановую смену MAC-адреса"
            perform_mac_change
        else
            log_message "INFO" "Служба остановлена, завершаем работу"
            break
        fi
    done
}

# Функция для запуска службы
start_service() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        log_message "WARNING" "Служба уже запущена (PID: $(cat "$PID_FILE"))"
        return 1
    fi
    
    log_message "INFO" "Запуск службы смены MAC-адреса"
    
    # Запускаем в фоновом режиме
    DAEMON_MODE="true"
    run_daemon &
    local daemon_pid=$!
    
    # Сохраняем PID
    echo "$daemon_pid" > "$PID_FILE"
    
    log_message "SUCCESS" "Служба запущена (PID: $daemon_pid)"
    return 0
}

# Функция для остановки службы
stop_service() {
    if [ ! -f "$PID_FILE" ]; then
        log_message "WARNING" "Служба не запущена"
        return 1
    fi
    
    local pid
    pid=$(cat "$PID_FILE")
    if ! kill -0 "$pid" 2>/dev/null; then
        log_message "WARNING" "Процесс службы не найден"
        rm -f "$PID_FILE"
        return 1
    fi
    
    log_message "INFO" "Остановка службы (PID: $pid)"
    kill "$pid"
    rm -f "$PID_FILE"
    
    log_message "SUCCESS" "Служба остановлена"
    return 0
}

# Функция для проверки статуса службы
status_service() {
    if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
        local pid
        pid=$(cat "$PID_FILE")
        local current_mac
        current_mac=$(get_current_mac "$INTERFACE")
        
        log_message "INFO" "=== СТАТУС СЛУЖБЫ ==="
        log_message "INFO" "Служба: ЗАПУЩЕНА (PID: $pid)"
        log_message "INFO" "Интерфейс: $INTERFACE"
        log_message "INFO" "Текущий MAC: $current_mac"
        
        if [ -f "$ORIGINAL_MAC_FILE" ]; then
            local original_mac
            original_mac=$(cat "$ORIGINAL_MAC_FILE")
            log_message "INFO" "Оригинальный MAC: $original_mac"
            if [ "$current_mac" = "$original_mac" ]; then
                log_message "INFO" "Статус MAC: Оригинальный"
            else
                log_message "INFO" "Статус MAC: Измененный"
            fi
        else
            log_message "WARNING" "Оригинальный MAC не сохранен"
        fi
        
        log_message "INFO" "=================="
        return 0
    else
        log_message "WARNING" "Служба не запущена"
        return 1
    fi
}

# Функция для принудительной смены MAC
force_change() {
    log_message "INFO" "Принудительная смена MAC-адреса"
    perform_mac_change
}

# Функция для отображения справки
show_help() {
    echo "Системная служба для автоматической смены MAC-адреса"
    echo ""
    echo "Использование: $0 [КОМАНДА]"
    echo ""
    echo "КОМАНДЫ:"
    echo "  start       Запустить службу"
    echo "  stop        Остановить службу"
    echo "  restart     Перезапустить службу"
    echo "  status      Показать статус службы"
    echo "  change      Принудительно сменить MAC-адрес"
    echo "  restore     Восстановить оригинальный MAC-адрес"
    echo "  info        Показать детальную информацию о MAC-адресе"
    echo "  history     Показать историю смены MAC-адресов"
    echo "  logs        Показать логи службы"
    echo "  help        Показать эту справку"
    echo ""
    echo "ФАЙЛЫ:"
    echo "  Логи: $LOG_FILE"
    echo "  PID: $PID_FILE"
    echo "  Конфиг: $CONFIG_FILE"
    echo "  Оригинальный MAC: $ORIGINAL_MAC_FILE"
}

# Функция для показа логов
show_logs() {
    if [ -f "$LOG_FILE" ]; then
        tail -n 50 "$LOG_FILE"
    else
        log_message "WARNING" "Файл логов не найден"
    fi
}

# Функция для отображения детальной информации о MAC
show_mac_info() {
    local current_mac
    current_mac=$(get_current_mac "$INTERFACE")
    
    if [ -n "$current_mac" ]; then
        log_message "INFO" "=== ДЕТАЛЬНАЯ ИНФОРМАЦИЯ О MAC-АДРЕСЕ ==="
        log_message "INFO" "Интерфейс: $INTERFACE"
        log_message "INFO" "Текущий MAC: $current_mac"
        
        if [ -f "$ORIGINAL_MAC_FILE" ]; then
            local original_mac
            original_mac=$(cat "$ORIGINAL_MAC_FILE")
            log_message "INFO" "Оригинальный MAC: $original_mac"
            if [ "$current_mac" = "$original_mac" ]; then
                log_message "INFO" "Статус: Оригинальный MAC-адрес"
            else
                log_message "INFO" "Статус: Измененный MAC-адрес"
                log_message "INFO" "Изменение: $original_mac -> $current_mac"
            fi
        else
            log_message "WARNING" "Оригинальный MAC не сохранен"
            log_message "INFO" "Статус: Неизвестно (оригинальный не сохранен)"
        fi
        
        # Проверяем активность интерфейса
        if is_interface_active "$INTERFACE"; then
            log_message "INFO" "Интерфейс: АКТИВЕН"
        else
            log_message "WARNING" "Интерфейс: НЕАКТИВЕН"
        fi
        
        log_message "INFO" "=========================================="
    else
        log_message "ERROR" "Не удалось получить MAC-адрес для $INTERFACE"
    fi
}

# Функция для отображения истории смены MAC-адресов
show_mac_history() {
    local history_file="/var/lib/mac_changer/mac_history.txt"
    
    log_message "INFO" "=== ИСТОРИЯ СМЕНЫ MAC-АДРЕСОВ ==="
    log_message "INFO" "Интерфейс: $INTERFACE"
    
    if [ -f "$history_file" ]; then
        local line_count
        line_count=$(wc -l < "$history_file" 2>/dev/null || echo "0")
        if [ "$line_count" -gt 0 ]; then
            log_message "INFO" "Записей в истории: $line_count"
            log_message "INFO" "──────────────────────────────────────────"
            
            # Показываем последние 10 записей
            tail -n 10 "$history_file" | while IFS='|' read -r timestamp old_mac new_mac status; do
                log_message "INFO" "$timestamp"
                log_message "INFO" "  БЫЛО:  $old_mac"
                log_message "INFO" "  СТАЛО: $new_mac"
                log_message "INFO" "  Статус: $status"
                log_message "INFO" "──────────────────────────────────────────"
            done
        else
            log_message "WARNING" "История пуста"
        fi
    else
        log_message "WARNING" "Файл истории не найден"
        log_message "INFO" "История будет создана при первой смене MAC-адреса"
    fi
    
    log_message "INFO" "=========================================="
}

# Функция для сохранения записи в историю
save_to_history() {
    local old_mac=$1
    local new_mac=$2
    local status=$3
    local history_file="/var/lib/mac_changer/mac_history.txt"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Создаем директорию если не существует
    mkdir -p "$(dirname "$history_file")"
    
    echo "${timestamp}|${old_mac}|${new_mac}|${status}" >> "$history_file"
}

# Основная функция
main() {
    # Проверка прав администратора
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}[ERROR]${NC} Этот скрипт должен запускаться с правами администратора (sudo)"
        exit 1
    fi
    
    # Создаем директории если не существуют
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$(dirname "$PID_FILE")"
    mkdir -p "$(dirname "$ORIGINAL_MAC_FILE")"
    
    # Обработка команд
    case "${1:-help}" in
        start)
            start_service
            ;;
        stop)
            stop_service
            ;;
        restart)
            stop_service
            sleep 2
            start_service
            ;;
        status)
            status_service
            ;;
        change)
            init_service
            force_change
            ;;
        restore)
            restore_original_mac
            ;;
        info)
            show_mac_info
            ;;
        history)
            show_mac_history
            ;;
        logs)
            show_logs
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} Неизвестная команда: $1"
            show_help
            exit 1
            ;;
    esac
}

# Запуск основной функции
main "$@"
