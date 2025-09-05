#!/bin/bash

# Скрипт для смены MAC-адреса на macOS

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Функция для вывода сообщений
print_message() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Функция для безопасной валидации путей
validate_path() {
    local path="$1"
    local base_path="$2"
    
    # Проверяем на path traversal атаки
    if [[ "$path" == *".."* ]] || [[ "$path" == *"/"* ]] && [[ "$path" != "$base_path"* ]]; then
        print_error "Небезопасный путь: $path"
        return 1
    fi
    
    # Проверяем на null bytes
    if [[ "$path" == *$'\0'* ]]; then
        print_error "Путь содержит null bytes: $path"
        return 1
    fi
    
    return 0
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
        print_warning "MAC-адрес не является локально администрируемым"
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
            print_error "MAC-адрес зарезервирован: $mac"
            return 1
        fi
    done
    
    return 0
}

# Функция для проверки прав доступа к файлу
check_file_permissions() {
    local file="$1"
    local required_perms="$2"
    
    if [ ! -e "$file" ]; then
        return 1
    fi
    
    local perms=$(stat -f "%OLp" "$file" 2>/dev/null)
    if [ "$perms" != "$required_perms" ]; then
        print_warning "Небезопасные права доступа к файлу $file: $perms (требуется: $required_perms)"
        return 1
    fi
    
    return 0
}


# Функция для ограничения частоты операций
check_rate_limit() {
    local operation="$1"
    local max_attempts="$2"
    local time_window="$3"
    local rate_file="/tmp/mac_changer_rate_${operation}.txt"
    
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
        print_error "Превышен лимит операций: $attempts/$max_attempts за $time_window секунд"
        return 1
    fi
    
    # Добавляем текущую попытку
    echo "$current_time" >> "$rate_file"
    return 0
}

# Функция для аудита безопасности
audit_log() {
    local level="$1"
    local message="$2"
    local audit_file="/var/log/mac_changer_audit.log"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Создаем директорию если не существует
    mkdir -p "$(dirname "$audit_file")"
    
    echo "[$timestamp] [$level] [UID:$(id -u)] [PID:$$] $message" >> "$audit_file"
    
    # Ограничиваем размер файла аудита (последние 1000 записей)
    if [ -f "$audit_file" ]; then
        tail -n 1000 "$audit_file" > "${audit_file}.tmp" && mv "${audit_file}.tmp" "$audit_file"
    fi
}

# Функция для генерации случайного MAC-адреса
generate_random_mac() {
    # Генерируем MAC с локально администрируемым битом (второй символ должен быть 2, 6, A, или E)
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

# Функция для получения текущего MAC-адреса
get_current_mac() {
    local interface=$1
    ifconfig "$interface" | grep -o -E '([[:xdigit:]]{1,2}:){5}[[:xdigit:]]{1,2}' | head -1
}

# Функция для получения списка сетевых интерфейсов
get_network_interfaces() {
    ifconfig -l | tr ' ' '\n' | grep -E '^(en|wl)' | head -5
}

# Функция для отображения сравнения MAC-адресов
show_mac_comparison() {
    local old_mac=$1
    local new_mac=$2
    local interface=$3
    
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                    СРАВНЕНИЕ MAC-АДРЕСОВ                    ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC} Интерфейс: ${YELLOW}$interface${NC}"
    echo -e "${BLUE}║${NC} ──────────────────────────────────────────────────────────"
    echo -e "${BLUE}║${NC} ${RED}БЫЛО:${NC}  $old_mac"
    echo -e "${BLUE}║${NC} ${GREEN}СТАЛО:${NC} $new_mac"
    echo -e "${BLUE}║${NC} ──────────────────────────────────────────────────────────"
    
    if [ "$old_mac" = "$new_mac" ]; then
        echo -e "${BLUE}║${NC} ${YELLOW}СТАТУС:${NC} ${YELLOW}MAC-адрес НЕ ИЗМЕНИЛСЯ${NC}"
    else
        echo -e "${BLUE}║${NC} ${GREEN}СТАТУС:${NC} ${GREEN}MAC-адрес УСПЕШНО ИЗМЕНЕН${NC}"
    fi
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Функция для смены MAC-адреса
change_mac() {
    local interface=$1
    local new_mac=$2
    local old_mac
    old_mac=$(get_current_mac "$interface")
    
    # Аудит операции
    audit_log "INFO" "Начало смены MAC для интерфейса $interface: $old_mac -> $new_mac"
    
    # Проверяем лимит операций (максимум 5 попыток в минуту)
    if ! check_rate_limit "mac_change" 5 60; then
        audit_log "WARNING" "Превышен лимит операций смены MAC"
        return 1
    fi
    
    # Валидируем MAC-адрес
    if ! validate_mac_address "$new_mac"; then
        audit_log "ERROR" "Невалидный MAC-адрес: $new_mac"
        print_error "Невалидный MAC-адрес: $new_mac"
        return 1
    fi
    
    # Проверяем, что новый MAC отличается от текущего
    if [ "$old_mac" = "$new_mac" ]; then
        audit_log "WARNING" "Попытка установить тот же MAC-адрес: $new_mac"
        print_warning "MAC-адрес уже установлен: $new_mac"
        return 0
    fi
    
    print_message "Меняем MAC-адрес для интерфейса $interface"
    print_message "Старый MAC: $old_mac"
    print_message "Новый MAC:  $new_mac"
    
    # Создаем резервную копию текущего состояния
    local backup_file="/tmp/mac_backup_${interface}_$(date +%s).txt"
    ifconfig "$interface" > "$backup_file" 2>/dev/null
    
    # Отключаем интерфейс
    if ! ifconfig "$interface" down; then
        audit_log "ERROR" "Не удалось отключить интерфейс $interface"
        print_error "Не удалось отключить интерфейс $interface"
        return 1
    fi
    
    # Меняем MAC-адрес
    if ! ifconfig "$interface" ether "$new_mac"; then
        audit_log "ERROR" "Не удалось установить новый MAC $new_mac для $interface"
        print_error "Не удалось установить новый MAC-адрес"
        # Пытаемся восстановить интерфейс
        ifconfig "$interface" up
        return 1
    fi
    
    # Включаем интерфейс
    if ! ifconfig "$interface" up; then
        audit_log "ERROR" "Не удалось включить интерфейс $interface"
        print_error "Не удалось включить интерфейс $interface"
        return 1
    fi
    
    # Ждем стабилизации
    sleep 3
    
    # Проверяем, что MAC изменился
    local current_mac
    current_mac=$(get_current_mac "$interface")
    if [ "$current_mac" = "$new_mac" ]; then
        audit_log "SUCCESS" "MAC успешно изменен: $old_mac -> $current_mac"
        print_success "MAC-адрес успешно изменен!"
        show_mac_comparison "$old_mac" "$current_mac" "$interface"
        save_to_history "$interface" "$old_mac" "$current_mac" "УСПЕШНО ИЗМЕНЕН"
        # Удаляем резервную копию при успехе
        rm -f "$backup_file"
        return 0
    else
        audit_log "ERROR" "MAC не изменился: ожидался $new_mac, получен $current_mac"
        print_error "Не удалось изменить MAC-адрес"
        show_mac_comparison "$old_mac" "$current_mac" "$interface"
        save_to_history "$interface" "$old_mac" "$current_mac" "ОШИБКА ИЗМЕНЕНИЯ"
        return 1
    fi
}

# Функция для сохранения оригинального MAC
save_original_mac() {
    local interface=$1
    local original_mac=$2
    local mac_file="/tmp/original_mac_${interface}.txt"
    
    # Валидируем MAC-адрес
    if ! validate_mac_address "$original_mac"; then
        audit_log "ERROR" "Попытка сохранить невалидный оригинальный MAC: $original_mac"
        print_error "Невалидный оригинальный MAC-адрес: $original_mac"
        return 1
    fi
    
    # Валидируем путь к файлу
    if ! validate_path "$mac_file" "/tmp/"; then
        audit_log "ERROR" "Небезопасный путь для сохранения MAC: $mac_file"
        return 1
    fi
    
    # Сохраняем MAC-адрес
    echo "$original_mac" > "$mac_file"
    
    # Устанавливаем безопасные права доступа
    chmod 600 "$mac_file"
    
    # Проверяем права доступа
    if ! check_file_permissions "$mac_file" "600"; then
        audit_log "WARNING" "Небезопасные права доступа к файлу MAC: $mac_file"
    fi
    
    audit_log "INFO" "Оригинальный MAC сохранен: $original_mac в $mac_file"
    print_message "Оригинальный MAC-адрес сохранен: $original_mac"
}

# Функция для восстановления оригинального MAC
restore_original_mac() {
    local interface=$1
    local mac_file="/tmp/original_mac_${interface}.txt"
    
    if [ -f "$mac_file" ]; then
        local original_mac
        local current_mac
        original_mac=$(cat "$mac_file")
        current_mac=$(get_current_mac "$interface")
        
        print_message "Восстанавливаем оригинальный MAC-адрес"
        print_message "Текущий MAC:  $current_mac"
        print_message "Оригинальный: $original_mac"
        
        if [ "$current_mac" = "$original_mac" ]; then
            print_warning "MAC-адрес уже соответствует оригинальному"
            show_mac_comparison "$current_mac" "$original_mac" "$interface"
        else
            change_mac "$interface" "$original_mac"
            rm "$mac_file"
            print_success "Оригинальный MAC-адрес восстановлен"
        fi
    else
        print_warning "Файл с оригинальным MAC-адресом не найден"
        print_message "Попробуйте сначала сменить MAC-адрес, чтобы сохранить оригинальный"
    fi
}

# Функция для отображения истории смены MAC-адресов
show_mac_history() {
    local interface=$1
    local history_file="/tmp/mac_history_${interface}.txt"
    
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                    ИСТОРИЯ СМЕНЫ MAC                        ║${NC}"
    echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC} Интерфейс: ${YELLOW}$interface${NC}"
    
    if [ -f "$history_file" ]; then
        local line_count
        line_count=$(wc -l < "$history_file")
        if [ "$line_count" -gt 0 ]; then
            echo -e "${BLUE}║${NC} Записей в истории: ${GREEN}$line_count${NC}"
            echo -e "${BLUE}║${NC} ──────────────────────────────────────────────────────────"
            
            # Показываем последние 10 записей
            tail -n 10 "$history_file" | while IFS='|' read -r timestamp old_mac new_mac status; do
                echo -e "${BLUE}║${NC} ${timestamp}"
                echo -e "${BLUE}║${NC}   ${RED}БЫЛО:${NC}  $old_mac"
                echo -e "${BLUE}║${NC}   ${GREEN}СТАЛО:${NC} $new_mac"
                echo -e "${BLUE}║${NC}   Статус: $status"
                echo -e "${BLUE}║${NC} ──────────────────────────────────────────────────────────"
            done
        else
            echo -e "${BLUE}║${NC} ${YELLOW}История пуста${NC}"
        fi
    else
        echo -e "${BLUE}║${NC} ${YELLOW}Файл истории не найден${NC}"
        echo -e "${BLUE}║${NC} История будет создана при первой смене MAC-адреса"
    fi
    
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Функция для сохранения записи в историю
save_to_history() {
    local interface=$1
    local old_mac=$2
    local new_mac=$3
    local status=$4
    local history_file="/tmp/mac_history_${interface}.txt"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "${timestamp}|${old_mac}|${new_mac}|${status}" >> "$history_file"
}

# Функция для отображения справки
show_help() {
    echo "Использование: $0 [ОПЦИИ]"
    echo ""
    echo "ОПЦИИ:"
    echo "  -i, --interface INTERFACE    Сетевой интерфейс (по умолчанию: en0)"
    echo "  -m, --mac MAC_ADDRESS        Конкретный MAC-адрес для установки"
    echo "  -r, --restore                Восстановить оригинальный MAC-адрес"
    echo "  -l, --list                   Показать доступные интерфейсы"
    echo "  -s, --show                   Показать текущий MAC-адрес"
    echo "  -H, --history                Показать историю смены MAC-адресов"
    echo "  -h, --help                   Показать эту справку"
    echo ""
    echo "ПРИМЕРЫ:"
    echo "  $0                          # Сменить MAC на случайный для en0"
    echo "  $0 -i en1                   # Сменить MAC для интерфейса en1"
    echo "  $0 -m 02:11:22:33:44:55     # Установить конкретный MAC"
    echo "  $0 -r                       # Восстановить оригинальный MAC"
    echo "  $0 -l                       # Показать доступные интерфейсы"
    echo "  $0 -H                       # Показать историю смены MAC"
}

# Функция для отображения доступных интерфейсов
list_interfaces() {
    print_message "Доступные сетевые интерфейсы:"
    local interfaces
    mapfile -t interfaces < <(get_network_interfaces)
    for interface in "${interfaces[@]}"; do
        local mac
        local status
        mac=$(get_current_mac "$interface")
        status=$(ifconfig "$interface" | grep -q "status: active" && echo "активен" || echo "неактивен")
        echo "  $interface: $mac ($status)"
    done
}

# Функция для отображения текущего MAC
show_current_mac() {
    local interface=$1
    local mac
    local mac_file="/tmp/original_mac_${interface}.txt"
    mac=$(get_current_mac "$interface")
    
    if [ -n "$mac" ]; then
        echo ""
        echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║                    ТЕКУЩИЙ MAC-АДРЕС                       ║${NC}"
        echo -e "${BLUE}╠══════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${BLUE}║${NC} Интерфейс: ${YELLOW}$interface${NC}"
        echo -e "${BLUE}║${NC} MAC-адрес: ${GREEN}$mac${NC}"
        
        if [ -f "$mac_file" ]; then
            local original_mac
            original_mac=$(cat "$mac_file")
            echo -e "${BLUE}║${NC} Оригинальный: ${YELLOW}$original_mac${NC}"
            if [ "$mac" = "$original_mac" ]; then
                echo -e "${BLUE}║${NC} Статус: ${GREEN}Оригинальный MAC-адрес${NC}"
            else
                echo -e "${BLUE}║${NC} Статус: ${YELLOW}Измененный MAC-адрес${NC}"
            fi
        else
            echo -e "${BLUE}║${NC} Статус: ${YELLOW}Оригинальный MAC не сохранен${NC}"
        fi
        
        echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
    else
        print_error "Не удалось получить MAC-адрес для $interface"
    fi
}

# Основная функция
main() {
    local interface="en0"
    local new_mac=""
    local restore=false
    local list=false
    local show=false
    local history=false
    
    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--interface)
                interface="$2"
                shift 2
                ;;
            -m|--mac)
                new_mac="$2"
                shift 2
                ;;
            -r|--restore)
                restore=true
                shift
                ;;
            -l|--list)
                list=true
                shift
                ;;
            -s|--show)
                show=true
                shift
                ;;
            -H|--history)
                history=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "Неизвестная опция: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Проверка прав администратора
    if [ "$EUID" -ne 0 ]; then
        print_error "Этот скрипт должен запускаться с правами администратора (sudo)"
        exit 1
    fi
    
    # Аудит запуска скрипта
    audit_log "INFO" "Запуск скрипта смены MAC-адреса с параметрами: $*"
    
    # Проверяем, что скрипт запущен из безопасного окружения
    if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_TTY" ]; then
        audit_log "WARNING" "Скрипт запущен через SSH соединение"
        print_warning "Скрипт запущен через SSH. Убедитесь в безопасности соединения."
    fi
    
    
    # Обработка различных режимов
    if [ "$list" = true ]; then
        list_interfaces
        exit 0
    fi
    
    if [ "$show" = true ]; then
        show_current_mac "$interface"
        exit 0
    fi
    
    if [ "$history" = true ]; then
        show_mac_history "$interface"
        exit 0
    fi
    
    if [ "$restore" = true ]; then
        restore_original_mac "$interface"
        exit 0
    fi
    
    # Проверка существования интерфейса
    if ! ifconfig "$interface" >/dev/null 2>&1; then
        print_error "Интерфейс $interface не найден"
        list_interfaces
        exit 1
    fi
    
    # Получение текущего MAC-адреса
    local current_mac
    current_mac=$(get_current_mac "$interface")
    if [ -z "$current_mac" ]; then
        print_error "Не удалось получить текущий MAC-адрес для $interface"
        exit 1
    fi
    
    print_message "Начинаем процесс смены MAC-адреса для интерфейса $interface"
    print_message "Текущий MAC-адрес: $current_mac"
    
    # Сохранение оригинального MAC (если еще не сохранен)
    if [ ! -f "/tmp/original_mac_${interface}.txt" ]; then
        save_original_mac "$interface" "$current_mac"
    fi
    
    # Генерация нового MAC-адреса, если не указан
    if [ -z "$new_mac" ]; then
        new_mac=$(generate_random_mac)
        print_message "Сгенерирован случайный MAC-адрес: $new_mac"
    else
        # Улучшенная проверка MAC-адреса
        if ! validate_mac_address "$new_mac"; then
            audit_log "ERROR" "Попытка использовать невалидный MAC-адрес: $new_mac"
            print_error "Неверный формат или небезопасный MAC-адрес: $new_mac"
            print_message "Правильный формат: XX:XX:XX:XX:XX:XX (локально администрируемый)"
            exit 1
        fi
        audit_log "INFO" "Использование указанного MAC-адреса: $new_mac"
        print_message "Используем указанный MAC-адрес: $new_mac"
    fi
    
    # Смена MAC-адреса
    if change_mac "$interface" "$new_mac"; then
        print_success "Процесс смены MAC-адреса завершен успешно!"
        print_message "Для восстановления оригинального MAC используйте: sudo $0 -r"
        print_message "Для просмотра текущего MAC используйте: sudo $0 -s"
    else
        print_error "Процесс смены MAC-адреса завершился с ошибкой"
        exit 1
    fi
}

# Запуск основной функции
main "$@"
