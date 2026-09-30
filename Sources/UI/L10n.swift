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
        "Correction Mode": "Режим исправления",
        "Automatic": "Автоматически",
        "SwitchFix Enabled": "SwitchFix включён",
        "Hotkey Only": "Только по горячей клавише",
        "Hotkey Only (%@)": "Только по горячей клавише (%@)",
        "On Layout Switch": "При смене раскладки",
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
        "Paused: secure input is on in %@": "Пауза: защищённый ввод включён в %@",
        "Paused: secure input is on": "Пауза: включён защищённый ввод",
        "While an app keeps secure input on (password fields, password managers, Secure Keyboard Entry in Terminal), macOS hides keystrokes from SwitchFix. Close the password field or turn Secure Keyboard Entry off.": "Пока приложение держит защищённый ввод (поля паролей, менеджеры паролей, «Защищённый ввод с клавиатуры» в Терминале), macOS скрывает нажатия от SwitchFix. Закройте поле пароля или выключите защищённый ввод.",
        "SwitchFix (paused: secure input is on)": "SwitchFix (пауза: включён защищённый ввод)",
        "Fix CapsLock Conflict…": "Устранить конфликт CapsLock…",
        "CapsLock is configured both in SwitchFix (revert) and in macOS (input source switch).":
            "CapsLock назначен и в SwitchFix (отмена), и в macOS (смена источника ввода).",

        // Settings window
        "General": "Основные",
        "Correction": "Исправление",
        "Apps": "Приложения",
        "About": "О программе",
        "Enable SwitchFix": "Включить SwitchFix",
        "Interface Language:": "Язык интерфейса:",
        "Permissions": "Разрешения",
        "Accessibility": "Универсальный доступ",
        "Input Monitoring": "Мониторинг ввода",
        "Granted": "Выдано",
        "Open System Settings…": "Открыть Системные настройки…",
        "SwitchFix needs both to see what you type and replace mistyped words.":
            "Оба разрешения нужны SwitchFix, чтобы видеть ввод и заменять слова, набранные не в той раскладке.",
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
        "Trigger Correction can be a single Option or Control press: click its field, then press and release the key.":
            "«Исправить» можно назначить на одиночное нажатие Option или Control: нажмите на поле, затем нажмите и отпустите клавишу.",
        "macOS also switches input sources with Caps Lock, so Revert Last may not fire. Pick another key, or turn off switching input sources with Caps Lock in System Settings → Keyboard.":
            "macOS тоже переключает раскладку по Caps Lock, поэтому «Отменить последнее» может не срабатывать. Назначьте другую клавишу или отключите переключение раскладки по Caps Lock в Системных настройках → Клавиатура.",
        "Double-pressing Control is the macOS Dictation shortcut. Consider Option instead.":
            "Двойное нажатие Control — системное сочетание для диктовки macOS. Лучше выбрать Option.",
        "Per-App Settings": "Настройки для приложений",
        "App": "Приложение",
        "Correct": "Исправлять",
        "Text Input": "Ввод текста",
        "Standard": "Обычный",
        "System Stream": "Системный поток",
        "System Stream (HID)": "Системный поток (HID)",
        "SwitchFix doesn't correct text in apps with Correct unchecked.":
            "В приложениях без флажка «Исправлять» SwitchFix текст не исправляет.",
        "If an app loses corrected text (e.g. Telegram), set its Text Input to System Stream; if that doesn't help, try System Stream (HID).":
            "Если приложение теряет исправленный текст (как Telegram), выберите для него ввод «Системный поток», а если не поможет — «Системный поток (HID)».",
        "Version %@": "Версия %@",
        "SwitchFix corrects between English, Ukrainian and Russian layouts.":
            "SwitchFix исправляет текст между английской, украинской и русской раскладками.",
        "Choose from Running Apps…": "Выбрать из запущенных…",
        "Choose from Applications Folder…": "Выбрать из папки «Программы»…",
        "Choose Running Apps": "Выберите запущенные приложения",
        "All running apps are already listed.": "Все запущенные приложения уже в списке.",
        "Cancel": "Отменить",
        "Add": "Добавить",

        // Sensitivity
        "Sensitivity": "Чувствительность",
        "Cautious": "Осторожно",
        "Bold": "Смело",
        "Corrects only clear cases.": "Исправляет только очевидные случаи.",
        "Fewer corrections, fewer mistakes.": "Меньше исправлений, меньше ошибок.",
        "Balanced (recommended).": "Сбалансированно (рекомендуется).",
        "Corrects more words, occasionally by mistake.": "Исправляет больше слов, иногда по ошибке.",
        "Corrects as much as possible; undo mistakes with Revert Last.": "Исправляет всё, что может; ошибки отменяйте «Отменить последнее».",

        // Words tab
        "Words": "Слова",
        "Learned Words": "Выученные слова",
        "Search": "Поиск",
        "All": "Все",
        "Don't correct": "Не исправлять",
        "Correct → %@": "Исправлять → %@",
        "Correct to": "Исправлять в",
        "Word": "Слово",
        "Layout": "Раскладка",
        "Rule": "Правило",
        "Source": "Источник",
        "Uses": "Срабатываний",
        "Revert": "Отмена",
        "Hotkey": "Хоткей",
        "Manual": "Вручную",
        "Last used: %@": "Последнее срабатывание: %@",
        "Never used": "Ещё не срабатывало",
        "Edit…": "Изменить…",
        "Delete": "Удалить",
        "Add Word": "Новое слово",
        "Edit Word": "Изменить слово",
        "Word:": "Слово:",
        "Typed on:": "Набрано в раскладке:",
        "Rule:": "Правило:",
        "Target layout:": "Целевая раскладка:",
        "Uses:": "Срабатываний:",
        "Save": "Сохранить",
        "Reset Learned Words…": "Сбросить выученные…",
        "Delete All Words…": "Удалить все слова…",
        "More actions": "Другие действия",
        "Reset": "Сбросить",
        "Delete All": "Удалить все",
        "Reset learned words? Words you added yourself stay.": "Сбросить выученные слова? Добавленные вами останутся.",
        "Delete all words? This can't be undone.": "Удалить все слова? Это нельзя отменить.",
        "Enter a word.": "Введите слово.",
        "The word is too long (64 characters at most).": "Слово слишком длинное (не больше 64 символов).",
        "These characters can't be typed on the selected layout.": "Эти символы нельзя набрать в выбранной раскладке.",
        "Choose a different target layout.": "Выберите другую целевую раскладку.",
        "SwitchFix converts only between English and Russian or Ukrainian.": "SwitchFix переводит только между английской и русской или украинской раскладками.",
        "This word is already in the list. Edit the existing entry instead.": "Это слово уже есть в списке — измените существующую запись.",
        "This entry has changed meanwhile. Close the form and try again.": "Запись тем временем изменилась. Закройте форму и попробуйте снова.",
        "SwitchFix learns from your actions: undoing an automatic correction adds “Don't correct”, converting a word with the hotkey adds “Correct”. Your own entries are never changed automatically.": "SwitchFix учится на ваших действиях: отмена автоматического исправления добавляет «Не исправлять», перевод слова горячей клавишей — «Исправлять». Добавленные вами записи автоматически не меняются.",
    ]
}
