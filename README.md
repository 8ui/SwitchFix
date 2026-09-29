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
- **Telegram (Qt) выбрасывал вставляемый текст** — для таких приложений есть режим отправки через системный поток событий (вкладка **Приложения** в настройках, см. ниже).

### Детекция без словарей

- **Словари удалены.** Раскладку определяет символьная n-граммная модель каждого языка
  (~450 КБ вместо ~70 МБ словарей): набранное сравнивается с тем, как те же клавиши читаются в
  другой раскладке. Модель понимает словоформы (`hf,jnftn` → `работает`, `сфеы` → `cats`), сленг
  и техтермины, которых в словарях не было. Основной сценарий — родной текст с английскими
  вставками («создай новую worktree»); автоконвертации между русским и украинским нет. Подробности и
  замеры — `plan/005_ngram_layout_detection.md`, `plan/benchmarks/detector_005_phase2.md`.

### Доработки ручной коррекции

- **Хоткей на одиночное нажатие модификатора** — Option или Control: нажал и отпустил, без других клавиш. Сочетания `Option+…`/`Ctrl+…` работают как обычно. Ничего не печатает, в отличие от Option+Space, который вставляет неразрывный пробел. ([#16](https://github.com/rundax/SwitchFix/issues/16))
- **Хоткей переводит слово всегда** — даже если модель не уверена (опечатки, редкие слова): `rehk` → `курл`.
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

Всё настраивается в окне настроек (значок SwitchFix в строке меню → Настройки…, `⌘,`). Окно разбито на вкладки:

- **Основные** — включение SwitchFix, запуск при входе в систему, язык интерфейса (русский или английский, по умолчанию как в системе; меняется сразу, без перезапуска) и состояние разрешений macOS с кнопками, которые открывают нужную страницу Системных настроек.
- **Исправление** → **Режим исправления**: выберите **Только по горячей клавише**, если нужна только ручная коррекция.
- **Исправление** → **Горячие клавиши** → **Исправить**: нажмите на поле, затем нажмите и отпустите Option (или Control). В поле появится `⌥ Option (одно нажатие)`. Обычные сочетания вроде `⌃⇧Space` записываются как раньше. Для **Отменить последнее** одиночный модификатор не поддерживается.
- **Приложения** — одна таблица для всех настроек по приложениям. Флажок **Исправлять** снят — SwitchFix не трогает текст в этом приложении (терминалы и IDE выключены по умолчанию). Колонка **Ввод текста** задаёт способ отправки исправлений: **Обычный** — напрямую процессу, **Системный поток** (session event tap) — для приложений, которые теряют текст, как Telegram (он уже в списке), **Системный поток (HID)** — если не помог предыдущий. Приложения добавляются кнопкой «+» (новые сразу исключаются из исправления), изменения применяются сразу.
- **О программе** — версия и установленные раскладки, которые видит SwitchFix.

В меню в строке меню остались только частые действия: включение/выключение, режим исправления, Настройки и Выход. Если не хватает разрешений или Caps Lock конфликтует с переключением раскладки macOS, сверху меню появляется предупреждение; нажатие на него ведёт туда, где это исправляется.

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
- **Permissions indicator** — missing macOS permissions show up at the top of the menu and in Settings → General.
- **Undo** — `Cmd+Z` within 5 seconds reverts the last correction.
- **Revert hotkey** — `CapsLock` reverts the last correction (configurable).
- **Three layouts** — English (US/ABC/British/Dvorak/Colemak), Ukrainian, and Russian.
- **Smart filtering** — skips password fields, URLs, emails, camelCase, mixed scripts.
- **App blacklist** — disabled in terminals, IDEs, and code editors by default (toggle per app in Settings → Apps).
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
- **Warnings** — missing permissions or a CapsLock conflict, each linking to where it is fixed
- **SwitchFix Enabled** toggle
- **Correction Mode** — Automatic, Hotkey Only (shows the current hotkey) or On Layout Switch
- **Settings…** (`⌘,`) — tabs General, Correction, Apps and About (installed layouts, version)
- **Quit**

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
3. On a word boundary (space, enter, tab), character n-gram language models score how plausible the keystrokes are as typed versus read on the other layout (English ↔ Ukrainian/Russian).
4. If the other reading is clearly more plausible, **TextCorrector** safely deletes the mistyped characters, switches your input layout, and retypes the correct word.

## License

MIT
