// Ключи настроек уведомлений приложения: по умолчанию все включены.
const kNotifGoalsKey = 'notif_goals';
const kNotifWorkoutsKey = 'notif_workouts';

bool notifEnabled(Map<String, String> settings, String key) => settings[key] != '0';
