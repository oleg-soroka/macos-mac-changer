#!/bin/bash

# Скрипт установки системной службы смены MAC-адреса

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Пути
SCRIPT_NAME="mac_changer_service.sh"
PLIST_NAME="com.macchanger.daemon.plist"
INSTALL_DIR="/usr/local/bin"
PLIST_DIR="/Library/LaunchDaemons"
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

# Функция для проверки прав администратора
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Этот скрипт должен запускаться с правами администратора (sudo)"
        exit 1
    fi
}

# Функция для проверки существования файлов
check_files() {
    if [ ! -f "$CURRENT_DIR/$SCRIPT_NAME" ]; then
        print_error "Файл $SCRIPT_NAME не найден в текущей директории"
        exit 1
    fi
    
    if [ ! -f "$CURRENT_DIR/$PLIST_NAME" ]; then
        print_error "Файл $PLIST_NAME не найден в текущей директории"
        exit 1
    fi
}

# Функция для остановки существующей службы
stop_existing_service() {
    print_message "Проверяем существующие службы..."
    
    if launchctl list | grep -q "com.macchanger.daemon"; then
        print_message "Останавливаем существующую службу..."
        launchctl unload "$PLIST_DIR/$PLIST_NAME" 2>/dev/null || true
        print_success "Существующая служба остановлена"
    fi
}

# Функция для установки скрипта
install_script() {
    print_message "Устанавливаем скрипт службы..."
    
    # Создаем директорию если не существует
    mkdir -p "$INSTALL_DIR"
    
    # Проверяем целостность исходного файла
    if [ ! -f "$CURRENT_DIR/$SCRIPT_NAME" ]; then
        print_error "Исходный файл $SCRIPT_NAME не найден"
        exit 1
    fi
    
    # Копируем скрипт
    cp "$CURRENT_DIR/$SCRIPT_NAME" "$INSTALL_DIR/"
    chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
    
    # Устанавливаем безопасные права доступа
    chown root:wheel "$INSTALL_DIR/$SCRIPT_NAME"
    
    print_success "Скрипт установлен в $INSTALL_DIR/$SCRIPT_NAME"
}

# Функция для установки LaunchDaemon
install_plist() {
    print_message "Устанавливаем LaunchDaemon..."
    
    # Копируем plist файл
    cp "$CURRENT_DIR/$PLIST_NAME" "$PLIST_DIR/"
    chmod 644 "$PLIST_DIR/$PLIST_NAME"
    chown root:wheel "$PLIST_DIR/$PLIST_NAME"
    
    print_success "LaunchDaemon установлен в $PLIST_DIR/$PLIST_NAME"
}

# Функция для запуска службы
start_service() {
    print_message "Запускаем службу..."
    
    # Загружаем службу
    launchctl load "$PLIST_DIR/$PLIST_NAME"
    
    # Ждем немного для запуска
    sleep 3
    
    # Проверяем статус
    if launchctl list | grep -q "com.macchanger.daemon"; then
        print_success "Служба успешно запущена"
    else
        print_error "Не удалось запустить службу"
        return 1
    fi
}

# Функция для создания директорий логов
create_log_directories() {
    print_message "Создаем директории для логов..."
    
    mkdir -p /var/log
    mkdir -p /var/run
    mkdir -p /var/lib/mac_changer
    
    print_success "Директории для логов созданы"
}

# Функция для проверки установки
verify_installation() {
    print_message "Проверяем установку..."
    
    # Проверяем файлы
    if [ -f "$INSTALL_DIR/$SCRIPT_NAME" ]; then
        print_success "Скрипт установлен: $INSTALL_DIR/$SCRIPT_NAME"
    else
        print_error "Скрипт не найден: $INSTALL_DIR/$SCRIPT_NAME"
        return 1
    fi
    
    if [ -f "$PLIST_DIR/$PLIST_NAME" ]; then
        print_success "LaunchDaemon установлен: $PLIST_DIR/$PLIST_NAME"
    else
        print_error "LaunchDaemon не найден: $PLIST_DIR/$PLIST_NAME"
        return 1
    fi
    
    # Проверяем статус службы
    if launchctl list | grep -q "com.macchanger.daemon"; then
        print_success "Служба запущена и работает"
    else
        print_warning "Служба не запущена"
    fi
}

# Функция для отображения информации об управлении
show_management_info() {
    echo ""
    print_message "Информация об управлении службой:"
    echo ""
    echo "  Проверить статус:"
    echo "    sudo launchctl list | grep macchanger"
    echo ""
    echo "  Остановить службу:"
    echo "    sudo launchctl unload $PLIST_DIR/$PLIST_NAME"
    echo ""
    echo "  Запустить службу:"
    echo "    sudo launchctl load $PLIST_DIR/$PLIST_NAME"
    echo ""
    echo "  Принудительно сменить MAC:"
    echo "    sudo $INSTALL_DIR/$SCRIPT_NAME change"
    echo ""
    echo "  Восстановить оригинальный MAC:"
    echo "    sudo $INSTALL_DIR/$SCRIPT_NAME restore"
    echo ""
    echo "  Просмотр логов:"
    echo "    sudo $INSTALL_DIR/$SCRIPT_NAME logs"
    echo "    tail -f /var/log/mac_changer.log"
    echo ""
}

# Функция для удаления службы
uninstall_service() {
    print_message "Удаляем службу..."
    
    # Останавливаем службу
    if launchctl list | grep -q "com.macchanger.daemon"; then
        launchctl unload "$PLIST_DIR/$PLIST_NAME" 2>/dev/null || true
    fi
    
    # Удаляем файлы
    rm -f "$PLIST_DIR/$PLIST_NAME"
    rm -f "$INSTALL_DIR/$SCRIPT_NAME"
    
    # Восстанавливаем оригинальный MAC
    if [ -f "/var/lib/mac_changer/original_mac.txt" ]; then
        print_message "Восстанавливаем оригинальный MAC-адрес..."
        local original_mac
        original_mac=$(cat "/var/lib/mac_changer/original_mac.txt")
        ifconfig en0 down
        ifconfig en0 ether "$original_mac"
        ifconfig en0 up
        print_success "Оригинальный MAC-адрес восстановлен: $original_mac"
    fi
    
    # Удаляем файлы конфигурации
    rm -rf /var/lib/mac_changer
    rm -f /var/run/mac_changer.pid
    
    print_success "Служба полностью удалена"
}

# Функция для отображения справки
show_help() {
    echo "Скрипт установки системной службы смены MAC-адреса"
    echo ""
    echo "Использование: $0 [КОМАНДА]"
    echo ""
    echo "КОМАНДЫ:"
    echo "  install     Установить службу (по умолчанию)"
    echo "  uninstall   Удалить службу"
    echo "  status      Показать статус службы"
    echo "  help        Показать эту справку"
    echo ""
    echo "ПРИМЕРЫ:"
    echo "  sudo $0 install    # Установить службу"
    echo "  sudo $0 uninstall  # Удалить службу"
    echo "  sudo $0 status     # Проверить статус"
}

# Основная функция
main() {
    case "${1:-install}" in
        install)
            print_message "Начинаем установку службы смены MAC-адреса..."
            check_root
            check_files
            stop_existing_service
            create_log_directories
            install_script
            install_plist
            start_service
            verify_installation
            show_management_info
            print_success "Установка завершена успешно!"
            ;;
        uninstall)
            print_message "Начинаем удаление службы..."
            check_root
            uninstall_service
            print_success "Удаление завершено!"
            ;;
        status)
            print_message "Проверяем статус службы..."
            if launchctl list | grep -q "com.macchanger.daemon"; then
                print_success "Служба запущена и работает"
                echo ""
                echo "Дополнительная информация:"
                echo "  Логи: /var/log/mac_changer.log"
                echo "  PID файл: /var/run/mac_changer.pid"
                echo "  Оригинальный MAC: /var/lib/mac_changer/original_mac.txt"
            else
                print_warning "Служба не запущена"
            fi
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "Неизвестная команда: $1"
            show_help
            exit 1
            ;;
    esac
}

# Запуск основной функции
main "$@"
