# SwitchFix

A macOS menu bar utility that automatically corrects keyboard layout mistakes. Type in the wrong layout (e.g., English instead of Ukrainian/Russian) and SwitchFix detects it, deletes the mistyped word, switches the layout, and retypes the correct text — like PuntoSwitcher, but native, lightweight, and modern.

![SwitchFix Demo](SwitchFix.gif)
![SwitchFix App Icon](Resources/Assets.xcassets/AppIcon.svg)

## Об этом форке

Форк [rundax/SwitchFix](https://github.com/rundax/SwitchFix) (v0.0.9) с исправлениями для свежих macOS/Swift и доработками ручной коррекции. Проверено на macOS 27.0, Apple Silicon, Xcode 27 / Swift 6.4.

### Исправления

- **Словари не находились при сборке на Swift 6.4** — `build-app.sh` клал `*.bin` в корень `SwitchFix_Dictionary.bundle`, а новый SwiftPM собирает бандл со структурой `Contents/Resources`. В итоге коррекция молча не работала совсем. ([#14](https://github.com/rundax/SwitchFix/issues/14))
- **После переключения раскладки клавишей 🌐 (Globe) терялись нажатия** — отложенная проверка фокуса отбрасывалась как устаревшая, и до клика мышью все буквы выпадали из буфера (или терялась первая: `ghbdtn` → `gпривет`). ([#15](https://github.com/rundax/SwitchFix/issues/15))
- **В Chromium/Electron (Claude, Chrome) хоткей стирал слова целиком** — синтетические Backspace доходили до приложения раньше отпускания модификатора и превращались в Option+Backspace. Теперь у синтетических нажатий модификаторы явно сброшены.
- **Выделение в Electron-приложениях** — перед чтением выделения включается `AXManualAccessibility`, без него Electron не отдаёт поле ввода через Accessibility.
- **Telegram (Qt) выбрасывал вставляемый текст** — для таких приложений есть режим отправки через системный поток событий (секция **App Compatibility** в настройках, см. ниже).

### Доработки ручной коррекции

- **Хоткей на одиночное нажатие модификатора** — Option или Control: нажал и отпустил, без других клавиш. Сочетания `Option+…`/`Ctrl+…` работают как обычно. Ничего не печатает, в отличие от Option+Space, который вставляет неразрывный пробел. ([#16](https://github.com/rundax/SwitchFix/issues/16))
- **Хоткей переводит слово всегда** — даже если его нет в словаре (опечатки, редкие слова): `ghbftn` → `приает`. Автоматический режим по-прежнему сверяется со словарём.
- **Исходная раскладка определяется по тексту**, а не по активной раскладке системы: `пше` → `git` работает, даже если система считает раскладку английской. Выделение можно конвертировать туда и обратно сколько угодно раз, фраза с запятой не ломается (`ghbdtn, vbh` ⇄ `привет, мир`).

### Установка и настройка форка

```bash
git clone https://github.com/8ui/SwitchFix.git
cd SwitchFix
./scripts/setup-codesign.sh   # один раз: стабильная подпись, разрешения переживают пересборку
./install.sh
```

Если `setup-codesign.sh` не находит только что созданный сертификат, значит, macOS считает его недоверенным. Разрешите его для подписи кода (попросит пароль) и запустите скрипт ещё раз:

```bash
security find-certificate -c "SwitchFix Development" -p > /tmp/switchfix.pem && security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db /tmp/switchfix.pem
```

Всё настраивается в окне настроек (значок SwitchFix в строке меню → Settings…):

- **Correction Mode** → **Hotkey Only**, если нужна только ручная коррекция.
- **Shortcuts → Trigger Correction**: нажмите на поле, затем нажмите и отпустите Option (или Control). В поле появится `⌥ Option (tap)`. Обычные сочетания вроде `⌃⇧Space` записываются как раньше. Для **Revert Last** одиночный модификатор не поддерживается.
- **App Compatibility**: способ отправки текста для отдельных приложений. Telegram уже в списке с режимом **Session event tap**. Если другое приложение теряет исправленный текст, добавьте его кнопкой «+» и выберите Session или HID. **Default** — обычная отправка напрямую процессу. Изменения применяются сразу.

Не используйте одиночный Control, если включена диктовка macOS: её системный хоткей — двойное нажатие Control.

Альтернатива — те же настройки через Терминал (после этого перезапустите SwitchFix):

```bash
defaults write com.switchfix.app SwitchFix_correctionMode -string hotkey
defaults write com.switchfix.app SwitchFix_hotkeyKeyCode -int 58      # одиночный Option; Control — 59
defaults write com.switchfix.app SwitchFix_hotkeyModifiers -int 0
defaults write com.switchfix.app SwitchFix_postModeByApp -dict com.tdesktop.Telegram session
```

Обновиться с оригинального репозитория:

```bash
git remote add upstream https://github.com/rundax/SwitchFix.git   # один раз
git pull upstream master
```

---

## Features

- **Automatic correction** — detects wrong-layout words on space/enter and corrects them instantly.
- **Hotkey mode** — correct only when you press Ctrl+Shift+Space (configurable).
- **Selection correction** — select text and press the hotkey to convert it.
- **Permissions indicator** — shows the status of required macOS permissions in the app menu.
- **Undo** — `Cmd+Z` within 5 seconds reverts the last correction.
- **Revert hotkey** — `CapsLock` reverts the last correction (configurable).
- **Three layouts** — English (US/ABC/British/Dvorak/Colemak), Ukrainian, and Russian.
- **Smart filtering** — skips password fields, URLs, emails, camelCase, mixed scripts.
- **App blacklist** — disabled in terminals, IDEs, and code editors by default (toggle per app).
- **Launch at Login** — optional auto-start.

## Requirements

- macOS 13.0 or later

## Installation

### From source

```bash
git clone https://github.com/rundax/SwitchFix.git
cd SwitchFix
./install.sh
```

The script builds the app, installs it to `/Applications`, sets it to run at startup, and guides you through the required **Accessibility** and **Input Monitoring** permissions.

> **Note:** Requires Xcode Command Line Tools. The script will prompt you to install them if missing.

### From DMG

Download a pre-built `.dmg` from the [Releases page](https://github.com/rundax/SwitchFix/releases), open it, and double-click **Install SwitchFix**.

## Development

### Stable code signing (recommended)

Ad-hoc signing (the default) changes the binary hash on every build, which forces you to re-grant Accessibility and Input Monitoring permissions each time. To avoid this, create a local code-signing certificate once:

```bash
./scripts/setup-codesign.sh
```

This creates a self-signed certificate in your Keychain and saves it to `.codesign-identity`. All subsequent builds via `build-app.sh` and `install.sh` will use it automatically — permissions survive rebuilds.

### Build without installing

```bash
./scripts/build-app.sh          # → dist/SwitchFix.app
```

### Create a DMG

```bash
./scripts/create-dmg.sh         # → dist/SwitchFix.dmg
```

## Menu Bar Options

SwitchFix lives in your menu bar with an **Ab** icon. The menu provides:
- **Enable/Disable** toggle
- **Correction Mode** — Automatic or Hotkey Only
- **Permissions Status** — visually indicates if required permissions are granted
- **Installed Layouts** — shows all detected system layouts
- **Launch at Login** — toggle automatic startup

## Advanced Configuration

SwitchFix stores hotkeys in `UserDefaults`. Customize via Terminal:

```bash
# Revert hotkey: CapsLock (no modifiers)
defaults write com.switchfix.app SwitchFix_revertHotkeyKeyCode -int 57
defaults write com.switchfix.app SwitchFix_revertHotkeyModifiers -int 0

# Correction hotkey: Ctrl+Shift+Space
defaults write com.switchfix.app SwitchFix_hotkeyKeyCode -int 49
defaults write com.switchfix.app SwitchFix_hotkeyModifiers -int $((262144+131072))

# Correction hotkey: lone Option tap (fork; 59 = lone Control tap)
defaults write com.switchfix.app SwitchFix_hotkeyKeyCode -int 58
defaults write com.switchfix.app SwitchFix_hotkeyModifiers -int 0

# Per-app event delivery for toolkits that drop Unicode events posted to the process (fork)
# values: session | hid
defaults write com.switchfix.app SwitchFix_postModeByApp -dict com.tdesktop.Telegram session
```

## How It Works

1. **KeyboardMonitor** securely captures keystrokes without blocking them.
2. Characters accumulate in a short-lived **LayoutDetector** word buffer.
3. On a word boundary (space, enter, tab), the buffer is checked against alternative layout dictionaries (e.g. checking if an English typo forms a valid Ukrainian word).
4. If a valid word is found in another layout, **TextCorrector** safely deletes the mistyped characters, switches your input layout, and retypes the correct word.

## License

MIT
