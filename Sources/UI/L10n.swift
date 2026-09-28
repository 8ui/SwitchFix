import Foundation

public enum AppLanguage: String, CaseIterable {
    case english = "en"
    case russian = "ru"

    /// Shown in the language's own form, so it is recognisable whatever language is active.
    public var nativeName: String {
        switch self {
        case .english: return "English"
        case .russian: return "Русский"
        }
    }

    /// Russian when it is the user's preferred system language, English otherwise.
    static var systemDefault: AppLanguage {
        Locale.preferredLanguages.first?.hasPrefix("ru") == true ? .russian : .english
    }
}

/// Interface strings, looked up by their English text; the active language is read
/// on every call, so a language switch applies as soon as the UI is redrawn.
enum L10n {
    static func tr(_ english: String) -> String {
        switch PreferencesManager.shared.language {
        case .english: return english
        case .russian: return russian[english] ?? english
        }
    }

    private static let russian: [String: String] = [
        // Status bar menu
        "Language": "Язык",
        "Enable": "Включить",
        "Disable": "Выключить",
        "Correction Mode": "Режим исправления",
        "Automatic": "Автоматически",
        "Hotkey Only": "Только по горячей клавише",
        "On Layout Switch": "При смене раскладки",
        "Enable in Current App": "Включить в текущем приложении",
        "App Filtering Unavailable": "Фильтр приложений недоступен",
        "Current App": "текущем приложении",
        "Enable in %@": "Включить в %@",
        "Disable in %@": "Выключить в %@",
        "Installed Layouts": "Установленные раскладки",
        "No supported layouts found": "Поддерживаемые раскладки не найдены",
        "English": "Английская",
        "Ukrainian": "Украинская",
        "Russian": "Русская",
        "Settings...": "Настройки…",
        "Launch at Login": "Запускать при входе в систему",
        "Quit SwitchFix": "Завершить SwitchFix",
        "Grant Accessibility Permission…": "Разрешить универсальный доступ…",
        "SwitchFix needs Accessibility access to monitor keyboard input and replace mistyped words.":
            "Для работы SwitchFix нужен универсальный доступ: так он следит за вводом и заменяет слова, набранные не в той раскладке.",
        "Grant Input Monitoring Permission…": "Разрешить мониторинг ввода…",
        "SwitchFix needs Input Monitoring access to observe keystrokes.":
            "Для работы SwitchFix нужен мониторинг ввода: так он видит нажатия клавиш.",
        "SwitchFix (missing permissions)": "SwitchFix (нет разрешений)",
        "SwitchFix (CapsLock conflict detected)": "SwitchFix (конфликт CapsLock)",
        "Warning: CapsLock conflicts with macOS input switching":
            "Внимание: CapsLock конфликтует с переключением раскладки macOS",
        "CapsLock is configured both in SwitchFix (revert) and in macOS (input source switch).":
            "CapsLock назначен и в SwitchFix (отмена), и в macOS (смена источника ввода).",

        // Settings window
        "SwitchFix Settings": "Настройки SwitchFix",
        "General": "Основные",
        "Automatic (Space / Enter)": "Автоматически (пробел / Enter)",
        "Auto-corrects on word boundaries (space, enter).": "Исправляет автоматически в конце слова (пробел, Enter).",
        "Corrects only when triggered via hotkey.": "Исправляет только по горячей клавише.",
        "Corrects the current word (or selection) when you switch the system keyboard layout.":
            "Исправляет текущее слово (или выделение) при переключении системной раскладки.",
        "Shortcuts": "Горячие клавиши",
        "Trigger Correction:": "Исправить:",
        "Revert Last:": "Отменить последнее:",
        "Type Key...": "Нажмите клавишу…",
        "%@ (tap)": "%@ (одно нажатие)",
        "Space": "Пробел",
        "Left": "Влево",
        "Right": "Вправо",
        "Down": "Вниз",
        "Up": "Вверх",
        "Key %@": "Клавиша %@",
        "Double-pressing Control is the macOS Dictation shortcut. Consider Option instead.":
            "Двойное нажатие Control — системное сочетание для диктовки macOS. Лучше выбрать Option.",
        "Recommended: Set 'Revert Last' to Caps Lock to avoid conflicts.":
            "Рекомендуется назначить «Отменить последнее» на Caps Lock, чтобы избежать конфликтов.",
        "Excluded Apps": "Исключённые приложения",
        "SwitchFix won't correct text while these apps are active.":
            "SwitchFix не исправляет текст, пока активно одно из этих приложений.",
        "App Compatibility": "Совместимость с приложениями",
        "Some apps, such as Telegram, ignore text sent directly to them. For these apps SwitchFix types corrections through the system event stream instead.":
            "Некоторые приложения, например Telegram, игнорируют текст, отправленный им напрямую. Для них SwitchFix вводит исправления через системный поток событий.",
        "Default": "По умолчанию",
        "Session event tap": "Поток сеанса (session)",
        "HID event tap": "Поток HID (hid)",
        "Choose from Running Apps…": "Выбрать из запущенных…",
        "Choose from Applications Folder…": "Выбрать из папки «Программы»…",
        "Choose Running Apps": "Выберите запущенные приложения",
        "All running apps are already excluded.": "Все запущенные приложения уже исключены.",
        "All running apps are already listed.": "Все запущенные приложения уже в списке.",
        "Cancel": "Отменить",
        "Add": "Добавить",
    ]
}
