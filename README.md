# MIRA ✦

> Подготовлена первая реализация MVP. Инструкции запуска и точные границы функциональности: [docs/SETUP.md](docs/SETUP.md). Ручная проверка: [docs/QA.md](docs/QA.md).

> Твой день в гармонии.

MIRA — кроссплатформенное lifestyle-приложение для iOS и Android, которое
объединяет планирование, стиль и питание в единую персональную систему.

Главная идея MIRA:

**Что мне делать сегодня? · Что надеть? · Что поесть?**

Вместо нескольких независимых трекеров MIRA связывает данные между
разделами и использует их для формирования персонального дня пользователя.

---

# 📱 Платформы

MIRA разрабатывается одновременно для:

- iOS
- Android

Используется единая кодовая база на Flutter.

---

# 🛠 Технологии

## Frontend

- Flutter
- Dart

## Backend

Планируется:

- Supabase
- PostgreSQL
- Supabase Auth
- Supabase Storage

## AI

MIRA AI будет подключаться через отдельный backend/API-слой.

AI не является хранилищем пользовательских данных.

## Дополнительные интеграции

Планируются:

- Weather API
- системный календарь
- push-уведомления
- камера
- фотогалерея

---

# 🎨 Design System

Основное направление:

**Clean · Editorial · Premium · Lifestyle**

### Основной цвет

`#21A5AA`

### Фон

Тёплый молочный / кремовый.

### Интерфейс

- мягкие скругления;
- лёгкие тени;
- много свободного пространства;
- спокойные пастельные оттенки;
- минималистичные иконки;
- serif display typography для акцентных заголовков;
- clean sans-serif для основного интерфейса.

Интерфейс должен ощущаться как единая система на iOS и Android.

---

# 🧭 Основная навигация

В приложении пять основных разделов:

1. Сегодня
2. План
3. Стиль
4. Питание
5. Я

MIRA AI не является отдельной вкладкой.

AI вызывается контекстно внутри приложения через кнопку `✦`.

---

# 🏠 Сегодня

Главный экран MIRA.

Он не хранит отдельные данные, а собирает информацию из других модулей:

- события;
- задачи;
- образ дня;
- питание;
- привычки;
- рекомендации MIRA.

Контент экрана зависит от включённых пользователем модулей.

---

# 📅 План

Основные сущности:

- Event
- Task
- Habit
- HabitLog
- EventCategory

Основные режимы:

- День
- Неделя
- Месяц

Планируется поддержка системного календаря.

---

# 👗 Стиль

Основные сущности:

- WardrobeItem
- Outfit
- OutfitItem
- PlannedOutfit
- WishlistItem

Функции:

- цифровой гардероб;
- карточки вещей;
- создание образов;
- избранные образы;
- планирование образа на дату;
- история носки;
- cost per wear;
- рекомендации MIRA.

---

# 🍓 Питание

Основные сущности:

- Food
- MealEntry
- Recipe
- RecipeIngredient
- MealPlan
- PantryItem
- WaterLog
- NutritionProfile

Режимы:

- Планирование
- Баланс
- Калории и БЖУ

Калории не являются обязательной частью MIRA.

---

# 👤 Я

Содержит:

- профиль;
- выбранные модули;
- цели;
- привычки;
- статистику;
- настройки;
- настройки MIRA;
- уведомления;
- настройки питания;
- настройки стиля.

---

# ✦ MIRA AI

MIRA AI работает как интеллектуальный слой над данными приложения.

Примеры:

> Что надеть завтра?

MIRA учитывает:

- погоду;
- события;
- гардероб;
- недавно использованные образы.

---

> Что приготовить на ужин?

MIRA может учитывать:

- план питания;
- оставшиеся КБЖУ;
- продукты дома;
- предпочтения;
- ограничения.

---

> Освободи мне завтра вечер.

MIRA анализирует расписание и предлагает изменения.

ВАЖНО:

**MIRA не должна самостоятельно выполнять значимые изменения без
подтверждения пользователя.**

Сначала:

`Предложение → Предпросмотр → Подтверждение → Изменение данных`

---

# 🧠 Архитектурный принцип

Модули MIRA должны быть связаны между собой.

Пример:

Event
↓
Weather
↓
Outfit suggestion
↓
PlannedOutfit
↓
Today

Другой пример:

Pantry
↓
MealPlan
↓
MealEntry
↓
Today

Не создавать дублирующие данные без необходимости.

---

# 📂 Структура Flutter-проекта

Планируемая структура:

lib/
│
├── main.dart
│
├── app/
│   ├── app.dart
│   ├── router/
│   └── theme/
│
├── features/
│   ├── onboarding/
│   ├── today/
│   ├── planner/
│   ├── style/
│   ├── nutrition/
│   └── profile/
│
├── shared/
│   ├── widgets/
│   ├── models/
│   ├── extensions/
│   └── utils/
│
└── services/
    ├── database/
    ├── auth/
    ├── storage/
    ├── ai/
    └── weather/

Каждая крупная функция должна находиться внутри соответствующего feature.

Не складывать всю бизнес-логику в `main.dart`.

---

# 💻 Среды разработки

## macOS

Используется для:

- Flutter-разработки;
- iOS;
- Android;
- iPhone Simulator;
- Android Emulator.

Необходимы:

- Git
- Flutter
- VS Code
- Android Studio
- Xcode

## Windows

Используется для:

- Flutter-разработки;
- Android;
- Android Emulator.

Необходимы:

- Git
- Flutter
- VS Code
- Android Studio

iOS локально на Windows не собирается.

---

# 🚀 Первый запуск

Проверить Flutter:

flutter doctor

Получить зависимости:

flutter pub get

Запустить приложение:

flutter run

Проверить устройства:

flutter devices

---

# 🌿 Git Workflow

Главная стабильная ветка:

`main`

Не разрабатываем новые функции напрямую в `main`.

Для каждой задачи создаётся отдельная ветка.

Примеры:

feature/onboarding
feature/today
feature/planner
feature/wardrobe
feature/nutrition

Исправления:

fix/android-navigation
fix/ios-layout

Рефакторинг:

refactor/outfit-model

---

# 🔄 Работа над новой функцией

Перед началом:

git checkout main
git pull

Создать ветку:

git checkout -b feature/name

После работы:

git add .
git commit -m "feat: add feature name"
git push -u origin feature/name

После этого создаётся Pull Request.

После проверки ветка объединяется с `main`.

---

# ✍️ Commit Convention

Используем короткие понятные сообщения.

feat: новая функция

fix: исправление ошибки

ui: изменение интерфейса

refactor: изменение структуры без новой функции

docs: документация

test: тесты

chore: технические изменения

Примеры:

feat: add onboarding flow
ui: add MIRA bottom navigation
fix: correct Android card spacing
refactor: extract outfit model
docs: update README

---

# 👥 Работа вдвоём

Нельзя одновременно независимо изменять один и тот же большой файл без
необходимости.

Перед началом крупной задачи желательно определить, кто над ней работает.

Пример:

Аня:
feature/onboarding

Брат:
feature/planner

После завершения:

Pull Request → Review → Merge

Если изменение затрагивает архитектуру всего приложения, сначала обсуждаем
решение, затем пишем код.

---

# 🍎🤖 Проверка платформ

Функция не считается полностью готовой, пока не проверено, что интерфейс
корректно работает на обеих платформах.

Минимально проверяем:

- iOS
- Android

Особое внимание:

- отступам;
- клавиатуре;
- системным разрешениям;
- навигации;
- safe area;
- размерам экранов;
- dark/light system behaviour;
- работе Back на Android.

---

# 🔐 Безопасность

Никогда не коммитить:

- API secret keys;
- service role keys;
- пароли;
- приватные сертификаты;
- production credentials.

Секреты должны находиться вне Git-репозитория.

Особенно важно:

**Supabase service_role key никогда не должен находиться внутри
Flutter-приложения.**

Пользовательские данные должны защищаться через Row Level Security.

---

# 📦 MVP 1.0

Основная цель первой версии:

- onboarding;
- профиль;
- Today;
- календарь;
- задачи;
- гардероб;
- образы;
- питание;
- базовые настройки;
- связи между модулями;
- MIRA AI.

---

# 🚧 Не входит в первый MVP

Пока не реализуем:

- социальную сеть;
- друзей;
- маркетплейс;
- виртуальную примерку;
- сложный fitness tracker;
- автоматическую покупку продуктов;
- финансы;
- медицинские рекомендации;
- полноценный beauty planner.

Не добавлять новую крупную функцию в MVP без предварительного обсуждения.

---

# 🎯 Milestones

## Alpha 0.1 — App Shell

- Flutter project
- MIRA theme
- onboarding shell
- Today
- Plan
- Style
- Nutrition
- Profile
- bottom navigation

## Alpha 0.2 — Planner

- events
- tasks
- calendar

## Alpha 0.3 — Style

- wardrobe
- wardrobe item
- outfits
- planned outfits

## Alpha 0.4 — Nutrition

- food
- meals
- recipes
- meal planning
- pantry

## Alpha 0.5 — Connected MIRA

- Today receives real data
- modules communicate
- notifications
- weather

## Alpha 0.6 — MIRA AI

- contextual assistant
- structured suggestions
- confirmation before actions

## Beta

- authentication
- cloud sync
- offline behaviour
- iOS testing
- Android testing
- bug fixing
- performance
- accessibility

## MIRA 1.0

First public release.

---

# 💎 Главное правило проекта

MIRA не должна превращаться в набор трекеров.

Перед добавлением функции задаём вопрос:

> Делает ли она жизнь пользователя проще и связывается ли она с остальной MIRA?

Если функция только добавляет ещё одно место, которое пользователь обязан
заполнять, её необходимость нужно пересмотреть.

---

MIRA ✦

**Больше, чем планы.**
