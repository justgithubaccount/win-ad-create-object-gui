# Active Directory Create User GUI

Форма для создания пользователя Active Directory. Основное приложение написано на PowerShell и WPF; XAML лежит в `XAML/ADOperatorWindows.xaml`.

## Запуск на Windows

```powershell
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File .\ADOperatorWindows.ps1
```

Окно открывается без Active Directory. При загрузке списков групп и руководителей скрипт обращается к AD; при недоступном модуле или домене списки останутся пустыми, а причина появится в консоли. Кнопка «Создать» вызывает `New-ADUser`, поэтому для неё нужны модуль Active Directory, доступ к домену и права на создание пользователей. Сейчас домен `rsvet.ru`, OU, группа руководителей и OU групп заданы в конце скрипта. Перед реальным созданием пользователя измените эти значения под свою инфраструктуру.

Имя, фамилия, логин и пароль обязательны. Пароль вводится в скрытое поле и не показывается в предварительном просмотре. Компания, отдел, должность, email, телефон, описание, область, город и комната передаются в `New-ADUser`, если заполнены. Страна, выбранная ролевая группа и руководитель пока не сохраняются в AD. Тип учётной записи подставляет отдел и должность, но сам по себе не задаёт отдельный атрибут AD.

## Просмотр формы на Linux

Откройте `preview.html` в браузере, например:

```bash
xdg-open preview.html
```

Это локальная версия формы для просмотра и заполнения полей. Она не подключается к AD и не создаёт пользователя. WPF приложение на Linux не запускается.

## Материалы PoSHPF

Основа WPF скрипта — [PowerShell Presentation Framework](https://github.com/theznerd/PoSHPF). Статьи автора доступны по архивным адресам:

1. [Создание и загрузка XAML](https://archive.z-nerd.com/blog/2019/05/27-posh-presentation-framework-part-1/)
2. [Обработчики элементов формы](https://archive.z-nerd.com/blog/2019/05/28-posh-presentation-framework-part-2/)
3. [Медиа-ресурсы](https://archive.z-nerd.com/blog/2019/05/29-posh-presentation-framework-part-3/)
4. [Разметка формы](https://archive.z-nerd.com/blog/2019/05/30-posh-presentation-framework-part-4/)

[Список сокращений для имён элементов управления](https://gist.github.com/andyyou/3052671).
