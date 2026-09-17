# Каталог кандидатов для каркаса

Список — отправная точка для поиска (составлен 16.09.2026).
Перед выбором проверить актуальность, версии и совместимость (`compat-check`).

## Библиотеки компонентов и дизайн-системы
| Стек | Кандидаты | Чем полезны |
|---|---|---|
| React / Next.js | shadcn/ui (+ готовые blocks, редакторы тем на CSS-переменных), Mantine, Ant Design, MUI | shadcn — код компонентов в проекте, темы на переменных; Ant Design — много готового для админок |
| React-админки, CRUD | Refine, React-Admin | готовые списки, формы, фильтры, права поверх API |
| Vue / Nuxt | Nuxt UI, PrimeVue, Vuetify | темы, готовые компоненты |
| Любой стек с Tailwind (в т.ч. Django, PHP, шаблоны) | daisyUI, Flowbite | классы компонентов и десятки тем без JavaScript |
| Без Tailwind, серверные шаблоны | Bootstrap, Tabler | классика, готовые админ-шаблоны |
| Мобильные (React Native / Expo) | React Native Paper, Tamagui, gluestack-ui | темы, адаптация под iOS/Android |

## Графики и дашборды
Recharts, Apache ECharts, Chart.js, Tremor (блоки дашбордов для React).

## Медиа для сайтов
- Изображения: sharp (Node), Pillow (Python), форматы WebP/AVIF.
- Видео: FFmpeg (сжатие, превью, форматы для веба).
- Анимация: GSAP, Motion (Framer Motion), Lottie.
- 3D: three.js, React Three Fiber.

## Вход и пользователи
Auth.js, Better Auth, Lucia-подобные решения (Node); Django auth, Laravel Breeze;
внешние: Supabase Auth, Clerk, Keycloak. Выбор — по стеку и где хранятся данные.

## Скиллы для Claude по интерфейсу
- `frontend-design` (Anthropic) — оформление интерфейсов.
- Скиллы авторов библиотек (например, daisyUI) — точный код под библиотеку.
Искать и ставить через `tool-scout`.
